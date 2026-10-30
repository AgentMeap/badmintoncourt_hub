package com.badminton.v2.controller;

import com.badminton.v2.entity.*;
import com.badminton.v2.repository.*;
import com.badminton.v2.service.EmailOtpService;
import com.badminton.v2.service.NotificationService;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

@RestController
@RequestMapping("/api")
public class AdminOwnerFinanceController {

    private final VenueRepository venueRepository;
    private final BookingRepository bookingRepository;
    private final PaymentRepository paymentRepository;
    private final PayoutRequestRepository payoutRequestRepository;
    private final UserRepository userRepository;
    private final EmailOtpService emailOtpService;
    private final NotificationService notificationService;
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    public AdminOwnerFinanceController(VenueRepository venueRepository,
                                       BookingRepository bookingRepository,
                                       PaymentRepository paymentRepository,
                                       PayoutRequestRepository payoutRequestRepository,
                                       UserRepository userRepository,
                                       EmailOtpService emailOtpService,
                                       NotificationService notificationService) {
        this.venueRepository = venueRepository;
        this.bookingRepository = bookingRepository;
        this.paymentRepository = paymentRepository;
        this.payoutRequestRepository = payoutRequestRepository;
        this.userRepository = userRepository;
        this.emailOtpService = emailOtpService;
        this.notificationService = notificationService;
    }

    // S19 & S23: Owner Dashboard & Payout Summary
    @GetMapping("/owner/{ownerId}/dashboard")
    public ResponseEntity<?> getOwnerDashboard(@PathVariable Long ownerId) {
        List<Venue> venues = venueRepository.findByOwnerIdOrderByIdDesc(ownerId);
        List<Long> venueIds = venues.stream().map(Venue::getId).toList();

        double totalGrossRevenue = 0;
        int totalBookingsCount = 0;
        int walkInCount = 0;
        List<Booking> recentBookings = new ArrayList<>();

        for (Long vid : venueIds) {
            List<Booking> bks = bookingRepository.findByVenueIdOrderByIdDesc(vid);
            for (Booking b : bks) {
                if (List.of("CONFIRMED", "CHECKED_IN", "COMPLETED").contains(b.getStatus())) {
                    totalGrossRevenue += b.getTotalPrice();
                    totalBookingsCount++;
                    if ("WALK_IN".equals(b.getBookingType())) walkInCount++;
                }
                if (recentBookings.size() < 15) {
                    recentBookings.add(b);
                }
            }
        }

        double commissionFee = Math.round(totalGrossRevenue * 0.05);
        double netRevenue = totalGrossRevenue - commissionFee;
        List<PayoutRequest> payouts = payoutRequestRepository.findByOwnerIdOrderByIdDesc(ownerId);
        double alreadyRequestedNet = payouts.stream()
                .filter(p -> !"REJECTED".equals(p.getStatus()))
                .mapToDouble(PayoutRequest::getNetPayoutAmount)
                .sum();
        double availableNetPayout = Math.max(0, netRevenue - alreadyRequestedNet);

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("venues", venues);
        res.put("totalGrossRevenue", totalGrossRevenue);
        res.put("commissionFee", commissionFee);
        res.put("netRevenue", netRevenue);
        res.put("availableNetPayout", availableNetPayout);
        res.put("totalBookingsCount", totalBookingsCount);
        res.put("walkInCount", walkInCount);
        res.put("recentBookings", recentBookings);
        res.put("payoutRequests", payouts);
        return ResponseEntity.ok(res);
    }

    // S23: Chủ sân gửi yêu cầu đối soát / giải ngân (Payout Request) kèm xác thực OTP Email
    @PostMapping("/owner/payout-requests")
    @Transactional
    public ResponseEntity<?> createPayoutRequest(@RequestBody Map<String, Object> body) {
        Long ownerId = Long.parseLong(String.valueOf(body.getOrDefault("ownerId", 2)));
        Long venueId = Long.parseLong(String.valueOf(body.getOrDefault("venueId", 1)));
        double grossAmount = Double.parseDouble(String.valueOf(body.getOrDefault("grossAmount", 2000000)));
        String bankName = String.valueOf(body.getOrDefault("bankName", "Vietcombank"));
        String bankAccountNumber = String.valueOf(body.getOrDefault("bankAccountNumber", "0071001234567"));
        String bankAccountHolder = String.valueOf(body.getOrDefault("bankAccountHolder", "NGUYEN CHU SAN"));
        String otpCode = String.valueOf(body.getOrDefault("otpCode", "123456")).trim();

        User owner = userRepository.findById(ownerId).orElseThrow();
        if (!emailOtpService.verifyOtp(owner.getEmail(), otpCode)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Mã bảo mật OTP không chính xác! Vui lòng kiểm tra Email hoặc nhập mã Demo 123456."));
        }

        Venue venue = venueRepository.findById(venueId).orElseThrow();
        double commissionFee = Math.round(grossAmount * 0.05);
        double netAmount = grossAmount - commissionFee;

        PayoutRequest pr = new PayoutRequest();
        pr.setPayoutCode("PO-" + (System.currentTimeMillis() % 1000000));
        pr.setVenueId(venueId);
        pr.setVenueName(venue.getName());
        pr.setOwnerId(ownerId);
        pr.setOwnerName(owner.getFullName());
        pr.setGrossAmount(grossAmount);
        pr.setCommissionFee(commissionFee);
        pr.setNetPayoutAmount(netAmount);
        pr.setBankName(bankName);
        pr.setBankAccountNumber(bankAccountNumber);
        pr.setBankAccountHolder(bankAccountHolder);
        pr.setStatus("PENDING");
        pr.setCreatedAt(LocalDateTime.now().format(FMT));
        pr = payoutRequestRepository.save(pr);

        notificationService.notifyUser(
                ownerId,
                "Đã tạo yêu cầu giải ngân #" + pr.getPayoutCode(),
                "Số tiền thực nhận: " + (long) netAmount + "đ (đã khấu trừ 5% phí sàn) đang chờ Admin đối soát chuyển khoản.",
                "PAYMENT",
                "S23",
                pr.getId()
        );
        return ResponseEntity.ok(pr);
    }

