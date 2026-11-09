package com.badminton.v2.controller;

import com.badminton.v2.entity.Venue;
import com.badminton.v2.repository.VenueRepository;
import com.badminton.v2.routing.RoutePlanner;
import com.badminton.v2.routing.RouteResult;
import com.badminton.v2.routing.RouteStep;
import com.badminton.v2.routing.RoutingService;
import com.badminton.v2.routing.TravelMode;
import com.badminton.v2.security.AuthUser;
import com.badminton.v2.security.CurrentUser;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Tìm đường theo đường phố (thuật toán A* trên bản đồ OpenStreetMap TP.HCM, tự dựng ở backend).
 * <ul>
 *   <li>GET  /api/routes?fromLat&fromLng&venueId&mode=motorbike|car|walk</li>
 *   <li>GET  /api/routes/status                      trạng thái bản đồ đường (đang tải / sẵn sàng)</li>
 *   <li>POST /api/admin/routing/reimport             Admin tải lại dữ liệu OSM</li>
 * </ul>
 */
@RestController
@RequestMapping("/api")
public class RouteController {

    private final RoutingService routingService;
    private final VenueRepository venueRepository;

    public RouteController(RoutingService routingService, VenueRepository venueRepository) {
        this.routingService = routingService;
        this.venueRepository = venueRepository;
    }

    @GetMapping("/routes")
    public ResponseEntity<?> route(@RequestParam double fromLat,
                                   @RequestParam double fromLng,
                                   @RequestParam Long venueId,
                                   @RequestParam(required = false) String mode) {
        if (Math.abs(fromLat) > 90 || Math.abs(fromLng) > 180) {
            return ResponseEntity.badRequest().body(Map.of("error", "Toạ độ không hợp lệ."));
        }
        // Điểm đến luôn lấy từ máy chủ theo id sân (không nhận toạ độ tuỳ ý)
        Venue venue = venueRepository.findById(venueId).orElseThrow();
        TravelMode travelMode = TravelMode.parse(mode);
        Long userId = CurrentUser.get().map(AuthUser::id).orElse(null);

        long t0 = System.currentTimeMillis();
        try {
            RouteResult r = routingService.route(userId, fromLat, fromLng,
                    venue.getLatitude(), venue.getLongitude(), travelMode, venue.getName(), "venue:" + venue.getId());
            Map<String, Object> res = toJson(r);
            res.put("venueId", venue.getId());
            res.put("computeMs", System.currentTimeMillis() - t0);
            return ResponseEntity.ok(res);
        } catch (RoutingService.RoutingUnavailableException e) {
            Map<String, Object> body = new LinkedHashMap<>(routingService.status());
            body.put("error", "Bản đồ đường chưa sẵn sàng: " + e.getMessage());
            return ResponseEntity.status(503).body(body);
        } catch (RoutePlanner.OutOfCoverageException e) {
            return ResponseEntity.status(422).body(Map.of("error", e.getMessage()));
        } catch (RoutePlanner.NoRouteException e) {
            return ResponseEntity.status(404).body(Map.of("error", e.getMessage()));
        } catch (RoutingService.RateLimitedException e) {
            return ResponseEntity.status(429).header("Retry-After", "30").body(Map.of("error", e.getMessage()));
        }
    }

    @GetMapping("/routes/status")
    public Map<String, Object> status() {
        return routingService.status();
    }

    @PostMapping("/admin/routing/reimport")
    public ResponseEntity<?> reimport() {
        if (!routingService.reimport()) {
            return ResponseEntity.status(409).body(Map.of("error", "Đang chuẩn bị bản đồ đường hoặc tính năng đang tắt."));
        }
        return ResponseEntity.accepted().body(routingService.status());
    }

    static Map<String, Object> toJson(RouteResult r) {
        List<double[]> geometry = new ArrayList<>(r.geometry().size());
        for (double[] p : r.geometry()) geometry.add(new double[]{round6(p[0]), round6(p[1])});
        List<Map<String, Object>> steps = new ArrayList<>();
        for (RouteStep s : r.steps()) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("type", s.type());
            m.put("instruction", s.instruction());
            m.put("streetName", s.streetName());
            m.put("distanceMeters", Math.round(s.distanceMeters()));
            m.put("durationSeconds", Math.round(s.durationSeconds()));
            m.put("lat", round6(s.lat()));
            m.put("lng", round6(s.lng()));
            steps.add(m);
        }
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("mode", r.mode().name());
        res.put("distanceMeters", Math.round(r.distanceMeters()));
        res.put("durationSeconds", Math.round(r.durationSeconds()));
        res.put("geometry", geometry);
        res.put("steps", steps);
        res.put("approximate", true);
        res.put("provider", "OSM_ASTAR");
        return res;
    }

    private static double round6(double v) {
        return Math.round(v * 1e6) / 1e6;
    }
}
