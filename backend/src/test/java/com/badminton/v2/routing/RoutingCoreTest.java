package com.badminton.v2.routing;

import com.fasterxml.jackson.core.JsonFactory;
import com.fasterxml.jackson.core.JsonParser;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

/** Lõi tìm đường (không cần Spring): dựng đồ thị, A*, một chiều, phương tiện, chỉ dẫn, lưu file, đọc Overpass. */
class RoutingCoreTest {

    static final double LAT0 = 10.80, LON0 = 106.70, D = 0.0009; // ~100 m

    static long id(int r, int c, int n) {
        return 1_000_000L + (long) r * n + c;
    }

    /** Lưới n x n: hàng ngang "Đường Ngang r", cột dọc "Đường Dọc c"; hàng 1 một chiều Tây -> Đông. */
    static GraphBuilder grid(int n) {
        GraphBuilder b = new GraphBuilder();
        for (int r = 0; r < n; r++) for (int c = 0; c < n; c++) b.addNode(id(r, c, n), LAT0 + r * D, LON0 + c * D);
        long wid = 1;
        for (int r = 0; r < n; r++) {
            long[] refs = new long[n];
            for (int c = 0; c < n; c++) refs[c] = id(r, c, n);
            Map<String, String> t = new HashMap<>();
            t.put("highway", r % 5 == 0 ? "secondary" : "residential");
            t.put("name", "Đường Ngang " + r);
            if (r == 1) t.put("oneway", "yes");
            b.addWay(wid++, refs, t);
        }
        for (int c = 0; c < n; c++) {
            long[] refs = new long[n];
            for (int r = 0; r < n; r++) refs[r] = id(r, c, n);
            Map<String, String> t = new HashMap<>();
            t.put("highway", c % 5 == 0 ? "primary" : "residential");
            t.put("name", "Đường Dọc " + c);
            b.addWay(wid++, refs, t);
        }
        return b;
    }

    static RoadGraph cityWithExtras() {
        GraphBuilder b = grid(10);
        b.addNode(id(0, 0, 10), LAT0, LON0); // nút trùng (ô tải chồng nhau)
        b.addWay(9003, new long[]{id(0, 0, 10), id(9, 9, 10)}, Map.of("highway", "motorway", "name", "Cao tốc"));
        b.addWay(9004, new long[]{id(2, 2, 10), id(3, 3, 10)}, Map.of("highway", "footway"));
        return b.build();
    }

    double block() {
        return Geo.distanceM(LAT0, LON0, LAT0 + D, LON0);
    }

    @Test
    @DisplayName("Bỏ đường không đi được / tư nhân / trùng; bỏ trùng nút")
    void builderFilters() {
        GraphBuilder b = grid(3);
        assertFalse(b.addWay(1, new long[]{id(0, 0, 3), id(1, 1, 3)}, Map.of("highway", "residential")), "trùng id đường");
        assertFalse(b.addWay(500, new long[]{id(0, 0, 3), id(2, 2, 3)}, Map.of("highway", "construction")));
        assertFalse(b.addWay(501, new long[]{id(0, 0, 3), id(2, 2, 3)}, Map.of("highway", "residential", "access", "private")));
        b.addNode(id(0, 0, 3), LAT0, LON0);
        b.addNode(99, 0, 0); // nút không thuộc đường nào
        assertEquals(9, b.build().vertexCount());
    }

    @Test
    @DisplayName("Xe máy không vào cao tốc, ô tô được; đi bộ dùng lối đi bộ")
    void modesUseAllowedRoads() {
        RoutePlanner p = new RoutePlanner(cityWithExtras(), 1);
        RouteResult moto = p.route(LAT0, LON0, LAT0 + 9 * D, LON0 + 9 * D, TravelMode.MOTORBIKE, "Sân");
        assertEquals(18 * block(), moto.distanceMeters(), 60);
        RouteResult car = p.route(LAT0, LON0, LAT0 + 9 * D, LON0 + 9 * D, TravelMode.CAR, "Sân");
        assertTrue(car.distanceMeters() < 18 * block() * 0.8, "ô tô đi cao tốc chéo");
        assertTrue(car.steps().get(0).instruction().contains("Cao tốc"));
    }

    @Test
    @DisplayName("Đường một chiều: xe phải đi vòng, đi bộ được đi ngược")
    void onewayRespected() {
        RoutePlanner p = new RoutePlanner(cityWithExtras(), 1);
        RouteResult moto = p.route(LAT0 + D, LON0 + 9 * D, LAT0 + D, LON0, TravelMode.MOTORBIKE, null);
        RouteResult walk = p.route(LAT0 + D, LON0 + 9 * D, LAT0 + D, LON0, TravelMode.WALK, null);
        assertTrue(moto.distanceMeters() > 9 * block() + 100);
        assertTrue(walk.distanceMeters() < moto.distanceMeters());
    }

