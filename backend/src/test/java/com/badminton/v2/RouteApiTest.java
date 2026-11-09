package com.badminton.v2;

import com.badminton.v2.entity.Venue;
import com.badminton.v2.routing.GraphBuilder;
import com.badminton.v2.routing.RoutingService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;
import org.springframework.beans.factory.annotation.Autowired;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * API tìm đường. Test chạy với app.routing.enabled=false (không tải OSM),
 * sau đó nạp một lưới đường giả quanh sân demo để kiểm tra kết quả.
 */
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class RouteApiTest extends IntegrationTestBase {

    @Autowired
    private RoutingService routingService;

    private static final double D = 0.0009; // ~100 m

    /** Lưới 15x15 ô (~1,4 km) có góc dưới-trái tại (lat0, lon0). */
    private static GraphBuilder grid(double lat0, double lon0) {
        int n = 15;
        GraphBuilder b = new GraphBuilder();
        for (int r = 0; r < n; r++) for (int c = 0; c < n; c++) b.addNode(r * 100L + c, lat0 + r * D, lon0 + c * D);
        long wid = 1;
        for (int r = 0; r < n; r++) {
            long[] refs = new long[n];
            for (int c = 0; c < n; c++) refs[c] = r * 100L + c;
            b.addWay(wid++, refs, Map.of("highway", "residential", "name", "Ngang " + r));
        }
        for (int c = 0; c < n; c++) {
            long[] refs = new long[n];
            for (int r = 0; r < n; r++) refs[r] = r * 100L + c;
            b.addWay(wid++, refs, Map.of("highway", "secondary", "name", "Dọc " + c));
        }
        return b;
    }

    @Test
    @Order(1)
    @DisplayName("Tính năng tắt / chưa có bản đồ: 503 kèm trạng thái, không làm hỏng app")
    void unavailable() throws Exception {
        Venue v = ownerApprovedVenue();
        var res = body(mvc.perform(getAs(tokenOf(CUSTOMER), "/api/routes")
                        .param("fromLat", "10.87").param("fromLng", "106.80").param("venueId", String.valueOf(v.getId())))
                .andExpect(status().isServiceUnavailable()).andReturn());
        assertEquals("DISABLED", res.path("state").asText());

        var st = body(mvc.perform(getAs(tokenOf(CUSTOMER), "/api/routes/status")).andExpect(status().isOk()).andReturn());
        assertFalse(st.path("ready").asBoolean(true));
    }

    @Test
    @Order(2)
    @DisplayName("Tham số sai -> 400; chưa đăng nhập -> 401; Admin mới được tải lại bản đồ")
    void validation() throws Exception {
        String token = tokenOf(CUSTOMER);
        Venue v = ownerApprovedVenue();
        mvc.perform(getAs(token, "/api/routes").param("fromLat", "abc").param("fromLng", "106.8")
                        .param("venueId", String.valueOf(v.getId())))
                .andExpect(status().isBadRequest());
        mvc.perform(getAs(token, "/api/routes").param("fromLat", "100").param("fromLng", "106.8")
                        .param("venueId", String.valueOf(v.getId())))
                .andExpect(status().isBadRequest());
        mvc.perform(getAs(null, "/api/routes").param("fromLat", "10.87").param("fromLng", "106.8")
                        .param("venueId", String.valueOf(v.getId())))
                .andExpect(status().isUnauthorized());
        mvc.perform(postAs(token, Map.of(), "/api/admin/routing/reimport")).andExpect(status().isForbidden());
        // Tính năng đang tắt trong test -> 409 (không tải OSM)
        mvc.perform(postAs(tokenOf(ADMIN), Map.of(), "/api/admin/routing/reimport")).andExpect(status().isConflict());
    }

    @Test
    @Order(3)
    @DisplayName("Có bản đồ: trả tuyến theo đường, chỉ dẫn, thời gian; ngoài vùng -> 422")
    void routeOnGraph() throws Exception {
        Venue v = ownerApprovedVenue();
        // Sân nằm ở giữa lưới, người dùng ở góc dưới-trái
        double lat0 = v.getLatitude() - 7 * D, lon0 = v.getLongitude() - 7 * D;
        routingService.useGraph(grid(lat0, lon0).build());
        String token = tokenOf(newUser("CUSTOMER", 0));

        var r = body(mvc.perform(getAs(token, "/api/routes")
                        .param("fromLat", String.valueOf(lat0)).param("fromLng", String.valueOf(lon0))
                        .param("venueId", String.valueOf(v.getId())).param("mode", "motorbike"))
                .andExpect(status().isOk()).andReturn());
        assertEquals("MOTORBIKE", r.path("mode").asText());
        assertTrue(r.path("distanceMeters").asDouble() > 1000, "đi theo lưới ~1,5 km");
        assertTrue(r.path("durationSeconds").asDouble() > 60);
        assertTrue(r.path("geometry").size() >= 2);
        var steps = r.path("steps");
        assertEquals("DEPART", steps.get(0).path("type").asText());
        assertEquals("ARRIVE", steps.get(steps.size() - 1).path("type").asText());
        assertTrue(steps.get(steps.size() - 1).path("instruction").asText().contains(v.getName()));

        var walk = body(mvc.perform(getAs(token, "/api/routes")
                        .param("fromLat", String.valueOf(lat0)).param("fromLng", String.valueOf(lon0))
                        .param("venueId", String.valueOf(v.getId())).param("mode", "walk"))
                .andExpect(status().isOk()).andReturn());
        assertTrue(walk.path("durationSeconds").asDouble() > r.path("durationSeconds").asDouble(), "đi bộ lâu hơn xe máy");

        mvc.perform(getAs(token, "/api/routes").param("fromLat", "10.30").param("fromLng", "106.30")
                        .param("venueId", String.valueOf(v.getId())))
                .andExpect(status().isUnprocessableEntity());

        var st = body(mvc.perform(getAs(token, "/api/routes/status")).andExpect(status().isOk()).andReturn());
        assertTrue(st.path("ready").asBoolean());
        assertEquals(225, st.path("vertices").asInt());
    }
}
