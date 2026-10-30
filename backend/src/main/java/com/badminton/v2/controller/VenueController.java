package com.badminton.v2.controller;

import com.badminton.v2.entity.*;
import com.badminton.v2.repository.*;
import com.badminton.v2.service.NotificationService;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

@RestController
@RequestMapping("/api/venues")
public class VenueController {

    private final VenueRepository venueRepository;
    private final CourtRepository courtRepository;
    private final PricingRuleRepository pricingRuleRepository;
    private final BookingRepository bookingRepository;
    private final MatchPostRepository matchPostRepository;
    private final UserRepository userRepository;
    private final NotificationService notificationService;
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    public VenueController(VenueRepository venueRepository,
                           CourtRepository courtRepository,
                           PricingRuleRepository pricingRuleRepository,
                           BookingRepository bookingRepository,
                           MatchPostRepository matchPostRepository,
                           UserRepository userRepository,
                           NotificationService notificationService) {
        this.venueRepository = venueRepository;
        this.courtRepository = courtRepository;
        this.pricingRuleRepository = pricingRuleRepository;
        this.bookingRepository = bookingRepository;
        this.matchPostRepository = matchPostRepository;
        this.userRepository = userRepository;
        this.notificationService = notificationService;
    }

    @GetMapping
    public List<Map<String, Object>> listApprovedVenues(
            @RequestParam(required = false) String keyword,
            @RequestParam(required = false, defaultValue = "10.8753") double lat,
            @RequestParam(required = false, defaultValue = "106.8000") double lng,
            @RequestParam(required = false) Double maxRadiusKm) {

        List<Venue> venues = venueRepository.findByStatusOrderByIdDesc("APPROVED");
        List<Map<String, Object>> result = new ArrayList<>();

        for (Venue v : venues) {
            if (keyword != null && !keyword.isBlank()) {
                String kw = keyword.trim().toLowerCase();
                if (!v.getName().toLowerCase().contains(kw) && !v.getAddress().toLowerCase().contains(kw)) {
                    continue;
                }
            }
            double distKm = Math.round(haversineKm(lat, lng, v.getLatitude(), v.getLongitude()) * 10.0) / 10.0;
            if (maxRadiusKm != null && distKm > maxRadiusKm) {
                continue;
            }
            Map<String, Object> item = toVenueMap(v, distKm);
            result.add(item);
        }
        result.sort(Comparator.comparingDouble(m -> (Double) m.get("distanceKm")));
        return result;
    }

    @GetMapping("/{id}")
    public ResponseEntity<?> getVenueDetail(
            @PathVariable Long id,
            @RequestParam(required = false) String playDate,
            @RequestParam(required = false, defaultValue = "10.8753") double lat,
            @RequestParam(required = false, defaultValue = "106.8000") double lng) {

        Optional<Venue> opt = venueRepository.findById(id);
        if (opt.isEmpty()) return ResponseEntity.notFound().build();
        Venue v = opt.get();

        String dateStr = (playDate == null || playDate.isBlank()) ? LocalDate.now().toString() : playDate;
        double distKm = Math.round(haversineKm(lat, lng, v.getLatitude(), v.getLongitude()) * 10.0) / 10.0;

        Map<String, Object> detail = toVenueMap(v, distKm);
        List<Court> courts = courtRepository.findByVenueIdOrderByIdAsc(id);
        List<PricingRule> pricingRules = pricingRuleRepository.findByVenueIdOrderByStartTimeAsc(id);
        List<Booking> bookingsOnDate = bookingRepository.findByVenueIdAndPlayDateOrderByStartTimeAsc(id, dateStr)
                .stream()
                .filter(b -> !List.of("CANCELLED", "EXPIRED").contains(b.getStatus()))
                .toList();
        List<MatchPost> openMatches = matchPostRepository.findByVenueIdOrderByIdDesc(id)
                .stream()
                .filter(m -> "OPEN".equals(m.getStatus()))
                .toList();

        detail.put("courts", courts);
        detail.put("pricingRules", pricingRules);
        detail.put("playDate", dateStr);
        detail.put("bookingsOnDate", bookingsOnDate);
        detail.put("openMatches", openMatches);
        return ResponseEntity.ok(detail);
    }

