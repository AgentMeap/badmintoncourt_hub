package com.badminton.v2.routing;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;

/**
 * Đồ thị đường dạng mảng nén (CSR): cạnh ra của đỉnh v nằm ở [first[v], first[v+1]).
 * Bất biến sau khi dựng nên dùng chung an toàn cho nhiều luồng.
 */
public final class RoadGraph {

    private static final int MAGIC = 0x424D5247; // "BMRG"
    private static final int VERSION = 1;

    final double[] lat;
    final double[] lon;
    final int[] first;
    final int[] target;
    final float[] length;
    final int[] edgeWay;
    final byte[] flags;
    final byte[] wayClass;
    final int[] wayName;
    final float[] wayCap;
    final String[] names;

    /** Phương tiện đi được tại mỗi đỉnh (OR cờ các cạnh vào + ra) – để bắt điểm gần đúng loại đường. */
    final byte[] vertexModes;

    // Lưới chia ô để tìm đỉnh gần nhất
    private static final double CELL_DEG = 0.0025; // ~275 m
    private final double minLat, minLon;
    private final int rows, cols;
    private final int[] cellStart;
    private final int[] cellVertices;

    RoadGraph(double[] lat, double[] lon, int[] first, int[] target, float[] length, int[] edgeWay, byte[] flags,
              byte[] wayClass, int[] wayName, float[] wayCap, String[] names) {
        this.lat = lat;
        this.lon = lon;
        this.first = first;
        this.target = target;
        this.length = length;
        this.edgeWay = edgeWay;
        this.flags = flags;
        this.wayClass = wayClass;
        this.wayName = wayName;
        this.wayCap = wayCap;
        this.names = names;

        int n = lat.length;
        vertexModes = new byte[n];
        for (int v = 0; v < n; v++) {
            for (int e = first[v]; e < first[v + 1]; e++) {
                vertexModes[v] |= flags[e];
                vertexModes[target[e]] |= flags[e];
            }
        }

        double mnLat = 90, mnLon = 180, mxLat = -90, mxLon = -180;
        for (int v = 0; v < n; v++) {
            mnLat = Math.min(mnLat, lat[v]);
            mxLat = Math.max(mxLat, lat[v]);
            mnLon = Math.min(mnLon, lon[v]);
            mxLon = Math.max(mxLon, lon[v]);
        }
        if (n == 0) {
            mnLat = mnLon = mxLat = mxLon = 0;
        }
        minLat = mnLat;
        minLon = mnLon;
        rows = Math.max(1, (int) ((mxLat - mnLat) / CELL_DEG) + 1);
        cols = Math.max(1, (int) ((mxLon - mnLon) / CELL_DEG) + 1);
        cellStart = new int[rows * cols + 1];
        int[] cellOf = new int[n];
        for (int v = 0; v < n; v++) {
            cellOf[v] = cellIndex(row(lat[v]), col(lon[v]));
            cellStart[cellOf[v] + 1]++;
        }
        for (int c = 0; c < rows * cols; c++) cellStart[c + 1] += cellStart[c];
        cellVertices = new int[n];
        int[] cursor = cellStart.clone();
        for (int v = 0; v < n; v++) cellVertices[cursor[cellOf[v]]++] = v;
    }

    public int vertexCount() {
        return lat.length;
    }

    public int edgeCount() {
        return target.length;
    }

    public double lat(int v) {
        return lat[v];
    }

    public double lon(int v) {
        return lon[v];
    }

    /** [minLat, minLon, maxLat, maxLon] của vùng có dữ liệu. */
    public double[] bounds() {
        return new double[]{minLat, minLon, minLat + rows * CELL_DEG, minLon + cols * CELL_DEG};
    }

    boolean allows(int edge, TravelMode mode) {
        return (flags[edge] & mode.flag) != 0;
    }

    RoadClass roadClass(int edge) {
        return RoadClass.values()[wayClass[edgeWay[edge]]];
    }

    /** Tên đường của cạnh, null nếu không có tên. */
    String name(int edge) {
        int idx = wayName[edgeWay[edge]];
        return idx < 0 ? null : names[idx];
    }

    int nameIndex(int edge) {
        return wayName[edgeWay[edge]];
    }

    /** Tốc độ (m/s) của phương tiện trên cạnh, có xét biển giới hạn tốc độ. */
    double speedMps(int edge, TravelMode mode) {
        double kmh = roadClass(edge).speedKmh(mode);
        float cap = wayCap[edgeWay[edge]];
        if (mode != TravelMode.WALK && cap > 0) kmh = Math.min(kmh, cap * 0.8);
        return Math.max(kmh, 1) / 3.6;
    }

    // ------------------------------------------------------------------ tìm đỉnh gần

    private int row(double la) {
        return Math.min(rows - 1, Math.max(0, (int) ((la - minLat) / CELL_DEG)));
    }

    private int col(double lo) {
        return Math.min(cols - 1, Math.max(0, (int) ((lo - minLon) / CELL_DEG)));
    }

    private int cellIndex(int r, int c) {
        return r * cols + c;
    }

