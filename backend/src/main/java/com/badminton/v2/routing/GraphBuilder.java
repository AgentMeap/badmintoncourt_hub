package com.badminton.v2.routing;

import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

/**
 * Dựng đồ thị đường từ dữ liệu OpenStreetMap (nút + đường).
 * Nút và đường có thể đến theo bất kỳ thứ tự nào, trùng lặp (các ô tải chồng lên nhau) cũng được.
 *
 * Quy tắc:
 * - Mỗi nút OSM thuộc đường đi được là một đỉnh; mỗi đoạn giữa 2 nút liên tiếp là một cạnh có hướng.
 * - Đường một chiều (oneway, vòng xuyến) chỉ có cạnh xuôi cho xe; đi bộ được đi cả 2 chiều.
 * - Thẻ cấm (access/motor_vehicle/motorcycle/motorcar/foot = no) loại phương tiện tương ứng.
 */
public class GraphBuilder {

    // ---- nút (có thể trùng) ----
    private long[] nodeIds = new long[1 << 16];
    private double[] nodeLat = new double[1 << 16];
    private double[] nodeLon = new double[1 << 16];
    private int nodeCount;

    // ---- đường đã nhận ----
    private final Set<Long> seenWays = new HashSet<>();
    private long[] refs = new long[1 << 16];
    private int refCount;
    private int[] wayRefStart = new int[1 << 12];
    private byte[] wayClass = new byte[1 << 12];
    private byte[] wayFwd = new byte[1 << 12];
    private byte[] wayBwd = new byte[1 << 12];
    private int[] wayName = new int[1 << 12];
    private float[] wayCap = new float[1 << 12];
    private int wayCount;

    private final Map<String, Integer> nameIndex = new HashMap<>();
    private String[] names = new String[256];
    private int nameCount;

    public void addNode(long id, double lat, double lon) {
        if (nodeCount == nodeIds.length) {
            int n = nodeIds.length * 2;
            nodeIds = Arrays.copyOf(nodeIds, n);
            nodeLat = Arrays.copyOf(nodeLat, n);
            nodeLon = Arrays.copyOf(nodeLon, n);
        }
        nodeIds[nodeCount] = id;
        nodeLat[nodeCount] = lat;
        nodeLon[nodeCount] = lon;
        nodeCount++;
    }

    /** Trả về false nếu đường bị bỏ qua (không đi được hoặc đã nhận). */
    public boolean addWay(long wayId, long[] nodeRefs, Map<String, String> tags) {
        if (nodeRefs == null || nodeRefs.length < 2 || !seenWays.add(wayId)) return false;
        RoadClass rc = RoadClass.of(tags.get("highway"));
        if (rc == null || "yes".equals(tags.get("area"))) return false;

        int allowed = allowedModes(rc, tags);
        if (allowed == 0) return false;

        // Một chiều chỉ áp dụng cho xe; đi bộ luôn đi được 2 chiều
        int vehicles = allowed & (TravelMode.CAR.flag | TravelMode.MOTORBIKE.flag);
        int walk = allowed & TravelMode.WALK.flag;
        int oneway = onewayDirection(tags, TravelMode.CAR);
        int onewayMoto = "no".equals(tags.get("oneway:motorcycle")) ? 0 : oneway;
        int fwd = walk, bwd = walk;
        for (TravelMode m : new TravelMode[]{TravelMode.CAR, TravelMode.MOTORBIKE}) {
            if ((vehicles & m.flag) == 0) continue;
            int dir = m == TravelMode.MOTORBIKE ? onewayMoto : oneway;
            if (dir >= 0) fwd |= m.flag;
            if (dir <= 0) bwd |= m.flag;
        }

        ensureWayCapacity();
        ensureRefCapacity(nodeRefs.length);
        wayRefStart[wayCount] = refCount;
        System.arraycopy(nodeRefs, 0, refs, refCount, nodeRefs.length);
        refCount += nodeRefs.length;
        wayClass[wayCount] = (byte) rc.ordinal();
        wayFwd[wayCount] = (byte) fwd;
        wayBwd[wayCount] = (byte) bwd;
        wayName[wayCount] = nameOf(tags);
        wayCap[wayCount] = maxSpeedKmh(tags.get("maxspeed"));
        wayCount++;
        return true;
    }