    // S24: Admin Platform Overview
    @GetMapping("/admin/dashboard")
    public ResponseEntity<?> getAdminDashboard() {
        List<Venue> allVenues = venueRepository.findAll();
        List<User> allUsers = userRepository.findAll();
        List<PayoutRequest> allPayouts = payoutRequestRepository.findAllByOrderByIdDesc();
        List<Payment> paidPayments = paymentRepository.findByStatusOrderByIdDesc("PAID");

        double totalGmv = paidPayments.stream().mapToDouble(Payment::getAmount).sum();
        double platformCommission = Math.round(totalGmv * 0.05);
        long pendingVenuesCount = allVenues.stream().filter(v -> "PENDING".equals(v.getStatus())).count();
        long pendingPayoutsCount = allPayouts.stream().filter(p -> "PENDING".equals(p.getStatus())).count();

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("totalGmv", totalGmv);
        res.put("platformCommission", platformCommission);
        res.put("totalUsers", allUsers.size());
        res.put("totalVenues", allVenues.size());
        res.put("pendingVenuesCount", pendingVenuesCount);
        res.put("pendingPayoutsCount", pendingPayoutsCount);
        res.put("venues", allVenues);
        res.put("users", allUsers);
        res.put("payoutRequests", allPayouts);
        res.put("recentPayments", paidPayments);
        return ResponseEntity.ok(res);
    }

    // S25: Admin Moderation - Duyệt / Từ chối cơ sở cầu lông
    @PatchMapping("/admin/venues/{venueId}/status")
    @Transactional
    public ResponseEntity<?> moderateVenue(@PathVariable Long venueId, @RequestBody Map<String, String> body) {
        String status = body.getOrDefault("status", "APPROVED").toUpperCase();
        Venue venue = venueRepository.findById(venueId).orElseThrow();
        venue.setStatus(status);
        venueRepository.save(venue);

        notificationService.notifyUser(
                venue.getOwnerId(),
                "APPROVED".equals(status)
                        ? "Cơ sở '" + venue.getName() + "' đã được Admin phê duyệt!"
                        : "Hồ sơ cơ sở '" + venue.getName() + "' bị từ chối",
                "APPROVED".equals(status)
                        ? "Sân của bạn đã chính thức hiển thị trên Bản đồ OpenStreetMap và sẵn sàng nhận khách đặt online."
                        : "Vui lòng kiểm tra lại thông tin địa chỉ và bảng giá.",
                "SYSTEM",
                "S19",
                venue.getId()
        );
        return ResponseEntity.ok(venue);
    }

    // S25: Admin Moderation - Khóa / Mở khóa tài khoản người dùng
    @PatchMapping("/admin/users/{userId}/toggle-active")
    @Transactional
    public ResponseEntity<?> toggleUserActive(@PathVariable Long userId) {
        User u = userRepository.findById(userId).orElseThrow();
        u.setActive(!u.isActive());
        return ResponseEntity.ok(userRepository.save(u));
    }

    // S26: Admin Duyệt giải ngân Payout cho Chủ sân
    @PatchMapping("/admin/payout-requests/{id}/status")
    @Transactional
    public ResponseEntity<?> updatePayoutStatus(@PathVariable Long id, @RequestBody Map<String, String> body) {
        String status = body.getOrDefault("status", "PAID").toUpperCase();
        PayoutRequest pr = payoutRequestRepository.findById(id).orElseThrow();
        pr.setStatus(status);
        if ("PAID".equals(status)) {
            pr.setPaidAt(LocalDateTime.now().format(FMT));
        }
        payoutRequestRepository.save(pr);

        notificationService.notifyUser(
                pr.getOwnerId(),
                "PAID".equals(status)
                        ? "Admin đã giải ngân đối soát #" + pr.getPayoutCode()
                        : "Cập nhật lệnh đối soát #" + pr.getPayoutCode(),
                "PAID".equals(status)
                        ? "Số tiền " + (long) pr.getNetPayoutAmount() + "đ đã được chuyển vào tài khoản " + pr.getBankName() + " (" + pr.getBankAccountNumber() + ")."
                        : "Trạng thái lệnh rút tiền: " + status,
                "PAYMENT",
                "S23",
                pr.getId()
        );
        return ResponseEntity.ok(pr);
    }
}
