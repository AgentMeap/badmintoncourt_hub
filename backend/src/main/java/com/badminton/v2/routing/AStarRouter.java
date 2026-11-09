package com.badminton.v2.routing;

import java.util.Arrays;

/**
 * Tìm đường nhanh nhất (theo thời gian) bằng A*.
 * - Chi phí cạnh = chiều dài / tốc độ của phương tiện trên loại đường đó.
 * - Hàm ước lượng = khoảng cách đường chim bay / tốc độ lớn nhất của phương tiện
 *   (không bao giờ đánh giá quá chi phí thật nên A* luôn cho đường tối ưu).
 * Mỗi luồng có vùng nhớ làm việc riêng (đánh dấu theo "thế hệ" nên không phải xoá mảng mỗi lần).
 */
public final class AStarRouter {

    private final RoadGraph g;
    private final ThreadLocal<Workspace> workspace;

    public AStarRouter(RoadGraph graph) {
        this.g = graph;
        this.workspace = ThreadLocal.withInitial(() -> new Workspace(graph.vertexCount()));
    }

    /** Kết quả: các cạnh theo thứ tự đi, tổng thời gian (giây) và số đỉnh đã duyệt. */
    public record Path(int[] edges, double seconds, int visited) {}

    /** null nếu không có đường đi. [maxVisited] giới hạn số đỉnh duyệt (chống treo máy chủ). */
    public Path route(int from, int to, TravelMode mode, int maxVisited) {
        if (from == to) return new Path(new int[0], 0, 0);
        Workspace w = workspace.get();
        int gen = w.nextGeneration();
        double inv = 1.0 / mode.maxSpeedMps();
        double toLat = g.lat[to], toLon = g.lon[to];

        w.open(from, gen, 0, -1);
        w.heap.push(from, (float) (Geo.distanceM(g.lat[from], g.lon[from], toLat, toLon) * inv));
        int visited = 0;

        while (!w.heap.isEmpty()) {
            int v = w.heap.pop();
            if (w.closed[v] == gen) continue;
            w.closed[v] = gen;
            if (v == to) return new Path(w.pathTo(to, g), w.cost[to], visited);
            if (++visited > maxVisited) return null;

            double base = w.cost[v];
            for (int e = g.first[v]; e < g.first[v + 1]; e++) {
                if ((g.flags[e] & mode.flag) == 0) continue;
                int u = g.target[e];
                if (w.closed[u] == gen) continue;
                double c = base + g.length[e] / g.speedMps(e, mode);
                if (w.seen[u] != gen || c < w.cost[u]) {
                    w.open(u, gen, c, e);
                    double h = Geo.distanceM(g.lat[u], g.lon[u], toLat, toLon) * inv;
                    w.heap.push(u, (float) (c + h));
                }
            }
        }
        return null;
    }

    private static final class Workspace {
        final double[] cost;
        final int[] prevEdge;
        final int[] seen;
        final int[] closed;
        final MinHeap heap = new MinHeap();
        int generation;

        Workspace(int n) {
            cost = new double[n];
            prevEdge = new int[n];
            seen = new int[n];
            closed = new int[n];
        }

        int nextGeneration() {
            heap.clear();
            if (++generation == Integer.MAX_VALUE) {
                Arrays.fill(seen, 0);
                Arrays.fill(closed, 0);
                generation = 1;
            }
            return generation;
        }

        void open(int v, int gen, double c, int viaEdge) {
            seen[v] = gen;
            cost[v] = c;
            prevEdge[v] = viaEdge;
        }

        int[] pathTo(int to, RoadGraph g) {
            int count = 0;
            for (int e = prevEdge[to]; e >= 0; e = prevEdge[source(g, e)]) count++;
            int[] edges = new int[count];
            int i = count;
            for (int e = prevEdge[to]; e >= 0; e = prevEdge[source(g, e)]) edges[--i] = e;
            return edges;
        }

        /** Đỉnh nguồn của cạnh: đỉnh v có first[v] <= e < first[v+1] (tìm nhị phân). */
        private static int source(RoadGraph g, int e) {
            int lo = 0, hi = g.first.length - 2;
            while (lo < hi) {
                int mid = (lo + hi + 1) >>> 1;
                if (g.first[mid] <= e) lo = mid;
                else hi = mid - 1;
            }
            return lo;
        }
    }

    /** Hàng đợi ưu tiên nhị phân trên mảng nguyên thuỷ (cho phép phần tử trùng, bỏ qua khi lấy ra). */
    private static final class MinHeap {
        private float[] keys = new float[1024];
        private int[] vals = new int[1024];
        private int size;

        void clear() {
            size = 0;
        }

        boolean isEmpty() {
            return size == 0;
        }

        void push(int v, float key) {
            if (size == keys.length) {
                keys = Arrays.copyOf(keys, size * 2);
                vals = Arrays.copyOf(vals, size * 2);
            }
            int i = size++;
            while (i > 0) {
                int p = (i - 1) >>> 1;
                if (keys[p] <= key) break;
                keys[i] = keys[p];
                vals[i] = vals[p];
                i = p;
            }
            keys[i] = key;
            vals[i] = v;
        }

        int pop() {
            int top = vals[0];
            size--;
            if (size > 0) {
                float key = keys[size];
                int v = vals[size];
                int i = 0;
                while (true) {
                    int l = 2 * i + 1;
                    if (l >= size) break;
                    int r = l + 1;
                    int c = r < size && keys[r] < keys[l] ? r : l;
                    if (keys[c] >= key) break;
                    keys[i] = keys[c];
                    vals[i] = vals[c];
                    i = c;
                }
                keys[i] = key;
                vals[i] = v;
            }
            return top;
        }
    }
}
