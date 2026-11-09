package com.badminton.v2.controller;

import com.badminton.v2.entity.*;
import com.badminton.v2.repository.*;
import com.badminton.v2.service.NotificationService;
import com.badminton.v2.service.BookingRules;
import com.badminton.v2.security.CurrentUser;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestClient;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

@RestController
@RequestMapping("/api")
public class BookingPaymentController {

    private static final Logger log = LoggerFactory.getLogger(BookingPaymentController.class);
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final BookingRepository bookingRepository;
    private final PaymentRepository paymentRepository;
    private final RefundRepository refundRepository;
    private final VenueRepository venueRepository;
    private final CourtRepository courtRepository;
    private final UserRepository userRepository;
    private final WalletTransactionRepository walletTransactionRepository;
    private final NotificationService notificationService;
    private final RestClient restClient;

    @Value("${app.payos.client-id:}")
    private String payosClientId;

    @Value("${app.payos.api-key:}")
    private String payosApiKey;

    @Value("${app.payos.checksum-key:}")
    private String payosChecksumKey;

    @Value("${app.payos.return-url:https://badminton-v2.demo/payment/success}")
    private String payosReturnUrl;

    @Value("${app.payos.cancel-url:https://badminton-v2.demo/payment/cancel}")
    private String payosCancelUrl;

    public BookingPaymentController(BookingRepository bookingRepository,
                                    PaymentRepository paymentRepository,
                                    RefundRepository refundRepository,
                                    VenueRepository venueRepository,
                                    CourtRepository courtRepository,
                                    UserRepository userRepository,
                                    WalletTransactionRepository walletTransactionRepository,
                                    NotificationService notificationService,
                                    RestClient restClient) {
        this.bookingRepository = bookingRepository;
        this.paymentRepository = paymentRepository;
        this.refundRepository = refundRepository;
        this.venueRepository = venueRepository;
        this.courtRepository = courtRepository;
        this.userRepository = userRepository;
        this.walletTransactionRepository = walletTransactionRepository;
        this.notificationService = notificationService;
        this.restClient = restClient;
    }

    // Luồng 1: Giữ chỗ tạm thời (HELD 5 phút) chống trùng sân
    @PostMapping("/bookings/hold")
    @Transactional
    public ResponseEntity<?> holdBookingSlot(@RequestBody Map<String, Object> body) {
        Long venueId = Long.parseLong(String.valueOf(body.get("venueId")));
        Long courtId = Long.parseLong(String.valueOf(body.get("courtId")));
        // Khách đặt = người đang đăng nhập (không tin "customerId" app gửi lên)
        Long customerId = CurrentUser.idOr(body.get("customerId"));
        String playDate = String.valueOf(body.getOrDefault("playDate", LocalDate.now().toString()));
        String startTime = String.valueOf(body.getOrDefault("startTime", "18:00"));
        String endTime = String.valueOf(body.getOrDefault("endTime", "20:00"));

        Venue venue = venueRepository.findById(venueId).orElseThrow();
        Court court = courtRepository.findById(courtId).orElseThrow();
        User customer = userRepository.findById(customerId).orElseThrow();

        if (!venueId.equals(court.getVenueId()) || !court.isActive()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Sân không thuộc cơ sở này hoặc đang tạm ngưng."));
        }
        if (!"APPROVED".equals(venue.getStatus())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Cơ sở chưa được phê duyệt để nhận đặt sân."));
        }
        String slotError = validateSlot(venue, playDate, startTime, endTime);
        if (slotError != null) {
            return ResponseEntity.badRequest().body(Map.of("error", slotError));
        }
        if (hasTimeConflict(courtId, playDate, startTime, endTime, null)) {
            return ResponseEntity.status(409).body(Map.of(
                    "error", "Khung giờ này vừa có người đặt hoặc đang được giữ chỗ! Vui lòng chọn sân/giờ khác."
            ));
        }
        // Giá do máy chủ tính theo bảng giá cơ sở (không tin giá app gửi lên)
        double totalPrice = priceFor(venue, playDate, startTime, endTime);

        String bookingCode = "BK-" + (System.currentTimeMillis() % 1000000);
        Booking b = new Booking();
        b.setBookingCode(bookingCode);
        b.setVenueId(venueId);
        b.setVenueName(venue.getName());
        b.setCourtId(courtId);
        b.setCourtName(court.getName());
        b.setCustomerId(customerId);
        b.setCustomerName(customer.getFullName());
        b.setCustomerPhone(customer.getPhone());
        b.setBookingType("ONLINE");
        b.setPlayDate(playDate);
        b.setStartTime(startTime);
        b.setEndTime(endTime);
        b.setTotalPrice(totalPrice);
        b.setStatus("HELD");
        b.setHoldExpiresAt(LocalDateTime.now().plusMinutes(5).format(FMT));
        b.setRescheduledCount(0);
        b.setQrCheckInToken("QR-" + bookingCode);
        b.setPaymentMethod("PENDING");
        b.setCreatedAt(LocalDateTime.now().format(FMT));

        b = bookingRepository.save(b);
        return ResponseEntity.ok(b);
    }

