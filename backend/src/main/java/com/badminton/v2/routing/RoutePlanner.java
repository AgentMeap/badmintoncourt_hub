package com.badminton.v2.routing;

import java.util.ArrayList;
import java.util.List;

/**
 * Tìm đường giữa 2 toạ độ bất kỳ: bắt điểm vào đỉnh đồ thị gần nhất -> A* -> hình dạng tuyến + chỉ dẫn.
 * Đoạn từ toạ độ thật tới đỉnh gần nhất (đầu / cuối) được tính như đi bộ / dắt xe.
 */
public final class RoutePlanner {

    /** Bán kính tối đa để bắt điểm vào đường (ngoài khoảng này coi như ngoài vùng có dữ liệu). */
    public static final double MAX_SNAP_METERS = 800;
    private static final int SNAP_CANDIDATES = 3;
    private static final int MAX_VISITED = 2_500_000;
    private static final double APPROACH_SPEED_MPS = 1.4;
    private static final double SIMPLIFY_TOLERANCE_M = 4;

    private final RoadGraph graph;
    private final AStarRouter router;
    private final double trafficFactor;

    public RoutePlanner(RoadGraph graph, double trafficFactor) {
        this.graph = graph;
        this.router = new AStarRouter(graph);
        this.trafficFactor = trafficFactor <= 0 ? 1 : trafficFactor;
    }

    public RoadGraph graph() {
        return graph;
    }

    public static class OutOfCoverageException extends RuntimeException {
        public OutOfCoverageException(String message) {
            super(message);
        }
    }

    public static class NoRouteException extends RuntimeException {
        public NoRouteException(String message) {
            super(message);
        }
    }

    /**
     * Các đỉnh gần nhất để bắt điểm. Chỉ giữ đỉnh dự phòng khi gần ngang đỉnh gần nhất
     * (tránh "đi bộ" một đoạn dài để lách đường một chiều).
     */
    private int[] candidates(double la, double lo, TravelMode mode) {
        int[] near = graph.nearest(la, lo, mode, MAX_SNAP_METERS, SNAP_CANDIDATES);
        if (near.length <= 1) return near;
        double d0 = Geo.distanceM(la, lo, graph.lat[near[0]], graph.lon[near[0]]);
        double limit = Math.max(40, d0 * 1.5);
        int n = 1;
        while (n < near.length && Geo.distanceM(la, lo, graph.lat[near[n]], graph.lon[near[n]]) <= limit) n++;
        return java.util.Arrays.copyOf(near, n);
    }

    public RouteResult route(double fromLat, double fromLng, double toLat, double toLng,
                             TravelMode mode, String destinationName) {
        int[] starts = candidates(fromLat, fromLng, mode);
        if (starts.length == 0) {
            throw new OutOfCoverageException("Vị trí của bạn nằm ngoài vùng bản đồ đường (TP.HCM).");
        }
        int[] ends = candidates(toLat, toLng, mode);
        if (ends.length == 0) {
            throw new OutOfCoverageException("Sân nằm ngoài vùng bản đồ đường.");
        }

        // Thử vài cặp điểm gần nhất (điểm gần nhất có thể nằm trên đoạn một chiều cụt)
        AStarRouter.Path best = null;
        int bestFrom = -1, bestTo = -1;
        int visited = 0;
        outer:
        for (int s : starts) {
            for (int t : ends) {
                AStarRouter.Path p = router.route(s, t, mode, MAX_VISITED);
                if (p != null) visited += p.visited();
                if (p != null) {
                    best = p;
                    bestFrom = s;
                    bestTo = t;
                    break outer;
                }
            }
        }
        if (best == null) throw new NoRouteException("Không tìm được đường đi bằng " + mode.label.toLowerCase() + ".");

        int[] edges = best.edges();
        int[] verts = new int[edges.length + 1];
        verts[0] = bestFrom;
        for (int i = 0; i < edges.length; i++) verts[i + 1] = graph.target[edges[i]];

        // Hình dạng tuyến: toạ độ thật -> các đỉnh -> toạ độ sân
        List<double[]> pts = new ArrayList<>(verts.length + 2);
        pts.add(new double[]{fromLat, fromLng});
        for (int v : verts) pts.add(new double[]{graph.lat[v], graph.lon[v]});
        pts.add(new double[]{toLat, toLng});
        List<double[]> geometry = Geo.simplify(pts, SIMPLIFY_TOLERANCE_M);

        List<RouteStep> steps = InstructionBuilder.build(graph, verts, edges, mode, trafficFactor, destinationName);

        double approach = Geo.distanceM(fromLat, fromLng, graph.lat[bestFrom], graph.lon[bestFrom])
                + Geo.distanceM(toLat, toLng, graph.lat[bestTo], graph.lon[bestTo]);
        double distance = approach;
        double seconds = approach / APPROACH_SPEED_MPS;
        for (RouteStep st : steps) {
            distance += st.distanceMeters();
            seconds += st.durationSeconds();
        }
        return new RouteResult(mode, distance, seconds, geometry, steps, visited);
    }
}
