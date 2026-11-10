package com.badminton.v2.controller;

import com.badminton.v2.entity.*;
import com.badminton.v2.repository.*;
import com.badminton.v2.security.AuthUser;
import com.badminton.v2.security.CurrentUser;
import com.badminton.v2.service.BookingRules;
import com.badminton.v2.service.EmailOtpService;
import com.badminton.v2.service.NotificationService;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.*;

/**
 * Chủ sân (S19-S23) và Quản trị viên (S24-S26).
 *
 * <ul>
 *   <li>GET   /api/owner/{ownerId}/dashboard               tổng quan chủ sân (hôm nay, 7 ngày, từng cơ sở, giải ngân)</li>
 *   <li>GET   /api/owner/venues/{venueId}/bookings?date=   lịch đầy đủ một cơ sở trong ngày (S21)</li>
 *   <li>POST  /api/owner/payout-requests                   yêu cầu giải ngân kèm OTP (S23)</li>
 *   <li>GET   /api/admin/dashboard                         tổng quan nền tảng (S24)</li>
 *   <li>PATCH /api/admin/venues/{venueId}/status           duyệt / từ chối / tạm ngưng cơ sở (S25)</li>
 *   <li>PATCH /api/admin/users/{userId}/toggle-active      khóa / mở khóa tài khoản (S25)</li>
 *   <li>PATCH /api/admin/payout-requests/{id}/status       xác nhận chuyển khoản / từ chối giải ngân (S26)</li>
 * </ul>
 */
@RestController
@RequestMapping("/api")
public class AdminOwnerFinanceController {

    private static final double COMMISSION_RATE = 0.05;
    private static final int CHART_DAYS = 7;
    private static final Set<String> REVENUE_STATUSES = Set.of("CONFIRMED", "CHECKED_IN", "COMPLETED");
    private static final Set<String> ONLINE_METHODS = Set.of("PAYOS_QR", "WALLET");
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    /** Chuyển trạng thái cơ sở hợp lệ: chờ duyệt -> duyệt/từ chối, đang hoạt động <-> tạm ngưng. */
    private static final Map<String, Set<String>> VENUE_TRANSITIONS = Map.of(
            "PENDING", Set.of("APPROVED", "REJECTED"),
            "APPROVED", Set.of("SUSPENDED"),
            "SUSPENDED", Set.of("APPROVED"),
            "REJECTED", Set.of("APPROVED")
    );

    private final VenueRepository venueRepository;
    private final CourtRepository courtRepository;
    private final BookingRepository bookingRepository;
    private final PaymentRepository paymentRepository;
    private final PayoutRequestRepository payoutRequestRepository;
    private final UserRepository userRepository;
    private final EmailOtpService emailOtpService;
    private final NotificationService notificationService;
    private final MatchParticipantRepository matchParticipantRepository;

    public AdminOwnerFinanceController(VenueRepository venueRepository,
                                       CourtRepository courtRepository,
                                       BookingRepository bookingRepository,
                                       PaymentRepository paymentRepository,
                                       PayoutRequestRepository payoutRequestRepository,
                                       UserRepository userRepository,
                                       EmailOtpService emailOtpService,
                                       NotificationService notificationService,
                                       MatchParticipantRepository matchParticipantRepository) {
        this.venueRepository = venueRepository;
        this.courtRepository = courtRepository;
        this.bookingRepository = bookingRepository;
        this.paymentRepository = paymentRepository;
        this.payoutRequestRepository = payoutRequestRepository;
        this.userRepository = userRepository;
        this.emailOtpService = emailOtpService;
        this.notificationService = notificationService;
        this.matchParticipantRepository = matchParticipantRepository;
    }

    // ===================================================================== Chủ sân