    static int allowedModes(RoadClass rc, Map<String, String> tags) {
        int modes = 0;
        for (TravelMode m : TravelMode.values()) {
            if (rc.speedKmh(m) > 0) modes |= m.flag;
        }
        String access = tags.get("access");
        if ("no".equals(access) || "private".equals(access)) modes = 0;
        if (isNo(tags.get("motor_vehicle"))) modes &= ~(TravelMode.CAR.flag | TravelMode.MOTORBIKE.flag);
        if (isNo(tags.get("motorcar"))) modes &= ~TravelMode.CAR.flag;
        if (isNo(tags.get("motorcycle"))) modes &= ~TravelMode.MOTORBIKE.flag;
        if (isNo(tags.get("foot"))) modes &= ~TravelMode.WALK.flag;
        // Cho phép tường minh (VD lối đi nhưng xe máy được vào)
        if (isYes(tags.get("motorcycle")) && rc != RoadClass.MOTORWAY && rc != RoadClass.MOTORWAY_LINK) {
            modes |= TravelMode.MOTORBIKE.flag;
        }
        if (isYes(tags.get("foot")) || "designated".equals(tags.get("foot"))) modes |= TravelMode.WALK.flag;
        return modes;
    }

    private static boolean isNo(String v) {
        return "no".equals(v) || "private".equals(v);
    }

    private static boolean isYes(String v) {
        return "yes".equals(v) || "designated".equals(v) || "permissive".equals(v);
    }

    /** 1 = chỉ đi xuôi, -1 = chỉ đi ngược, 0 = hai chiều. */
    static int onewayDirection(Map<String, String> tags, TravelMode mode) {
        String ow = tags.get("oneway");
        if ("-1".equals(ow) || "reverse".equals(ow)) return -1;
        if ("yes".equals(ow) || "1".equals(ow) || "true".equals(ow)) return 1;
        if ("no".equals(ow)) return 0;
        String junction = tags.get("junction");
        if ("roundabout".equals(junction) || "circular".equals(junction)) return 1;
        String hw = tags.get("highway");
        if ("motorway".equals(hw)) return 1;
        return 0;
    }