    /**
     * Tối đa [k] đỉnh gần ([lat],[lon]) nhất mà phương tiện đi được, trong bán kính [maxMeters].
     * Trả về mảng chỉ số đỉnh sắp theo khoảng cách tăng dần (có thể rỗng).
     */
    public int[] nearest(double la, double lo, TravelMode mode, double maxMeters, int k) {
        if (lat.length == 0) return new int[0];
        double[] bestD = new double[k];
        int[] best = new int[k];
        java.util.Arrays.fill(bestD, Double.MAX_VALUE);
        java.util.Arrays.fill(best, -1);
        double cellMeters = CELL_DEG * 111_000 * Math.cos(Math.toRadians(la));
        int maxRing = (int) Math.ceil(maxMeters / Math.max(1, cellMeters)) + 1;
        int r0 = (int) Math.floor((la - minLat) / CELL_DEG);
        int c0 = (int) Math.floor((lo - minLon) / CELL_DEG);
        for (int ring = 0; ring <= maxRing; ring++) {
            // Mọi đỉnh ở vòng này cách ít nhất (ring - 1) ô: dừng khi đã đủ k và không thể gần hơn
            if (best[k - 1] >= 0 && (ring - 1) * cellMeters > bestD[k - 1]) break;
            for (int r = r0 - ring; r <= r0 + ring; r++) {
                if (r < 0 || r >= rows) continue;
                for (int c = c0 - ring; c <= c0 + ring; c++) {
                    if (c < 0 || c >= cols) continue;
                    if (Math.abs(r - r0) != ring && Math.abs(c - c0) != ring) continue; // chỉ viền vòng
                    int cell = cellIndex(r, c);
                    for (int i = cellStart[cell]; i < cellStart[cell + 1]; i++) {
                        int v = cellVertices[i];
                        if ((vertexModes[v] & mode.flag) == 0) continue;
                        double d = Geo.distanceM(la, lo, lat[v], lon[v]);
                        if (d > maxMeters || d >= bestD[k - 1]) continue;
                        int pos = k - 1;
                        while (pos > 0 && bestD[pos - 1] > d) {
                            bestD[pos] = bestD[pos - 1];
                            best[pos] = best[pos - 1];
                            pos--;
                        }
                        bestD[pos] = d;
                        best[pos] = v;
                    }
                }
            }
        }
        int count = 0;
        while (count < k && best[count] >= 0) count++;
        return java.util.Arrays.copyOf(best, count);
    }

    // ------------------------------------------------------------------ lưu / đọc file

    /** Ghi ra file (nén gzip). Ghi vào file tạm rồi đổi tên để không bao giờ để lại file hỏng. */
    public void save(Path file) throws IOException {
        Files.createDirectories(file.toAbsolutePath().getParent());
        Path tmp = file.resolveSibling(file.getFileName() + ".tmp");
        try (DataOutputStream out = new DataOutputStream(new BufferedOutputStream(
                new GZIPOutputStream(Files.newOutputStream(tmp), 1 << 16), 1 << 16))) {
            out.writeInt(MAGIC);
            out.writeInt(VERSION);
            int n = lat.length, m = target.length, w = wayClass.length;
            out.writeInt(n);
            out.writeInt(m);
            out.writeInt(w);
            out.writeInt(names.length);
            for (int i = 0; i < n; i++) {
                out.writeDouble(lat[i]);
                out.writeDouble(lon[i]);
            }
            for (int i = 0; i <= n; i++) out.writeInt(first[i]);
            for (int i = 0; i < m; i++) {
                out.writeInt(target[i]);
                out.writeFloat(length[i]);
                out.writeInt(edgeWay[i]);
                out.writeByte(flags[i]);
            }
            for (int i = 0; i < w; i++) {
                out.writeByte(wayClass[i]);
                out.writeInt(wayName[i]);
                out.writeFloat(wayCap[i]);
            }
            for (String s : names) {
                byte[] b = s.getBytes(StandardCharsets.UTF_8);
                out.writeShort(b.length);
                out.write(b);
            }
        }
        Files.move(tmp, file, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
    }

    public static RoadGraph load(Path file) throws IOException {
        try (DataInputStream in = new DataInputStream(new BufferedInputStream(
                new GZIPInputStream(Files.newInputStream(file), 1 << 16), 1 << 16))) {
            if (in.readInt() != MAGIC) throw new IOException("Không phải file đồ thị đường: " + file);
            int version = in.readInt();
            if (version != VERSION) throw new IOException("Phiên bản đồ thị không hỗ trợ: " + version);
            int n = in.readInt(), m = in.readInt(), w = in.readInt(), nn = in.readInt();
            double[] lat = new double[n], lon = new double[n];
            for (int i = 0; i < n; i++) {
                lat[i] = in.readDouble();
                lon[i] = in.readDouble();
            }
            int[] first = new int[n + 1];
            for (int i = 0; i <= n; i++) first[i] = in.readInt();
            int[] target = new int[m], edgeWay = new int[m];
            float[] length = new float[m];
            byte[] flags = new byte[m];
            for (int i = 0; i < m; i++) {
                target[i] = in.readInt();
                length[i] = in.readFloat();
                edgeWay[i] = in.readInt();
                flags[i] = in.readByte();
            }
            byte[] wayClass = new byte[w];
            int[] wayName = new int[w];
            float[] wayCap = new float[w];
            for (int i = 0; i < w; i++) {
                wayClass[i] = in.readByte();
                wayName[i] = in.readInt();
                wayCap[i] = in.readFloat();
            }
            String[] names = new String[nn];
            for (int i = 0; i < nn; i++) {
                byte[] b = new byte[in.readUnsignedShort()];
                in.readFully(b);
                names[i] = new String(b, StandardCharsets.UTF_8);
            }
            return new RoadGraph(lat, lon, first, target, length, edgeWay, flags, wayClass, wayName, wayCap, names);
        }
    }
}