    // S19 & S23: tổng quan chủ sân
    @GetMapping("/owner/{ownerId}/dashboard")
    public ResponseEntity<?> getOwnerDashboard(@PathVariable Long ownerId) {
        CurrentUser.requireSelfOrAdmin(ownerId);
        List<Venue> venues = venueRepository.findByOwnerIdOrderByIdDesc(ownerId);
        String today = LocalDate.now().toString();

        double totalGross = 0;
        double onlineGross = 0;
        int totalBookings = 0;
        int walkInCount = 0;
        List<Booking> recentBookings = new ArrayList<>();
        List<Booking> todaySessions = new ArrayList<>();
        Map<String, double[]> byDay = emptyDays(); // ngày -> [doanh thu, số ca]
        List<Map<String, Object>> venueStats = new ArrayList<>();
        int bookedHoursToday = 0;
        int capacityHoursToday = 0;

        for (Venue v : venues) {
            List<Booking> bookings = bookingRepository.findByVenueIdOrderByIdDesc(v.getId());
            double venueToday = 0;
            int venueSessionsToday = 0;
            for (Booking b : bookings) {
                if (recentBookings.size() < 15) recentBookings.add(b);
                if (today.equals(b.getPlayDate()) && BookingRules.blocksCourt(b)
                        && !"MAINTENANCE".equals(b.getBookingType())) {
                    bookedHoursToday += hoursOf(b);
                }
                double retained = retainedOf(b);
                if (retained > 0) {
                    // Vé hủy muộn: phần khách không được hoàn vẫn tính cho chủ sân (không tính là 1 ca chơi)
                    totalGross += retained;
                    if (isOnline(b)) onlineGross += retained;
                    double[] retainedDay = byDay.get(b.getPlayDate());
                    if (retainedDay != null) retainedDay[0] += retained;
                    continue;
                }
                if (!isRevenue(b)) continue;
                totalGross += b.getTotalPrice();
                totalBookings++;
                if ("WALK_IN".equals(b.getBookingType())) walkInCount++;
                if (isOnline(b)) onlineGross += b.getTotalPrice();
                double[] day = byDay.get(b.getPlayDate());
                if (day != null) {
                    day[0] += b.getTotalPrice();
                    day[1]++;
                }
                if (today.equals(b.getPlayDate())) {
                    todaySessions.add(b);
                    venueToday += b.getTotalPrice();
                    venueSessionsToday++;
                }
            }
            if ("APPROVED".equals(v.getStatus())) {
                capacityHoursToday += activeCourts(v) * openHours(v);
            }
            Map<String, Object> stat = new LinkedHashMap<>();
            stat.put("venueId", v.getId());
            stat.put("name", v.getName());
            stat.put("status", v.getStatus());
            stat.put("totalCourts", v.getTotalCourts());
            stat.put("revenueToday", venueToday);
            stat.put("sessionsToday", venueSessionsToday);
            venueStats.add(stat);
        }
        todaySessions.sort(Comparator.comparing(Booking::getStartTime).thenComparing(Booking::getCourtName));

        List<PayoutRequest> payouts = payoutRequestRepository.findByOwnerIdOrderByIdDesc(ownerId);
        double requestedGross = payouts.stream()
                .filter(p -> !"REJECTED".equals(p.getStatus()))
                .mapToDouble(PayoutRequest::getGrossAmount)
                .sum();
        double pendingPayoutNet = payouts.stream()
                .filter(p -> "PENDING".equals(p.getStatus()))
                .mapToDouble(PayoutRequest::getNetPayoutAmount)
                .sum();
        double availableGross = Math.max(0, onlineGross - requestedGross);
        // Phí sàn chỉ tính trên tiền đi qua nền tảng (PayOS / Ví), tiền mặt tại quầy không mất phí
        double commissionFee = commissionOf(onlineGross);

        Map<String, Object> todayStats = new LinkedHashMap<>();
        todayStats.put("date", today);
        todayStats.put("revenue", todaySessions.stream().mapToDouble(Booking::getTotalPrice).sum());
        todayStats.put("sessions", todaySessions.size());
        todayStats.put("waitingCheckIn", todaySessions.stream().filter(b -> "CONFIRMED".equals(b.getStatus())).count());
        todayStats.put("occupancyPercent", capacityHoursToday == 0 ? 0
                : Math.min(100, Math.round(bookedHoursToday * 100.0 / capacityHoursToday)));

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("venues", venues);
        res.put("venueStats", venueStats);
        res.put("today", todayStats);
        res.put("todaySessions", todaySessions);
        res.put("last7Days", dayRows(byDay));
        res.put("totalGrossRevenue", totalGross);
        res.put("commissionFee", commissionFee);
        res.put("netRevenue", totalGross - commissionFee);
        res.put("onlineGrossRevenue", onlineGross);
        res.put("availablePayoutGross", availableGross);
        res.put("availableNetPayout", availableGross - commissionOf(availableGross));
        res.put("pendingPayoutNet", pendingPayoutNet);
        res.put("commissionRate", COMMISSION_RATE);
        res.put("totalBookingsCount", totalBookings);
        res.put("walkInCount", walkInCount);
        res.put("recentBookings", recentBookings);
        res.put("payoutRequests", payouts);
        return ResponseEntity.ok(res);
    }