    // Luồng 1 + Module 3: Tạo mã thanh toán VietQR PayOS
    @PostMapping("/payments/create-payos")
    @Transactional
    public ResponseEntity<?> createPayosPayment(@RequestBody Map<String, Object> body) {
        Long bookingId = Long.parseLong(String.valueOf(body.get("bookingId")));
        Booking booking = bookingRepository.findById(bookingId).orElseThrow();
        CurrentUser.requireSelfOrAdmin(booking.getCustomerId());
        if (!isHoldActive(booking)) {
            return ResponseEntity.status(409).body(Map.of("error", HOLD_EXPIRED_MESSAGE));
        }

        long orderCode = System.currentTimeMillis() / 1000;
        int amountInt = (int) Math.round(booking.getTotalPrice());
        String description = "Dat san " + booking.getBookingCode();

        String qrData = "00020101021238570010A00000072701270006970436011300710012345670208QRIBFTTA5303704540"
                + String.valueOf(amountInt).length() + amountInt + "5802VN62180814" + booking.getBookingCode() + "6304PAYOS";
        String checkoutUrl = "https://pay.payos.vn/web/demo-" + orderCode;

        // If user configured real PayOS keys in application.yml, call real PayOS v2 API
        if (payosClientId != null && !payosClientId.isBlank()
                && payosApiKey != null && !payosApiKey.isBlank()
                && payosChecksumKey != null && !payosChecksumKey.isBlank()) {
            try {
                String dataToSign = "amount=" + amountInt
                        + "&cancelUrl=" + payosCancelUrl
                        + "&description=" + description
                        + "&orderCode=" + orderCode
                        + "&returnUrl=" + payosReturnUrl;
                String signature = hmacSha256(dataToSign, payosChecksumKey);

                Map<String, Object> reqPayload = Map.of(
                        "orderCode", orderCode,
                        "amount", amountInt,
                        "description", description,
                        "cancelUrl", payosCancelUrl,
                        "returnUrl", payosReturnUrl,
                        "signature", signature
                );
                @SuppressWarnings("unchecked")
                Map<String, Object> resp = restClient.post()
                        .uri("https://api-merchant.payos.vn/v2/payment-requests")
                        .header("x-client-id", payosClientId)
                        .header("x-api-key", payosApiKey)
                        .contentType(MediaType.APPLICATION_JSON)
                        .body(reqPayload)
                        .retrieve()
                        .body(Map.class);

                if (resp != null && resp.get("data") instanceof Map<?, ?> dataMap) {
                    if (dataMap.get("qrCode") != null) qrData = String.valueOf(dataMap.get("qrCode"));
                    if (dataMap.get("checkoutUrl") != null) checkoutUrl = String.valueOf(dataMap.get("checkoutUrl"));
                }
            } catch (Exception e) {
                log.warn("PayOS live API fallback activated: {}", e.getMessage());
            }
        }

        Payment payment = new Payment();
        payment.setBookingId(booking.getId());
        payment.setBookingCode(booking.getBookingCode());
        payment.setPayosOrderCode(orderCode);
        payment.setPaymentMethod("PAYOS_QR");
        payment.setAmount(booking.getTotalPrice());
        payment.setStatus("PENDING");
        payment.setCheckoutUrl(checkoutUrl);
        payment.setQrCodeData(qrData);
        payment.setCreatedAt(LocalDateTime.now().format(FMT));
        payment = paymentRepository.save(payment);

        return ResponseEntity.ok(Map.of(
                "payment", payment,
                "booking", booking
        ));
    }

    // Luồng 1 + Module 3: Webhook chính thức từ PayOS
    @PostMapping("/payments/payos-webhook")
    @Transactional
    public ResponseEntity<?> handlePayosWebhook(@RequestBody Map<String, Object> webhookPayload) {
        log.info("[MODULE 3 - PAYOS WEBHOOK] Received payload: {}", webhookPayload);
        Long orderCode = null;
        if (webhookPayload.get("data") instanceof Map<?, ?> dataMap && dataMap.get("orderCode") != null) {
            orderCode = Long.parseLong(String.valueOf(dataMap.get("orderCode")));
        } else if (webhookPayload.get("orderCode") != null) {
            orderCode = Long.parseLong(String.valueOf(webhookPayload.get("orderCode")));
        }
        if (orderCode == null) {
            return ResponseEntity.ok(Map.of("success", true));
        }
        return confirmPayosOrder(orderCode, true);
    }