    static float maxSpeedKmh(String raw) {
        if (raw == null) return 0;
        String digits = raw.replaceAll("[^0-9.]", "");
        if (digits.isEmpty()) return 0;
        try {
            float v = Float.parseFloat(digits);
            if (raw.contains("mph")) v *= 1.609f;
            return v > 0 && v < 200 ? v : 0;
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    private int nameOf(Map<String, String> tags) {
        String name = tags.get("name:vi");
        if (name == null || name.isBlank()) name = tags.get("name");
        if (name == null || name.isBlank()) name = tags.get("ref");
        if (name == null || name.isBlank()) return -1;
        name = name.trim();
        Integer idx = nameIndex.get(name);
        if (idx != null) return idx;
        if (nameCount == names.length) names = Arrays.copyOf(names, names.length * 2);
        names[nameCount] = name;
        nameIndex.put(name, nameCount);
        return nameCount++;
    }

    private void ensureWayCapacity() {
        if (wayCount < wayClass.length) return;
        int n = wayClass.length * 2;
        wayRefStart = Arrays.copyOf(wayRefStart, n);
        wayClass = Arrays.copyOf(wayClass, n);
        wayFwd = Arrays.copyOf(wayFwd, n);
        wayBwd = Arrays.copyOf(wayBwd, n);
        wayName = Arrays.copyOf(wayName, n);
        wayCap = Arrays.copyOf(wayCap, n);
    }

    private void ensureRefCapacity(int extra) {
        if (refCount + extra <= refs.length) return;
        refs = Arrays.copyOf(refs, Math.max(refs.length * 2, refCount + extra));
    }

    public int wayCount() {
        return wayCount;
    }

    /** Dựng đồ thị dạng mảng (CSR). Các đoạn có nút không tải được bị bỏ qua. */
    public RoadGraph build() {
        // 1. Sắp xếp + bỏ trùng nút theo id
        long[] sortedIds;
        double[] lat, lon;
        {
            int[] idx = sortIndicesById();
            int unique = 0;
            sortedIds = new long[nodeCount];
            lat = new double[nodeCount];
            lon = new double[nodeCount];
            long prev = Long.MIN_VALUE;
            for (int k = 0; k < nodeCount; k++) {
                int i = idx[k];
                if (nodeIds[i] == prev) continue;
                prev = nodeIds[i];
                sortedIds[unique] = nodeIds[i];
                lat[unique] = nodeLat[i];
                lon[unique] = nodeLon[i];
                unique++;
            }
            sortedIds = Arrays.copyOf(sortedIds, unique);
            lat = Arrays.copyOf(lat, unique);
            lon = Arrays.copyOf(lon, unique);
        }

        // 2. Đánh dấu nút được đường sử dụng -> đỉnh của đồ thị
        int[] vertexOf = new int[sortedIds.length];
        Arrays.fill(vertexOf, -1);
        int vertexCount = 0;
        for (int w = 0; w < wayCount; w++) {
            int end = w + 1 < wayCount ? wayRefStart[w + 1] : refCount;
            for (int r = wayRefStart[w]; r < end; r++) {
                int ni = Arrays.binarySearch(sortedIds, refs[r]);
                if (ni >= 0 && vertexOf[ni] < 0) vertexOf[ni] = vertexCount++;
            }
        }
        double[] vLat = new double[vertexCount];
        double[] vLon = new double[vertexCount];
        for (int ni = 0; ni < sortedIds.length; ni++) {
            int v = vertexOf[ni];
            if (v >= 0) {
                vLat[v] = lat[ni];
                vLon[v] = lon[ni];
            }
        }

        // 3. Đếm cạnh theo đỉnh nguồn, rồi điền (counting sort -> CSR)
        int[] outDeg = new int[vertexCount + 1];
        int edgeCount = 0;
        for (int pass = 0; pass < 2; pass++) {
            int[] cursor = pass == 1 ? outDeg.clone() : null;
            int[] target = pass == 1 ? new int[edgeCount] : null;
            float[] length = pass == 1 ? new float[edgeCount] : null;
            int[] edgeWay = pass == 1 ? new int[edgeCount] : null;
            byte[] flags = pass == 1 ? new byte[edgeCount] : null;
            for (int w = 0; w < wayCount; w++) {
                int end = w + 1 < wayCount ? wayRefStart[w + 1] : refCount;
                for (int r = wayRefStart[w]; r + 1 < end; r++) {
                    int a = vertexIndex(sortedIds, vertexOf, refs[r]);
                    int b = vertexIndex(sortedIds, vertexOf, refs[r + 1]);
                    if (a < 0 || b < 0 || a == b) continue;
                    if (pass == 0) {
                        if (wayFwd[w] != 0) {
                            outDeg[a + 1]++;
                            edgeCount++;
                        }
                        if (wayBwd[w] != 0) {
                            outDeg[b + 1]++;
                            edgeCount++;
                        }
                    } else {
                        float len = (float) Geo.distanceM(vLat[a], vLon[a], vLat[b], vLon[b]);
                        if (wayFwd[w] != 0) {
                            int e = cursor[a]++;
                            target[e] = b;
                            length[e] = len;
                            edgeWay[e] = w;
                            flags[e] = wayFwd[w];
                        }
                        if (wayBwd[w] != 0) {
                            int e = cursor[b]++;
                            target[e] = a;
                            length[e] = len;
                            edgeWay[e] = w;
                            flags[e] = wayBwd[w];
                        }
                    }
                }
            }
            if (pass == 0) {
                for (int v = 0; v < vertexCount; v++) outDeg[v + 1] += outDeg[v];
            } else {
                return new RoadGraph(vLat, vLon, outDeg, target, length, edgeWay, flags,
                        Arrays.copyOf(wayClass, wayCount), Arrays.copyOf(wayName, wayCount),
                        Arrays.copyOf(wayCap, wayCount), Arrays.copyOf(names, nameCount));
            }
        }
        throw new IllegalStateException("unreachable");
    }

    private static int vertexIndex(long[] sortedIds, int[] vertexOf, long osmId) {
        int ni = Arrays.binarySearch(sortedIds, osmId);
        return ni < 0 ? -1 : vertexOf[ni];
    }

    /** Chỉ số các nút sắp theo id OSM (quicksort trên 2 mảng song song, không tạo object). */
    private int[] sortIndicesById() {
        long[] ids = Arrays.copyOf(nodeIds, nodeCount);
        int[] idx = new int[nodeCount];
        for (int i = 0; i < nodeCount; i++) idx[i] = i;
        quickSort(ids, idx, 0, nodeCount - 1);
        return idx;
    }

    private static void quickSort(long[] keys, int[] idx, int lo, int hi) {
        while (lo < hi) {
            if (hi - lo < 16) {
                for (int i = lo + 1; i <= hi; i++) {
                    long k = keys[i];
                    int v = idx[i];
                    int j = i - 1;
                    while (j >= lo && keys[j] > k) {
                        keys[j + 1] = keys[j];
                        idx[j + 1] = idx[j];
                        j--;
                    }
                    keys[j + 1] = k;
                    idx[j + 1] = v;
                }
                return;
            }
            long pivot = keys[(lo + hi) >>> 1];
            int i = lo, j = hi;
            while (i <= j) {
                while (keys[i] < pivot) i++;
                while (keys[j] > pivot) j--;
                if (i <= j) {
                    long tk = keys[i];
                    keys[i] = keys[j];
                    keys[j] = tk;
                    int tv = idx[i];
                    idx[i] = idx[j];
                    idx[j] = tv;
                    i++;
                    j--;
                }
            }
            // Đệ quy phần nhỏ hơn để giới hạn độ sâu ngăn xếp
            if (j - lo < hi - i) {
                quickSort(keys, idx, lo, j);
                lo = i;
            } else {
                quickSort(keys, idx, i, hi);
                hi = j;
            }
        }
    }
}