    // S21: lịch đầy đủ một cơ sở trong ngày (kèm tên / SĐT khách, chỉ chủ sân & Admin xem được)
    @GetMapping("/owner/venues/{venueId}/bookings")
    public ResponseEntity<?> getVenueBookingsOfDay(@PathVariable Long venueId,
                                                   @RequestParam(required = false) String date) {
        Venue venue = venueRepository.findById(venueId).orElseThrow();
        CurrentUser.requireAnyOf("Cơ sở này không thuộc tài khoản của bạn.", venue.getOwnerId());
        String playDate;
        try {
            playDate = (date == null || date.isBlank()) ? LocalDate.now().toString() : LocalDate.parse(date).toString();
        } catch (DateTimeParseException e) {
            return ResponseEntity.badRequest().body(Map.of("error", "Ngày không hợp lệ (định dạng yyyy-MM-dd)."));
        }

        List<Booking> bookings = bookingRepository.findByVenueIdAndPlayDateOrderByStartTimeAsc(venueId, playDate)
                .stream()
                .filter(b -> !"EXPIRED".equals(b.getStatus()))
                .filter(b -> !"HELD".equals(b.getStatus()) || BookingRules.isHoldActive(b))
                .sorted(Comparator.comparing(Booking::getStartTime).thenComparing(Booking::getCourtName))
                .toList();
        List<Court> courts = courtRepository.findByVenueIdOrderByIdAsc(venueId);

        Map<String, Object> summary = new LinkedHashMap<>();
        summary.put("sessions", bookings.stream().filter(this::isRevenue).count());
        summary.put("revenue", bookings.stream().mapToDouble(this::revenueOf).sum());
        summary.put("waitingCheckIn", bookings.stream()
                .filter(b -> "CONFIRMED".equals(b.getStatus()) && !"MAINTENANCE".equals(b.getBookingType()))
                .count());

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("venue", venue);
        res.put("playDate", playDate);
        res.put("courts", courts);
        res.put("bookings", bookings);
        res.put("summary", summary);
        return ResponseEntity.ok(res);
    }