    // Nút hỗ trợ Demo Webhook PayOS trên lớp học
    @PostMapping("/payments/simulate-webhook/{orderCode}")
    @Transactional
    public ResponseEntity<?> simulatePayosWebhook(@PathVariable Long orderCode) {
        paymentRepository.findByPayosOrderCode(orderCode)
                .flatMap(p -> bookingRepository.findById(p.getBookingId()))
                .ifPresent(b -> CurrentUser.requireSelfOrAdmin(b.getCustomerId()));
        return confirmPayosOrder(orderCode, false);
    }

    // S11: App hỏi định kỳ trạng thái thanh toán (PENDING / PAID / CANCELLED)
    @GetMapping("/payments/{orderCode}/status")
    public ResponseEntity<?> getPaymentStatus(@PathVariable Long orderCode) {
        Payment payment = paymentRepository.findByPayosOrderCode(orderCode).orElseThrow();
        Booking booking = bookingRepository.findById(payment.getBookingId()).orElseThrow();
        CurrentUser.requireSelfOrAdmin(booking.getCustomerId());
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("orderCode", orderCode);
        res.put("status", payment.getStatus());
        res.put("paid", "PAID".equals(payment.getStatus()) && "CONFIRMED".equals(booking.getStatus()));
        res.put("holdActive", isHoldActive(booking));
        res.put("booking", booking);
        return ResponseEntity.ok(res);
    }

    /**
     * Xác nhận đơn PayOS đã thanh toán.
     * @param realPayment true = webhook thật từ PayOS (tiền đã chuyển), false = nút giả lập khi demo.
     */
    private ResponseEntity<?> confirmPayosOrder(Long orderCode, boolean realPayment) {
        Optional<Payment> opt = paymentRepository.findByPayosOrderCode(orderCode);
        if (opt.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Không tìm thấy mã đơn PayOS: " + orderCode));
        }
        Payment payment = opt.get();
        Booking booking = bookingRepository.findById(payment.getBookingId()).orElseThrow();

        // Webhook có thể gửi lại nhiều lần: đơn đã xác nhận thì trả kết quả cũ
        if ("PAID".equals(payment.getStatus())) {
            return ResponseEntity.ok(Map.of("success", true, "payment", payment, "booking", booking));
        }
        if (!isHoldActive(booking)) {
            if (!realPayment) {
                return ResponseEntity.status(409).body(Map.of("error", HOLD_EXPIRED_MESSAGE));
            }
            // Khách đã chuyển tiền nhưng giữ chỗ đã hết hạn: ghi nhận và hoàn toàn bộ vào Ví nội bộ
            payment.setStatus("PAID");
            payment.setPaidAt(LocalDateTime.now().format(FMT));
            paymentRepository.save(payment);
            refundLatePayment(booking, payment.getAmount());
            return ResponseEntity.ok(Map.of("success", true, "refundedToWallet", true, "booking", booking));
        }

        payment.setStatus("PAID");
        payment.setPaidAt(LocalDateTime.now().format(FMT));
        paymentRepository.save(payment);

        booking.setStatus("CONFIRMED");
        booking.setPaymentMethod("PAYOS_QR");
        bookingRepository.save(booking);

        notificationService.notifyUser(
                booking.getCustomerId(),
                "Thanh toán PayOS VietQR thành công!",
                "Vé " + booking.getBookingCode() + " tại " + booking.getVenueName() + " (" + booking.getCourtName()
                        + ", " + booking.getStartTime() + "-" + booking.getEndTime() + ") đã xác nhận. Mã QR Check-in đã sẵn sàng!",
                "PAYMENT",
                "S13",
                booking.getId()
        );

        venueRepository.findById(booking.getVenueId()).ifPresent(v ->
                notificationService.notifyUser(
                        v.getOwnerId(),
                        "Có đơn đặt sân mới đã thanh toán PayOS",
                        "Khách " + booking.getCustomerName() + " vừa đặt " + booking.getCourtName() + " (" + booking.getStartTime() + "-" + booking.getEndTime() + ").",
                        "BOOKING",
                        "S21",
                        booking.getId()
                )
        );

        return ResponseEntity.ok(Map.of(
                "success", true,
                "payment", payment,
                "booking", booking
        ));
    }