    @GetMapping("/owner/{ownerId}")
    public List<Venue> getOwnerVenues(@PathVariable Long ownerId) {
        return venueRepository.findByOwnerIdOrderByIdDesc(ownerId);
    }

    @PostMapping("/owner")
    @Transactional
    public ResponseEntity<?> createOwnerVenue(@RequestBody Map<String, Object> body) {
        Long ownerId = Long.parseLong(String.valueOf(body.getOrDefault("ownerId", 2)));
        String ownerName = userRepository.findById(ownerId).map(User::getFullName).orElse("Chủ sân");
        String name = String.valueOf(body.getOrDefault("name", "Sân Cầu Lông Mới"));
        String address = String.valueOf(body.getOrDefault("address", "TP. Hồ Chí Minh"));
        double latitude = Double.parseDouble(String.valueOf(body.getOrDefault("latitude", 10.7850)));
        double longitude = Double.parseDouble(String.valueOf(body.getOrDefault("longitude", 106.6620)));
        String description = String.valueOf(body.getOrDefault("description", "Thảm tiêu chuẩn thi đấu BWF, trần cao 10m, đèn chống chói."));
        int totalCourts = Integer.parseInt(String.valueOf(body.getOrDefault("totalCourts", 4)));
        double basePrice = Double.parseDouble(String.valueOf(body.getOrDefault("basePricePerHour", 80000)));
        double peakPrice = Double.parseDouble(String.valueOf(body.getOrDefault("peakPricePerHour", 120000)));

        Venue venue = new Venue(
                ownerId,
                ownerName,
                name,
                address,
                latitude,
                longitude,
                description,
                "https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?w=800",
                "05:00",
                "23:00",
                "PENDING",
                0.05,
                5.0,
                totalCourts,
                basePrice,
                peakPrice,
                LocalDateTime.now().format(FMT)
        );
        venue = venueRepository.save(venue);

        for (int i = 1; i <= totalCourts; i++) {
            courtRepository.save(new Court(venue.getId(), "Sân " + i, i == 1 ? "VIP" : "STANDARD", true));
        }
        pricingRuleRepository.save(new PricingRule(venue.getId(), "ALL", "05:00", "17:00", basePrice));
        pricingRuleRepository.save(new PricingRule(venue.getId(), "ALL", "17:00", "23:00", peakPrice));

        notificationService.notifyUser(
                ownerId,
                "Đã gửi hồ sơ đăng ký cơ sở mới",
                "Cơ sở '" + name + "' đang ở trạng thái PENDING chờ Admin phê duyệt trên hệ thống.",
                "SYSTEM",
                "S19",
                venue.getId()
        );
        return ResponseEntity.ok(venue);
    }

    private Map<String, Object> toVenueMap(Venue v, double distKm) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", v.getId());
        m.put("ownerId", v.getOwnerId());
        m.put("ownerName", v.getOwnerName());
        m.put("name", v.getName());
        m.put("address", v.getAddress());
        m.put("latitude", v.getLatitude());
        m.put("longitude", v.getLongitude());
        m.put("distanceKm", distKm);
        m.put("description", v.getDescription());
        m.put("imageUrl", v.getImageUrl());
        m.put("openTime", v.getOpenTime());
        m.put("closeTime", v.getCloseTime());
        m.put("status", v.getStatus());
        m.put("commissionRate", v.getCommissionRate());
        m.put("rating", v.getRating());
        m.put("totalCourts", v.getTotalCourts());
        m.put("basePricePerHour", v.getBasePricePerHour());
        m.put("peakPricePerHour", v.getPeakPricePerHour());
        return m;
    }

    private double haversineKm(double lat1, double lon1, double lat2, double lon2) {
        final int R = 6371;
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    }
}