    // S23: Chủ sân gửi yêu cầu đối soát / giải ngân (Payout Request) kèm xác thực OTP Email
    @PostMapping("/owner/payout-requests")
    @Transactional
    public ResponseEntity<?> createPayoutRequest(@RequestBody Map<String, Object> body) {
        Long ownerId = CurrentUser.idOr(body.getOrDefault("ownerId", 2));
        double grossAmount = Double.parseDouble(String.valueOf(body.getOrDefault("grossAmount", 0)));
        String bankName = String.valueOf(body.getOrDefault("bankName", "")).trim();
        String bankAccountNumber = String.valueOf(body.getOrDefault("bankAccountNumber", "")).trim();
        String bankAccountHolder = String.valueOf(body.getOrDefault("bankAccountHolder", "")).trim().toUpperCase();
        String otpCode = String.valueOf(body.getOrDefault("otpCode", "")).trim();

        User owner = userRepository.findById(ownerId).orElseThrow();
        List<Venue> ownVenues = venueRepository.findByOwnerIdOrderByIdDesc(ownerId);
        if (ownVenues.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Tài khoản chưa có cơ sở nào."));
        }
        Venue venue = ownVenues.get(ownVenues.size() - 1);
        if (body.get("venueId") != null) {
            Long venueId = Long.parseLong(String.valueOf(body.get("venueId")));
            venue = venueRepository.findById(venueId).orElseThrow();
            if (!ownerId.equals(venue.getOwnerId())) {
                return ResponseEntity.status(403).body(Map.of("error", "Cơ sở này không thuộc tài khoản của bạn."));
            }
        }
        if (bankName.isEmpty() || bankAccountNumber.length() < 6 || bankAccountHolder.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Vui lòng nhập đủ thông tin tài khoản ngân hàng."));
        }
        if (grossAmount <= 0) {
            return ResponseEntity.badRequest().body(Map.of("error", "Số tiền giải ngân phải lớn hơn 0."));
        }
        double available = availablePayoutGross(ownerId);
        if (grossAmount > available + 0.5) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "Số tiền yêu cầu vượt doanh thu online chưa giải ngân (" + (long) available + "đ)."));
        }
        if (!emailOtpService.verifyOtp(owner.getEmail(), otpCode, "PAYOUT")) {
            return ResponseEntity.badRequest().body(Map.of("error", "Mã bảo mật OTP không chính xác hoặc đã hết hạn."));
        }

        double commissionFee = commissionOf(grossAmount);
        double netAmount = grossAmount - commissionFee;

        PayoutRequest pr = new PayoutRequest();
        pr.setPayoutCode("PO-" + (System.currentTimeMillis() % 1000000));
        pr.setVenueId(venue.getId());
        pr.setVenueName(ownVenues.size() > 1 ? ownVenues.size() + " cơ sở" : venue.getName());
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

    /**
     * Dòng tiền nền tảng (thẻ trên Trang chủ Admin):
     * khách trả online cho các sân -> nền tảng giữ -> chủ sân xin rút -> Admin chuyển khoản (trừ 5% phí sàn).
     * Tiền nền tảng đang giữ = tiền sân thu online - tiền đã chuyển cho chủ sân + số dư Ví người dùng + cọc kèo đang giữ.
     */
    private Map<String, Object> platformCashflow(List<Venue> venues, List<User> users, List<PayoutRequest> payouts) {
        double ownerOnline = 0;
        double retainedTotal = 0;
        for (Venue v : venues) {
            for (Booking b : bookingRepository.findByVenueIdOrderByIdDesc(v.getId())) {
                if (!isOnline(b)) continue;
                ownerOnline += revenueOf(b);
                retainedTotal += retainedOf(b);
            }
        }
        double paidGross = 0, paidNet = 0, feeEarned = 0, pendingGross = 0, pendingNet = 0;
        for (PayoutRequest p : payouts) {
            if ("PAID".equals(p.getStatus())) {
                paidGross += p.getGrossAmount();
                paidNet += p.getNetPayoutAmount();
                feeEarned += p.getCommissionFee();
            } else if ("PENDING".equals(p.getStatus())) {
                pendingGross += p.getGrossAmount();
                pendingNet += p.getNetPayoutAmount();
            }
        }
        double unrequested = 0;
        for (User u : users) {
            if ("COURT_OWNER".equals(u.getRole())) unrequested += availablePayoutGross(u.getId());
        }
        double walletTotal = users.stream()
                .filter(u -> !"ADMIN".equals(u.getRole()))
                .mapToDouble(User::getWalletBalance)
                .sum();
        double heldDeposits = matchParticipantRepository.findAll().stream()
                .filter(mp -> "HELD".equals(mp.getDepositStatus()) && mp.getDepositAmount() != null)
                .mapToDouble(MatchParticipant::getDepositAmount)
                .sum();

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("ownerOnlineRevenue", ownerOnline);
        res.put("retainedFromCancellations", retainedTotal);
        res.put("payoutPaidGross", paidGross);
        res.put("payoutPaidNet", paidNet);
        res.put("platformFeeEarned", feeEarned);
        res.put("payoutPendingGross", pendingGross);
        res.put("payoutPendingNet", pendingNet);
        res.put("ownerUnrequested", unrequested);
        res.put("userWalletTotal", walletTotal);
        res.put("heldMatchDeposits", heldDeposits);
        res.put("platformHolding", Math.max(0, ownerOnline - paidNet) + walletTotal + heldDeposits);
        return res;
    }

    /**
     * Doanh thu thanh toán online (PayOS / Ví) của chủ sân trừ phần đã gửi yêu cầu giải ngân
     * (trừ yêu cầu bị từ chối). Tiền mặt khách vãng lai chủ sân đã thu tại quầy nên không tính.
     */
    private double availablePayoutGross(Long ownerId) {
        double online = 0;
        for (Venue v : venueRepository.findByOwnerIdOrderByIdDesc(ownerId)) {
            for (Booking b : bookingRepository.findByVenueIdOrderByIdDesc(v.getId())) {
                if (isOnline(b)) online += revenueOf(b);
            }
        }
        double requested = payoutRequestRepository.findByOwnerIdOrderByIdDesc(ownerId).stream()
                .filter(p -> !"REJECTED".equals(p.getStatus()))
                .mapToDouble(PayoutRequest::getGrossAmount)
                .sum();
        return Math.max(0, online - requested);
    }

    // ============================================================== Quản trị viên

    // S24: tổng quan nền tảng
    @GetMapping("/admin/dashboard")
    public ResponseEntity<?> getAdminDashboard() {
        List<Venue> allVenues = venueRepository.findAll();
        List<User> allUsers = userRepository.findAll();
        List<PayoutRequest> allPayouts = payoutRequestRepository.findAllByOrderByIdDesc();
        // Nạp ví không phải doanh thu đặt sân
        List<Payment> paidPayments = paymentRepository.findByStatusOrderByIdDesc("PAID").stream()
                .filter(p -> !"TOPUP".equals(p.getPurpose()))
                .toList();
        String today = LocalDate.now().toString();

        double totalGmv = paidPayments.stream().mapToDouble(Payment::getAmount).sum();
        Map<String, double[]> byDay = emptyDays();
        for (Payment p : paidPayments) {
            String day = p.getPaidAt() != null && p.getPaidAt().length() >= 10
                    ? p.getPaidAt().substring(0, 10)
                    : (p.getCreatedAt() != null && p.getCreatedAt().length() >= 10 ? p.getCreatedAt().substring(0, 10) : "");
            double[] row = byDay.get(day);
            if (row != null) {
                row[0] += p.getAmount();
                row[1]++;
            }
        }

        long bookingsToday = 0;
        for (Venue v : allVenues) {
            bookingsToday += bookingRepository.findByVenueIdAndPlayDateOrderByStartTimeAsc(v.getId(), today)
                    .stream().filter(this::isRevenue).count();
        }

        Map<String, Long> usersByRole = new LinkedHashMap<>();
        for (String role : List.of("CUSTOMER", "COURT_OWNER", "ADMIN")) usersByRole.put(role, 0L);
        for (User u : allUsers) usersByRole.merge(String.valueOf(u.getRole()), 1L, Long::sum);

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("totalGmv", totalGmv);
        res.put("platformCommission", commissionOf(totalGmv));
        res.put("commissionRate", COMMISSION_RATE);
        res.put("totalUsers", allUsers.size());
        res.put("lockedUsersCount", allUsers.stream().filter(u -> !u.isActive()).count());
        res.put("usersByRole", usersByRole);
        res.put("totalVenues", allVenues.size());
        res.put("activeVenuesCount", allVenues.stream().filter(v -> "APPROVED".equals(v.getStatus())).count());
        res.put("pendingVenuesCount", allVenues.stream().filter(v -> "PENDING".equals(v.getStatus())).count());
        res.put("pendingPayoutsCount", allPayouts.stream().filter(p -> "PENDING".equals(p.getStatus())).count());
        res.put("pendingPayoutsAmount", allPayouts.stream()
                .filter(p -> "PENDING".equals(p.getStatus()))
                .mapToDouble(PayoutRequest::getNetPayoutAmount).sum());
        res.put("bookingsToday", bookingsToday);
        res.put("gmvLast7Days", dayRows(byDay));
        res.put("venues", allVenues);
        res.put("users", allUsers);
        res.put("payoutRequests", allPayouts);
        res.put("recentPayments", paidPayments.subList(0, Math.min(20, paidPayments.size())));
        res.put("cashflow", platformCashflow(allVenues, allUsers, allPayouts));
        return ResponseEntity.ok(res);
    }

    // S25: duyệt / từ chối / tạm ngưng / mở lại cơ sở. Body: {status, reason?}
    @PatchMapping("/admin/venues/{venueId}/status")
    @Transactional
    public ResponseEntity<?> moderateVenue(@PathVariable Long venueId, @RequestBody Map<String, String> body) {
        String status = String.valueOf(body.getOrDefault("status", "")).trim().toUpperCase();
        String reason = trimReason(body.get("reason"));
        Venue venue = venueRepository.findById(venueId).orElseThrow();
        String current = venue.getStatus() == null ? "PENDING" : venue.getStatus();
        if (!VENUE_TRANSITIONS.getOrDefault(current, Set.of()).contains(status)) {
            return ResponseEntity.status(409).body(Map.of(
                    "error", "Không thể chuyển cơ sở từ trạng thái " + current + " sang " + status + "."));
        }
        if ("REJECTED".equals(status) && reason == null) {
            return ResponseEntity.badRequest().body(Map.of("error", "Vui lòng nhập lý do từ chối để chủ sân chỉnh sửa."));
        }
        venue.setStatus(status);
        venueRepository.save(venue);

        String title;
        String message;
        switch (status) {
            case "APPROVED" -> {
                title = "Cơ sở '" + venue.getName() + "' đã được phê duyệt!";
                message = "Sân của bạn đã hiển thị trên Bản đồ và sẵn sàng nhận khách đặt online.";
            }
            case "REJECTED" -> {
                title = "Hồ sơ cơ sở '" + venue.getName() + "' bị từ chối";
                message = "Lý do: " + reason;
            }
            default -> {
                title = "Cơ sở '" + venue.getName() + "' tạm ngưng hiển thị";
                message = reason != null ? "Lý do: " + reason : "Vui lòng liên hệ Admin để biết thêm chi tiết.";
            }
        }
        notificationService.notifyUser(venue.getOwnerId(), title, message, "SYSTEM", "S19", venue.getId());
        return ResponseEntity.ok(venue);
    }

    // S25: khóa / mở khóa tài khoản (không khóa được tài khoản Admin, kể cả chính mình)
    @PatchMapping("/admin/users/{userId}/toggle-active")
    @Transactional
    public ResponseEntity<?> toggleUserActive(@PathVariable Long userId) {
        User u = userRepository.findById(userId).orElseThrow();
        Long currentId = CurrentUser.get().map(AuthUser::id).orElse(null);
        if (userId.equals(currentId)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Bạn không thể tự khóa tài khoản của mình."));
        }
        if ("ADMIN".equals(u.getRole())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Không thể khóa tài khoản Quản trị viên."));
        }
        u.setActive(!u.isActive());
        User saved = userRepository.save(u);
        if (saved.isActive()) {
            notificationService.notifyUser(saved.getId(), "Tài khoản đã được mở khóa",
                    "Bạn có thể đăng nhập và sử dụng ứng dụng bình thường.", "SYSTEM", "S06", saved.getId());
        }
        return ResponseEntity.ok(saved);
    }

    // S26: Admin xác nhận đã chuyển khoản (PAID) hoặc từ chối (REJECTED, cần lý do). Body: {status, reason?}
    @PatchMapping("/admin/payout-requests/{id}/status")
    @Transactional
    public ResponseEntity<?> updatePayoutStatus(@PathVariable Long id, @RequestBody Map<String, String> body) {
        String status = String.valueOf(body.getOrDefault("status", "")).trim().toUpperCase();
        String reason = trimReason(body.get("reason"));
        PayoutRequest pr = payoutRequestRepository.findById(id).orElseThrow();
        if (!List.of("PAID", "REJECTED").contains(status)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Trạng thái giải ngân không hợp lệ."));
        }
        if (!"PENDING".equals(pr.getStatus())) {
            return ResponseEntity.status(409).body(Map.of("error", "Yêu cầu #" + pr.getPayoutCode() + " đã được xử lý trước đó."));
        }
        if ("REJECTED".equals(status) && reason == null) {
            return ResponseEntity.badRequest().body(Map.of("error", "Vui lòng nhập lý do từ chối."));
        }
        pr.setStatus(status);
        if ("PAID".equals(status)) {
            pr.setPaidAt(LocalDateTime.now().format(FMT));
        }
        payoutRequestRepository.save(pr);

        notificationService.notifyUser(
                pr.getOwnerId(),
                "PAID".equals(status)
                        ? "Admin đã giải ngân đối soát #" + pr.getPayoutCode()
                        : "Yêu cầu giải ngân #" + pr.getPayoutCode() + " bị từ chối",
                "PAID".equals(status)
                        ? "Số tiền " + (long) pr.getNetPayoutAmount() + "đ đã được chuyển vào tài khoản " + pr.getBankName() + " (" + pr.getBankAccountNumber() + ")."
                        : "Lý do: " + reason + ". Doanh thu đã được trả lại để bạn gửi yêu cầu mới.",
                "PAYMENT",
                "S23",
                pr.getId()
        );
        return ResponseEntity.ok(pr);
    }

    // ==================================================================== Tiện ích

    private boolean isRevenue(Booking b) {
        return REVENUE_STATUSES.contains(b.getStatus()) && !"MAINTENANCE".equals(b.getBookingType());
    }

    /** Phần tiền giữ lại của vé đã thanh toán nhưng bị hủy muộn. */
    private static double retainedOf(Booking b) {
        return "CANCELLED".equals(b.getStatus()) && b.getRetainedAmount() != null ? b.getRetainedAmount() : 0;
    }

    /** Doanh thu của một vé với chủ sân: vé hợp lệ = giá vé, vé hủy muộn = phần giữ lại. */
    private double revenueOf(Booking b) {
        return isRevenue(b) ? b.getTotalPrice() : retainedOf(b);
    }

    private boolean isOnline(Booking b) {
        return ONLINE_METHODS.contains(b.getPaymentMethod());
    }

    private static double commissionOf(double gross) {
        return Math.round(gross * COMMISSION_RATE);
    }

    private static int hoursOf(Booking b) {
        return Math.max(0, (BookingRules.toMinutes(b.getEndTime()) - BookingRules.toMinutes(b.getStartTime())) / 60);
    }

    private int activeCourts(Venue v) {
        List<Court> courts = courtRepository.findByVenueIdOrderByIdAsc(v.getId());
        long active = courts.stream().filter(Court::isActive).count();
        return (int) (courts.isEmpty() ? v.getTotalCourts() : active);
    }

    private static int openHours(Venue v) {
        return Math.max(0, (BookingRules.closeMinutes(v) - BookingRules.openMinutes(v)) / 60);
    }

    /** 7 ngày gần nhất (cũ -> mới, gồm hôm nay), mỗi ngày [giá trị, số lượng]. */
    private static Map<String, double[]> emptyDays() {
        Map<String, double[]> days = new LinkedHashMap<>();
        LocalDate today = LocalDate.now();
        for (int i = CHART_DAYS - 1; i >= 0; i--) {
            days.put(today.minusDays(i).toString(), new double[]{0, 0});
        }
        return days;
    }

    private static List<Map<String, Object>> dayRows(Map<String, double[]> days) {
        List<Map<String, Object>> rows = new ArrayList<>();
        days.forEach((date, v) -> {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("date", date);
            row.put("amount", v[0]);
            row.put("count", (long) v[1]);
            rows.add(row);
        });
        return rows;
    }

    private static String trimReason(String raw) {
        if (raw == null || raw.isBlank()) return null;
        String r = raw.trim();
        return r.length() > 300 ? r.substring(0, 300) : r;
    }
}
