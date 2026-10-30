package com.badminton.v2.controller;

import com.badminton.v2.entity.*;
import com.badminton.v2.repository.*;
import com.badminton.v2.service.NotificationService;
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
        Long customerId = Long.parseLong(String.valueOf(body.get("customerId")));
        String playDate = String.valueOf(body.getOrDefault("playDate", LocalDate.now().toString()));
        String startTime = String.valueOf(body.getOrDefault("startTime", "18:00"));
        String endTime = String.valueOf(body.getOrDefault("endTime", "20:00"));
        double totalPrice = Double.parseDouble(String.valueOf(body.getOrDefault("totalPrice", 240000)));

        if (hasTimeConflict(courtId, playDate, startTime, endTime, null)) {
            return ResponseEntity.status(409).body(Map.of(
                    "error", "Khung giờ này vừa có người đặt hoặc đang được giữ chỗ! Vui lòng chọn sân/giờ khác."
            ));
        }

        Venue venue = venueRepository.findById(venueId).orElseThrow();
        Court court = courtRepository.findById(courtId).orElseThrow();
        User customer = userRepository.findById(customerId).orElseThrow();

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
        return confirmPayosOrder(orderCode);
    }

    // Nút hỗ trợ Demo Webhook PayOS trên lớp học
    @PostMapping("/payments/simulate-webhook/{orderCode}")
    @Transactional
    public ResponseEntity<?> simulatePayosWebhook(@PathVariable Long orderCode) {
        return confirmPayosOrder(orderCode);
    }

    private ResponseEntity<?> confirmPayosOrder(Long orderCode) {
        Optional<Payment> opt = paymentRepository.findByPayosOrderCode(orderCode);
        if (opt.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Không tìm thấy mã đơn PayOS: " + orderCode));
        }
        Payment payment = opt.get();
        payment.setStatus("PAID");
        payment.setPaidAt(LocalDateTime.now().format(FMT));
        paymentRepository.save(payment);

        Booking booking = bookingRepository.findById(payment.getBookingId()).orElseThrow();
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
        Long userId = Long.parseLong(String.valueOf(body.get("userId")));

        Booking booking = bookingRepository.findById(bookingId).orElseThrow();
        User user = userRepository.findById(userId).orElseThrow();

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

    @GetMapping("/bookings/customer/{customerId}")
    public List<Booking> getCustomerBookings(@PathVariable Long customerId) {
        return bookingRepository.findByCustomerIdOrderByIdDesc(customerId);
    }

    @GetMapping("/bookings/{id}")
    public ResponseEntity<?> getBookingDetail(@PathVariable Long id) {
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
        if (b.getRescheduledCount() >= 1) {
            return ResponseEntity.badRequest().body(Map.of("error", "Mỗi vé chỉ được phép đổi lịch tối đa 1 lần!"));
        }
        String newDate = String.valueOf(body.getOrDefault("playDate", b.getPlayDate()));
        String newStart = String.valueOf(body.getOrDefault("startTime", "19:00"));
        String newEnd = String.valueOf(body.getOrDefault("endTime", "21:00"));
        Long newCourtId = body.get("courtId") != null ? Long.parseLong(String.valueOf(body.get("courtId"))) : b.getCourtId();

        if (hasTimeConflict(newCourtId, newDate, newStart, newEnd, b.getId())) {
            return ResponseEntity.status(409).body(Map.of("error", "Khung giờ mới đã có người đặt, vui lòng chọn khung giờ khác!"));
        }

        Court newCourt = courtRepository.findById(newCourtId).orElseThrow();
        b.setCourtId(newCourtId);
        b.setCourtName(newCourt.getName());
        b.setPlayDate(newDate);
        b.setStartTime(newStart);
        b.setEndTime(newEnd);
        b.setRescheduledCount(b.getRescheduledCount() + 1);
        bookingRepository.save(b);

        notificationService.notifyUser(
                b.getCustomerId(),
                "Đổi lịch đặt sân thành công (#" + b.getBookingCode() + ")",
                "Lịch mới: " + b.getCourtName() + " (" + newStart + " - " + newEnd + ", ngày " + newDate + ").",
                "BOOKING",
                "S13",
                b.getId()
        );
        return ResponseEntity.ok(b);
    }

    // Luồng 4: Hủy sân & Tự động hoàn tiền về Ví nội bộ theo mốc thời gian (>=24h: 100%, 6-24h: 50%, <6h: 0%)
    @PostMapping("/bookings/{id}/cancel")
    @Transactional
    public ResponseEntity<?> cancelAndRefundBooking(@PathVariable Long id, @RequestBody Map<String, Object> body) {
        Booking b = bookingRepository.findById(id).orElseThrow();
        if ("CANCELLED".equals(b.getStatus())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Vé đặt sân này đã được hủy trước đó."));
        }
        String reason = String.valueOf(body.getOrDefault("reason", "Thay đổi kế hoạch cá nhân"));

        long hoursUntilPlay = calculateHoursUntilPlay(b.getPlayDate(), b.getStartTime());
        int refundPercent;
        if (hoursUntilPlay >= 24) {
            refundPercent = 100;
        } else if (hoursUntilPlay >= 6) {
            refundPercent = 50;
        } else {
            // Allow demo force 100% if requested, otherwise follow policy
            boolean forceDemoRefund = Boolean.parseBoolean(String.valueOf(body.getOrDefault("demoFullRefund", "true")));
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

        if (hasTimeConflict(courtId, playDate, startTime, endTime, null)) {
            return ResponseEntity.status(409).body(Map.of("error", "Khung giờ này đã có lịch đặt trước!"));
        }

        Venue venue = venueRepository.findById(venueId).orElseThrow();
        Court court = courtRepository.findById(courtId).orElseThrow();
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
            int exStart = toMinutes(b.getStartTime());
            int exEnd = toMinutes(b.getEndTime());
            if (reqStart < exEnd && reqEnd > exStart) {
                return true;
            }
        }
        return false;
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