    @Test
    @DisplayName("Chỉ dẫn tiếng Việt cho tuyến hình chữ L")
    void instructions() {
        RoutePlanner p = new RoutePlanner(cityWithExtras(), 1);
        RouteResult r = p.route(LAT0, LON0 + 2 * D, LAT0 + 5 * D, LON0 + 7 * D, TravelMode.MOTORBIKE, "Sân B");
        assertEquals("DEPART", r.steps().get(0).type());
        assertEquals("Đi về hướng Đông trên Đường Ngang 0", r.steps().get(0).instruction());
        assertEquals("TURN_LEFT", r.steps().get(1).type());
        assertEquals("Rẽ trái vào Đường Dọc 5", r.steps().get(1).instruction());
        assertEquals("TURN_RIGHT", r.steps().get(2).type());
        assertEquals("Đến nơi: Sân B", r.steps().get(r.steps().size() - 1).instruction());
        assertTrue(r.geometry().size() <= 6, "hình dạng tuyến đã rút gọn");
        assertTrue(r.durationSeconds() > 0);
    }

    @Test
    @DisplayName("Ngoài vùng bản đồ -> OutOfCoverage")
    void outOfCoverage() {
        RoutePlanner p = new RoutePlanner(cityWithExtras(), 1);
        assertThrows(RoutePlanner.OutOfCoverageException.class,
                () -> p.route(LAT0 + 1, LON0, LAT0, LON0, TravelMode.MOTORBIKE, null));
    }

    @Test
    @DisplayName("Lưu / đọc file đồ thị cho cùng kết quả")
    void saveAndLoad(@TempDir Path dir) throws Exception {
        RoadGraph g = cityWithExtras();
        Path f = dir.resolve("g.graph");
        g.save(f);
        RoadGraph g2 = RoadGraph.load(f);
        assertEquals(g.vertexCount(), g2.vertexCount());
        assertEquals(g.edgeCount(), g2.edgeCount());
        RouteResult a = new RoutePlanner(g, 1).route(LAT0, LON0 + 2 * D, LAT0 + 5 * D, LON0 + 7 * D, TravelMode.MOTORBIKE, "S");
        RouteResult b = new RoutePlanner(g2, 1).route(LAT0, LON0 + 2 * D, LAT0 + 5 * D, LON0 + 7 * D, TravelMode.MOTORBIKE, "S");
        assertEquals(a.distanceMeters(), b.distanceMeters(), 0.01);
        assertEquals(a.steps(), b.steps());
    }

    @Test
    @DisplayName("Đọc dữ liệu Overpass: bỏ trùng giữa các ô, hẻm một chiều")
    void parseOverpass() throws Exception {
        String json = """
                {"elements":[
                 {"type":"way","id":10,"nodes":[1,2,3],"tags":{"highway":"primary","name":"Võ Văn Ngân"}},
                 {"type":"way","id":11,"nodes":[3,4],"tags":{"highway":"residential","name":"Hẻm 12","oneway":"yes"}},
                 {"type":"way","id":11,"nodes":[3,4],"tags":{"highway":"residential","name":"Hẻm 12","oneway":"yes"}},
                 {"type":"way","id":12,"nodes":[4,5],"tags":{"highway":"construction"}},
                 {"type":"node","id":1,"lat":10.85,"lon":106.76},
                 {"type":"node","id":2,"lat":10.8505,"lon":106.761},
                 {"type":"node","id":3,"lat":10.851,"lon":106.762},
                 {"type":"node","id":4,"lat":10.852,"lon":106.762}
                ],"remark":"ok"}""";
        GraphBuilder b = new GraphBuilder();
        try (JsonParser parser = new JsonFactory().createParser(json)) {
            OverpassImporter.parseStream(parser, b);
        }
        assertEquals(2, b.wayCount());
        RoadGraph g = b.build();
        assertEquals(4, g.vertexCount());
        assertEquals(6, g.edgeCount()); // 2 đoạn x 2 chiều + hẻm (xuôi + ngược chỉ đi bộ)
        RoutePlanner p = new RoutePlanner(g, 1);
        assertEquals("Rẽ trái vào Hẻm 12",
                p.route(10.85, 106.76, 10.852, 106.762, TravelMode.MOTORBIKE, null).steps().get(1).instruction());
        assertThrows(RoutePlanner.NoRouteException.class,
                () -> p.route(10.852, 106.762, 10.85, 106.76, TravelMode.MOTORBIKE, null));
    }

    @Test
    @DisplayName("Góc rẽ, hướng la bàn, rút gọn đường")
    void geometry() {
        assertEquals(90, Geo.turnAngle(0, 90), 1e-9);
        assertEquals(-90, Geo.turnAngle(0, 270), 1e-9);
        assertEquals("CONTINUE", InstructionBuilder.maneuver(10));
        assertEquals("SLIGHT_RIGHT", InstructionBuilder.maneuver(40));
        assertEquals("TURN_LEFT", InstructionBuilder.maneuver(-90));
        assertEquals("UTURN", InstructionBuilder.maneuver(175));
        assertEquals("Bắc", Geo.compass(5));
        assertEquals("Đông Nam", Geo.compass(135));
        var line = new java.util.ArrayList<double[]>();
        for (int i = 0; i <= 10; i++) line.add(new double[]{LAT0, LON0 + i * 0.0001});
        assertEquals(2, Geo.simplify(line, 1).size());
    }
}