    // Thanh toán bằng Ví Cầu Lông nội bộ
    @PostMapping("/payments/pay-with-wallet")
    @Transactional
    public ResponseEntity<?> payWithWallet(@RequestBody Map<String, Object> body) {
        Long bookingId = Long.parseLong(String.valueOf(body.get("bookingId")));
        Long userId = CurrentUser.idOr(body.get("userId"));

        Booking booking = bookingRepository.findById(bookingId).orElseThrow();
        User user = userRepository.findById(userId).orElseThrow();

        if (!userId.equals(booking.getCustomerId())) {
            return ResponseEntity.status(403).body(Map.of("error", "Vé này không thuộc tài khoản của bạn."));
        }
        // Chặn trả 2 lần cho cùng một vé và trả cho giữ chỗ đã hết hạn
        if (!isHoldActive(booking)) {
            return ResponseEntity.status(409).body(Map.of("error", HOLD_EXPIRED_MESSAGE));
        }
        if (user.getWalletBalance() < booking.getTotalPrice()) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "Số dư Ví không đủ (" + (long) user.getWalletBalance() + "đ < " + (long) booking.getTotalPrice() + "đ). Vui lòng chọn Quét QR PayOS!"
            ));
        }

        user.setWalletBalance(user.getWalletBalance() - booking.getTotalPrice());
        userRepository.save(user);

        walletTransactionRepository.save(new WalletTransaction(
                userId,
                "Thanh toán đặt sân " + booking.getBookingCode() + " (" + booking.getVenueName() + ")",
                -booking.getTotalPrice(),
                "BOOKING_PAYMENT",
                user.getWalletBalance(),
                LocalDateTime.now().format(FMT)
        ));

        booking.setStatus("CONFIRMED");
        booking.setPaymentMethod("WALLET");
        bookingRepository.save(booking);

        Payment payment = new Payment();
        payment.setBookingId(booking.getId());
        payment.setBookingCode(booking.getBookingCode());
        payment.setPayosOrderCode(System.currentTimeMillis() / 1000);
        payment.setPaymentMethod("WALLET");
        payment.setAmount(booking.getTotalPrice());
        payment.setStatus("PAID");
        payment.setPaidAt(LocalDateTime.now().format(FMT));
        payment.setCreatedAt(LocalDateTime.now().format(FMT));
        paymentRepository.save(payment);

        notificationService.notifyUser(
                userId,
                "Thanh toán bằng Ví Cầu Lông thành công",
                "Đã trừ " + (long) booking.getTotalPrice() + "đ cho vé " + booking.getBookingCode() + ". Số dư còn lại: " + (long) user.getWalletBalance() + "đ.",
                "PAYMENT",
                "S13",
                booking.getId()
        );

        return ResponseEntity.ok(Map.of(
                "booking", booking,
                "walletBalance", user.getWalletBalance()
        ));
    }

    // Khách rời màn thanh toán: trả lại chỗ đang giữ ngay, không chờ hết 5 phút
    @PostMapping("/bookings/{id}/release")
    @Transactional
    public ResponseEntity<?> releaseHeldBooking(@PathVariable Long id,
                                                @RequestBody(required = false) Map<String, Object> body) {
        Booking b = bookingRepository.findById(id).orElseThrow();
        CurrentUser.requireSelfOrAdmin(b.getCustomerId());
        if (List.of("CONFIRMED", "CHECKED_IN", "COMPLETED").contains(b.getStatus())) {
            return ResponseEntity.status(409).body(Map.of("error", "Vé đã thanh toán, hãy dùng chức năng Hủy vé để được hoàn tiền."));
        }
        if ("HELD".equals(b.getStatus())) {
            b.setStatus("CANCELLED");
            bookingRepository.save(b);
            paymentRepository.findTopByBookingIdOrderByIdDesc(id).ifPresent(p -> {
                if ("PENDING".equals(p.getStatus())) {
                    p.setStatus("CANCELLED");
                    paymentRepository.save(p);
                }
            });
        }
        return ResponseEntity.ok(Map.of("booking", b));
    }

    @GetMapping("/bookings/customer/{customerId}")
    public List<Booking> getCustomerBookings(@PathVariable Long customerId) {
        CurrentUser.requireSelfOrAdmin(customerId);
        return bookingRepository.findByCustomerIdOrderByIdDesc(customerId);
    }

    @GetMapping("/bookings/{id}")
    public ResponseEntity<?> getBookingDetail(@PathVariable Long id) {
        bookingRepository.findById(id).ifPresent(this::requireBookingAccess);
        return bookingRepository.findById(id).map(b -> {
            Map<String, Object> res = new LinkedHashMap<>();
            res.put("booking", b);
            res.put("payment", paymentRepository.findTopByBookingIdOrderByIdDesc(id).orElse(null));
            res.put("refunds", refundRepository.findByBookingIdOrderByIdDesc(id));
            return ResponseEntity.ok(res);
        }).orElse(ResponseEntity.notFound().build());
    }

    // Luồng 4: Đổi lịch đặt sân (Reschedule)
    @PostMapping("/bookings/{id}/reschedule")
    @Transactional
    public ResponseEntity<?> rescheduleBooking(@PathVariable Long id, @RequestBody Map<String, Object> body) {
        Booking b = bookingRepository.findById(id).orElseThrow();
        CurrentUser.requireSelfOrAdmin(b.getCustomerId());
        if (!"CONFIRMED".equals(b.getStatus())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Chỉ vé đã thanh toán và chưa sử dụng mới được đổi lịch."));
        }
        if (b.getRescheduledCount() >= 1) {
            return ResponseEntity.badRequest().body(Map.of("error", "Mỗi vé chỉ được phép đổi lịch tối đa 1 lần!"));
        }
        String newDate = String.valueOf(body.getOrDefault("playDate", b.getPlayDate()));
        String newStart = String.valueOf(body.getOrDefault("startTime", "19:00"));
        String newEnd = String.valueOf(body.getOrDefault("endTime", "21:00"));
        Long newCourtId = body.get("courtId") != null ? Long.parseLong(String.valueOf(body.get("courtId"))) : b.getCourtId();

        if (calculateHoursUntilPlay(b.getPlayDate(), b.getStartTime()) < RESCHEDULE_CUTOFF_HOURS
                || calculateHoursUntilPlay(newDate, newStart) < RESCHEDULE_CUTOFF_HOURS) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "Chỉ được đổi lịch khi cả giờ cũ và giờ mới còn cách ít nhất " + RESCHEDULE_CUTOFF_HOURS + " tiếng."
            ));
        }
        Court targetCourt = courtRepository.findById(newCourtId).orElseThrow();
        if (!b.getVenueId().equals(targetCourt.getVenueId())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Chỉ được đổi sang sân trong cùng cơ sở."));
        }
        Venue venue = venueRepository.findById(b.getVenueId()).orElseThrow();
        String slotError = validateSlot(venue, newDate, newStart, newEnd);
        if (slotError != null) {
            return ResponseEntity.badRequest().body(Map.of("error", slotError));
        }
        if (hasTimeConflict(newCourtId, newDate, newStart, newEnd, b.getId())) {
            return ResponseEntity.status(409).body(Map.of("error", "Khung giờ mới đã có người đặt, vui lòng chọn khung giờ khác!"));
        }

        // Chênh lệch giá giữa khung giờ mới và cũ: dương = khách bù thêm từ Ví, âm = hoàn vào Ví
        double oldPrice = b.getTotalPrice();
        double newPrice = priceFor(venue, newDate, newStart, newEnd);
        double diff = Math.round(newPrice - oldPrice);
        User customer = b.getCustomerId() != null ? userRepository.findById(b.getCustomerId()).orElse(null) : null;
        if (diff != 0 && customer == null) {
            return ResponseEntity.badRequest().body(Map.of("error", "Không tìm thấy Ví của khách để xử lý chênh lệch giá."));
        }
        if (diff > 0 && customer.getWalletBalance() < diff) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "Số dư Ví không đủ để bù chênh lệch " + (long) diff + "đ."
            ));
        }

        b.setCourtId(newCourtId);
        b.setCourtName(targetCourt.getName());
        b.setPlayDate(newDate);
        b.setStartTime(newStart);
        b.setEndTime(newEnd);
        b.setRescheduledCount(b.getRescheduledCount() + 1);
        b.setTotalPrice(oldPrice + diff);
        bookingRepository.save(b);

        if (diff != 0) {
            customer.setWalletBalance(customer.getWalletBalance() - diff);
            userRepository.save(customer);
            walletTransactionRepository.save(new WalletTransaction(
                    customer.getId(),
                    (diff > 0 ? "Bù chênh lệch đổi lịch vé " : "Hoàn chênh lệch đổi lịch vé ") + b.getBookingCode(),
                    -diff,
                    diff > 0 ? "BOOKING_PAYMENT" : "REFUND",
                    customer.getWalletBalance(),
                    LocalDateTime.now().format(FMT)
            ));
        }

        notificationService.notifyUser(
                b.getCustomerId(),
                "Đổi lịch đặt sân thành công (#" + b.getBookingCode() + ")",
                "Lịch mới: " + b.getCourtName() + " (" + newStart + " - " + newEnd + ", ngày " + newDate + ").",
                "BOOKING",
                "S13",
                b.getId()
        );
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("booking", b);
        res.put("priceDifference", diff);
        if (customer != null) res.put("walletBalance", customer.getWalletBalance());
        return ResponseEntity.ok(res);
    }

    // Luồng 4: Hủy sân & Tự động hoàn tiền về Ví nội bộ theo mốc thời gian (>=24h: 100%, 6-24h: 50%, <6h: 0%)
    @PostMapping("/bookings/{id}/cancel")
    @Transactional
    public ResponseEntity<?> cancelAndRefundBooking(@PathVariable Long id, @RequestBody Map<String, Object> body) {
        Booking b = bookingRepository.findById(id).orElseThrow();
        CurrentUser.requireSelfOrAdmin(b.getCustomerId());
        if ("CANCELLED".equals(b.getStatus())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Vé đặt sân này đã được hủy trước đó."));
        }
        if (List.of("CHECKED_IN", "COMPLETED", "EXPIRED").contains(b.getStatus())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Vé đã sử dụng hoặc đã hết hạn, không thể hủy."));
        }
        // Vé chưa thanh toán (HELD) thì hủy giữ chỗ, không phát sinh hoàn tiền
        boolean paid = "CONFIRMED".equals(b.getStatus());
        String reason = String.valueOf(body.getOrDefault("reason", "Thay đổi kế hoạch cá nhân"));

        long hoursUntilPlay = calculateHoursUntilPlay(b.getPlayDate(), b.getStartTime());
        int refundPercent;
        if (!paid) {
            refundPercent = 0;
        } else if (hoursUntilPlay >= 24) {
            refundPercent = 100;
        } else if (hoursUntilPlay >= 6) {
            refundPercent = 50;
        } else {
            // Chỉ khi demo trên lớp mới gửi demoFullRefund=true để ép hoàn 100%
            boolean forceDemoRefund = Boolean.parseBoolean(String.valueOf(body.getOrDefault("demoFullRefund", "false")));
            refundPercent = forceDemoRefund ? 100 : 0;
        }

        double refundAmount = Math.round((b.getTotalPrice() * refundPercent) / 100.0);
        b.setStatus("CANCELLED");
        bookingRepository.save(b);

        Refund refund = new Refund();
        refund.setBookingId(b.getId());
        refund.setBookingCode(b.getBookingCode());
        refund.setCustomerId(b.getCustomerId());
        refund.setRefundAmount(refundAmount);
        refund.setRefundPercentage(refundPercent);
        refund.setReason(reason);
        refund.setStatus("CREDITED_TO_WALLET");
        refund.setCreatedAt(LocalDateTime.now().format(FMT));
        refundRepository.save(refund);

        double updatedBalance = 0;
        if (b.getCustomerId() != null && refundAmount > 0) {
            User customer = userRepository.findById(b.getCustomerId()).orElseThrow();
            customer.setWalletBalance(customer.getWalletBalance() + refundAmount);
            userRepository.save(customer);
            updatedBalance = customer.getWalletBalance();

            walletTransactionRepository.save(new WalletTransaction(
                    customer.getId(),
                    "Hoàn tiền " + refundPercent + "% hủy vé " + b.getBookingCode(),
                    refundAmount,
                    "REFUND",
                    updatedBalance,
                    LocalDateTime.now().format(FMT)
            ));

            notificationService.notifyUser(
                    customer.getId(),
                    "Hoàn tiền hủy sân +" + (long) refundAmount + "đ vào Ví Cầu Lông",
                    "Đã hủy vé " + b.getBookingCode() + " và hoàn " + refundPercent + "% (" + (long) refundAmount + "đ) vào Ví nội bộ.",
                    "PAYMENT",
                    "S18",
                    b.getId()
            );
        }

        return ResponseEntity.ok(Map.of(
                "booking", b,
                "refund", refund,
                "walletBalance", updatedBalance,
                "message", "Đã hủy sân và hoàn " + refundPercent + "% (" + (long) refundAmount + "đ) vào Ví Cầu Lông!"
        ));
    }

    // Luồng 2 (Court Owner): Tạo khách vãng lai (Walk-in) hoặc Khóa sân bảo trì (Maintenance)
    @PostMapping("/owner/bookings/walk-in")
    @Transactional
    public ResponseEntity<?> createWalkInOrMaintenance(@RequestBody Map<String, Object> body) {
        Long venueId = Long.parseLong(String.valueOf(body.get("venueId")));
        Long courtId = Long.parseLong(String.valueOf(body.get("courtId")));
        String bookingType = String.valueOf(body.getOrDefault("bookingType", "WALK_IN")).toUpperCase();
        String playDate = String.valueOf(body.getOrDefault("playDate", LocalDate.now().toString()));
        String startTime = String.valueOf(body.getOrDefault("startTime", "19:00"));
        String endTime = String.valueOf(body.getOrDefault("endTime", "21:00"));
        String customerName = String.valueOf(body.getOrDefault("customerName",
                "MAINTENANCE".equals(bookingType) ? "Bảo trì sân / Thay lưới" : "Khách vãng lai tại quầy"));
        String customerPhone = String.valueOf(body.getOrDefault("customerPhone", "0900000000"));
        double totalPrice = "MAINTENANCE".equals(bookingType)
                ? 0.0
                : Double.parseDouble(String.valueOf(body.getOrDefault("totalPrice", 200000)));

        Venue venue = venueRepository.findById(venueId).orElseThrow();
        Court court = courtRepository.findById(courtId).orElseThrow();
        CurrentUser.requireAnyOf("Cơ sở này không thuộc tài khoản của bạn.", venue.getOwnerId());
        if (!venueId.equals(court.getVenueId())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Sân không thuộc cơ sở này."));
        }
        if (!List.of("WALK_IN", "MAINTENANCE").contains(bookingType)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Loại lịch không hợp lệ."));
        }
        if (hasTimeConflict(courtId, playDate, startTime, endTime, null)) {
            return ResponseEntity.status(409).body(Map.of("error", "Khung giờ này đã có lịch đặt trước!"));
        }
        String code = ("MAINTENANCE".equals(bookingType) ? "MT-" : "WI-") + (System.currentTimeMillis() % 1000000);

        Booking b = new Booking();
        b.setBookingCode(code);
        b.setVenueId(venueId);
        b.setVenueName(venue.getName());
        b.setCourtId(courtId);
        b.setCourtName(court.getName());
        b.setCustomerName(customerName);
        b.setCustomerPhone(customerPhone);
        b.setBookingType(bookingType);
        b.setPlayDate(playDate);
        b.setStartTime(startTime);
        b.setEndTime(endTime);
        b.setTotalPrice(totalPrice);
        b.setStatus("CONFIRMED");
        b.setQrCheckInToken("QR-" + code);
        b.setPaymentMethod("MAINTENANCE".equals(bookingType) ? "NONE" : "CASH");
        b.setCreatedAt(LocalDateTime.now().format(FMT));

        return ResponseEntity.ok(bookingRepository.save(b));
    }

    // Luồng 2 (Court Owner): Quét QR Check-in khách đến sân
    @PostMapping("/owner/bookings/check-in")
    @Transactional
    public ResponseEntity<?> checkInByQrOrCode(@RequestBody Map<String, String> body) {
        String codeOrToken = body.getOrDefault("code", "").trim();
        Optional<Booking> opt = bookingRepository.findByQrCheckInToken(codeOrToken);
        if (opt.isEmpty()) {
            opt = bookingRepository.findByBookingCode(codeOrToken.replace("QR-", ""));
        }
        if (opt.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Không tìm thấy vé đặt sân với mã: " + codeOrToken));
        }

        Booking b = opt.get();
        Long venueOwnerId = venueRepository.findById(b.getVenueId()).map(Venue::getOwnerId).orElse(null);
        CurrentUser.requireAnyOf("Vé này không thuộc cơ sở của bạn.", venueOwnerId);
        if ("CHECKED_IN".equals(b.getStatus())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Vé này đã check-in trước đó."));
        }
        if (!"CONFIRMED".equals(b.getStatus()) || "MAINTENANCE".equals(b.getBookingType())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Vé chưa thanh toán, đã hủy hoặc không phải vé của khách."));
        }
        b.setStatus("CHECKED_IN");
        bookingRepository.save(b);

        if (b.getCustomerId() != null) {
            notificationService.notifyUser(
                    b.getCustomerId(),
                    "Check-in nhận sân thành công!",
                    "Chúc bạn có buổi giao lưu cầu lông vui vẻ tại " + b.getVenueName() + " (" + b.getCourtName() + ").",
                    "BOOKING",
                    "S13",
                    b.getId()
            );
        }
        return ResponseEntity.ok(Map.of(
                "message", "Check-in thành công cho khách " + b.getCustomerName() + " tại " + b.getCourtName(),
                "booking", b
        ));
    }

    private boolean hasTimeConflict(Long courtId, String playDate, String start, String end, Long excludeBookingId) {
        List<Booking> existing = bookingRepository.findByCourtIdAndPlayDateOrderByStartTimeAsc(courtId, playDate);
        int reqStart = toMinutes(start);
        int reqEnd = toMinutes(end);
        for (Booking b : existing) {
            if (excludeBookingId != null && excludeBookingId.equals(b.getId())) continue;
            if (List.of("CANCELLED", "EXPIRED").contains(b.getStatus())) continue;
            if ("HELD".equals(b.getStatus()) && !isHoldActive(b)) continue;
            int exStart = toMinutes(b.getStartTime());
            int exEnd = toMinutes(b.getEndTime());
            if (reqStart < exEnd && reqEnd > exStart) {
                return true;
            }
        }
        return false;
    }

    /** Xem vé: khách đặt vé, chủ sân của cơ sở hoặc Admin. */
    private void requireBookingAccess(Booking b) {
        Long venueOwnerId = venueRepository.findById(b.getVenueId()).map(Venue::getOwnerId).orElse(null);
        CurrentUser.requireAnyOf("Bạn không có quyền xem vé này.", b.getCustomerId(), venueOwnerId);
    }

    private static final int RESCHEDULE_CUTOFF_HOURS = BookingRules.RESCHEDULE_CUTOFF_HOURS;
    private static final String HOLD_EXPIRED_MESSAGE =
            "Thời gian giữ chỗ đã hết hoặc vé không còn chờ thanh toán. Vui lòng chọn lại khung giờ.";

    /** Vé đang giữ chỗ (HELD) và chưa quá hạn thanh toán. */
    private boolean isHoldActive(Booking b) {
        return BookingRules.isHoldActive(b);
    }

    /**
     * Kiểm tra khung giờ đặt: đúng định dạng, theo giờ tròn, trong giờ mở cửa và chưa trôi qua.
     * Trả về câu báo lỗi, hoặc null nếu hợp lệ.
     */
    private String validateSlot(Venue venue, String playDate, String start, String end) {
        LocalDate date;
        int s;
        int e;
        try {
            date = LocalDate.parse(playDate);
            s = toMinutes(start);
            e = toMinutes(end);
        } catch (Exception ex) {
            return "Ngày hoặc giờ đặt sân không hợp lệ.";
        }
        if (s % 60 != 0 || e % 60 != 0 || e <= s) {
            return "Khung giờ phải theo giờ tròn và giờ kết thúc sau giờ bắt đầu.";
        }
        int open = toMinutes(venue.getOpenTime() != null ? venue.getOpenTime() : "05:00");
        int close = toMinutes(venue.getCloseTime() != null ? venue.getCloseTime() : "23:00");
        if (close <= open) close = 24 * 60;
        if (s < open || e > close) {
            return "Khung giờ nằm ngoài giờ mở cửa (" + venue.getOpenTime() + " - " + venue.getCloseTime() + ").";
        }
        if (!LocalDateTime.of(date, LocalTime.of(s / 60, 0)).isAfter(LocalDateTime.now())) {
            return "Khung giờ đã trôi qua, vui lòng chọn giờ khác.";
        }
        return null;
    }

    /** Giá theo từng giờ: giờ vàng từ 17:00 ngày thường và cả ngày cuối tuần (giống BookingRules ở app). */
    /** Giá theo bảng giá cơ sở - dùng chung với Trợ lý AI (service/BookingRules). */
    private double priceFor(Venue venue, String playDate, String start, String end) {
        return BookingRules.priceFor(venue, playDate, start, end);
    }

    /** Tiền PayOS về sau khi giữ chỗ hết hạn: cộng lại vào Ví của khách. */
    private void refundLatePayment(Booking booking, double amount) {
        if (booking.getCustomerId() == null || amount <= 0) return;
        userRepository.findById(booking.getCustomerId()).ifPresent(customer -> {
            customer.setWalletBalance(customer.getWalletBalance() + amount);
            userRepository.save(customer);
            walletTransactionRepository.save(new WalletTransaction(
                    customer.getId(),
                    "Hoàn tiền PayOS vé " + booking.getBookingCode() + " (giữ chỗ đã hết hạn)",
                    amount,
                    "REFUND",
                    customer.getWalletBalance(),
                    LocalDateTime.now().format(FMT)
            ));
            notificationService.notifyUser(
                    customer.getId(),
                    "Đã hoàn " + (long) amount + "đ vào Ví Cầu Lông",
                    "Thanh toán cho vé " + booking.getBookingCode() + " đến sau khi hết thời gian giữ chỗ nên đã được hoàn vào Ví.",
                    "PAYMENT",
                    "S18",
                    booking.getId()
            );
        });
    }

    private int toMinutes(String hhmm) {
        String[] parts = hhmm.split(":");
        return Integer.parseInt(parts[0]) * 60 + Integer.parseInt(parts[1]);
    }

    private long calculateHoursUntilPlay(String playDate, String startTime) {
        try {
            LocalDate d = LocalDate.parse(playDate);
            LocalTime t = LocalTime.parse(startTime);
            LocalDateTime playDateTime = LocalDateTime.of(d, t);
            return Duration.between(LocalDateTime.now(), playDateTime).toHours();
        } catch (Exception e) {
            return 25;
        }
    }

    private String hmacSha256(String data, String key) throws Exception {
        Mac sha256Hmac = Mac.getInstance("HmacSHA256");
        SecretKeySpec secretKey = new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), "HmacSHA256");
        sha256Hmac.init(secretKey);
        byte[] hash = sha256Hmac.doFinal(data.getBytes(StandardCharsets.UTF_8));
        StringBuilder hexString = new StringBuilder();
        for (byte b : hash) {
            String hex = Integer.toHexString(0xff & b);
            if (hex.length() == 1) hexString.append('0');
            hexString.append(hex);
        }
        return hexString.toString();
    }
}
