package com.badminton.v2.service;

import com.badminton.v2.entity.Payment;
import com.badminton.v2.entity.User;
import com.badminton.v2.entity.WalletTransaction;
import com.badminton.v2.repository.PaymentRepository;
import com.badminton.v2.repository.UserRepository;
import com.badminton.v2.repository.WalletTransactionRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.client.RestClient;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Nạp tiền vào Ví Cầu Lông qua PayOS (VietQR).
 *
 * Tiền chỉ được cộng khi PayOS xác nhận đơn đã thanh toán: backend tự hỏi PayOS
 * (GET /v2/payment-requests/{orderCode}) khi app kiểm tra trạng thái hoặc khi webhook tới,
 * nên chạy ở localhost (không nhận được webhook) vẫn hoạt động.
 * Mỗi đơn chỉ cộng tiền một lần (đổi PENDING -> PAID bằng một câu UPDATE có điều kiện).
 *
 * Khi chưa cấu hình key PayOS và đang ở chế độ demo: tạo mã QR giả và cho phép nút "giả lập đã thanh toán".
 */
@Service
public class WalletTopupService {

    private static final Logger log = LoggerFactory.getLogger(WalletTopupService.class);
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static final String PAYOS_API = "https://api-merchant.payos.vn/v2/payment-requests";

    public static final String PURPOSE = "TOPUP";
    public static final double MIN_AMOUNT = 10_000;
    public static final double MAX_AMOUNT = 10_000_000;
    /** Link thanh toán PayOS hết hạn sau 15 phút. */
    public static final int EXPIRE_MINUTES = 15;

    private final PaymentRepository paymentRepository;
    private final UserRepository userRepository;
    private final WalletTransactionRepository walletTransactionRepository;
    private final NotificationService notificationService;
    private final EmailOtpService emailOtpService;
    private final RestClient restClient;

    @Value("${app.payos.client-id:}")
    private String clientId;
    @Value("${app.payos.api-key:}")
    private String apiKey;
    @Value("${app.payos.checksum-key:}")
    private String checksumKey;
    @Value("${app.payos.return-url:https://badminton-v2.demo/payment/success}")
    private String returnUrl;
    @Value("${app.payos.cancel-url:https://badminton-v2.demo/payment/cancel}")
    private String cancelUrl;

    public WalletTopupService(PaymentRepository paymentRepository,
                              UserRepository userRepository,
                              WalletTransactionRepository walletTransactionRepository,
                              NotificationService notificationService,
                              EmailOtpService emailOtpService,
                              RestClient restClient) {
        this.paymentRepository = paymentRepository;
        this.userRepository = userRepository;
        this.walletTransactionRepository = walletTransactionRepository;
        this.notificationService = notificationService;
        this.emailOtpService = emailOtpService;
        this.restClient = restClient;
    }

    /** Lỗi nghiệp vụ trả về cho app (status HTTP + câu báo lỗi tiếng Việt). */
    public static class TopupException extends RuntimeException {
        private final int status;
        public TopupException(int status, String message) {
            super(message);
            this.status = status;
        }
        public int getStatus() { return status; }
    }

    public static boolean isTopup(Payment p) {
        return p != null && PURPOSE.equals(p.getPurpose());
    }

    public boolean payosEnabled() {
        return notBlank(clientId) && notBlank(apiKey) && notBlank(checksumKey);
    }

    /** Cho phép nút "giả lập đã thanh toán" (chỉ khi demo). */
    public boolean simulateAllowed() {
        return emailOtpService.isDemoMode();
    }

    @Transactional
    public Payment create(Long userId, double amount) {
        if (amount < MIN_AMOUNT || amount > MAX_AMOUNT) {
            throw new TopupException(400, "Số tiền nạp phải từ 10.000đ đến 10.000.000đ.");
        }
        if (amount != Math.floor(amount)) {
            throw new TopupException(400, "Số tiền nạp phải là số nguyên (đồng).");
        }
        userRepository.findById(userId).orElseThrow(() -> new TopupException(404, "Không tìm thấy tài khoản."));
        if (!payosEnabled() && !emailOtpService.isDemoMode()) {
            throw new TopupException(503, "Cổng thanh toán PayOS chưa được cấu hình. Vui lòng thử lại sau.");
        }

        long orderCode = newOrderCode();
        int amountInt = (int) amount;
        // Mô tả ngắn (ngân hàng không liên kết PayOS chỉ nhận tối đa 9 ký tự)
        String description = "NAPVI" + userId;
        if (description.length() > 9) description = description.substring(0, 9);

        String qrData;
        String checkoutUrl;
        if (payosEnabled()) {
            Map<String, Object> data = requestPayos(orderCode, amountInt, description);
            qrData = String.valueOf(data.get("qrCode"));
            checkoutUrl = String.valueOf(data.get("checkoutUrl"));
        } else {
            qrData = "00020101021238570010A00000072701270006970436011300710012345670208QRIBFTTA5303704540"
                    + String.valueOf(amountInt).length() + amountInt + "5802VN6213" + description + "6304DEMO";
            checkoutUrl = "https://pay.payos.vn/web/demo-" + orderCode;
        }

        Payment payment = new Payment();
        payment.setPurpose(PURPOSE);
        payment.setUserId(userId);
        payment.setPayosOrderCode(orderCode);
        payment.setPaymentMethod("PAYOS_QR");
        payment.setAmount(amount);
        payment.setStatus("PENDING");
        payment.setCheckoutUrl(checkoutUrl);
        payment.setQrCodeData(qrData);
        payment.setCreatedAt(LocalDateTime.now().format(FMT));
        return paymentRepository.save(payment);
    }

    /**
     * Hỏi PayOS trạng thái đơn đang chờ: đã thanh toán đủ -> cộng ví; đã hủy / hết hạn -> CANCELLED.
     * Không tin dữ liệu trong webhook, luôn hỏi lại PayOS bằng key của mình.
     */
    @Transactional
    public Payment sync(Payment payment) {
        if (!isTopup(payment) || !"PENDING".equals(payment.getStatus()) || !payosEnabled()) {
            return payment;
        }
        Map<String, Object> data;
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> resp = restClient.get()
                    .uri(PAYOS_API + "/" + payment.getPayosOrderCode())
                    .header("x-client-id", clientId)
                    .header("x-api-key", apiKey)
                    .retrieve()
                    .body(Map.class);
            if (resp == null || !(resp.get("data") instanceof Map<?, ?>)) return payment;
            @SuppressWarnings("unchecked")
            Map<String, Object> d = (Map<String, Object>) resp.get("data");
            data = d;
        } catch (Exception e) {
            log.warn("Không hỏi được trạng thái PayOS đơn {}: {}", payment.getPayosOrderCode(), e.getMessage());
            return payment;
        }
        String status = String.valueOf(data.get("status"));
        double amountPaid = toDouble(data.get("amountPaid"));
        if ("PAID".equals(status) && amountPaid + 0.5 >= payment.getAmount()) {
            credit(payment, "Nạp tiền qua PayOS");
        } else if ("CANCELLED".equals(status) || "EXPIRED".equals(status) || "FAILED".equals(status)) {
            paymentRepository.markCancelled(payment.getId());
        }
        return reload(payment);
    }

    /** Nút giả lập (demo): coi như đơn đã thanh toán. */
    @Transactional
    public Payment simulatePaid(Payment payment) {
        if (!simulateAllowed()) {
            throw new TopupException(403, "Chỉ giả lập thanh toán ở chế độ demo.");
        }
        if (!"PENDING".equals(payment.getStatus())) return payment;
        credit(payment, "Nạp tiền qua PayOS (demo)");
        return reload(payment);
    }

    /** Kiểm tra lại các đơn nạp đang chờ trong 24 giờ qua (khách đã chuyển khoản nhưng đóng app sớm). */
    @Transactional
    public int syncPending(Long userId) {
        if (!payosEnabled()) return 0;
        String since = LocalDateTime.now().minusHours(24).format(FMT);
        int credited = 0;
        List<Payment> pending = paymentRepository.findByUserIdAndPurposeAndStatusOrderByIdDesc(userId, PURPOSE, "PENDING");
        for (Payment p : pending) {
            if (p.getCreatedAt() != null && p.getCreatedAt().compareTo(since) < 0) continue;
            if ("PAID".equals(sync(p).getStatus())) credited++;
        }
        return credited;
    }

    public Map<String, Object> view(Payment p) {
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("orderCode", p.getPayosOrderCode());
        res.put("amount", p.getAmount());
        res.put("status", p.getStatus());
        res.put("paid", "PAID".equals(p.getStatus()));
        res.put("checkoutUrl", p.getCheckoutUrl());
        res.put("qrCodeData", p.getQrCodeData());
        res.put("createdAt", p.getCreatedAt());
        res.put("paidAt", p.getPaidAt());
        res.put("expireMinutes", EXPIRE_MINUTES);
        res.put("live", payosEnabled());
        res.put("canSimulate", simulateAllowed() && "PENDING".equals(p.getStatus()));
        userRepository.findById(p.getUserId()).ifPresent(u -> res.put("walletBalance", u.getWalletBalance()));
        return res;
    }

    // ------------------------------------------------------------------ nội bộ

    /** Cộng tiền đúng một lần: chỉ đơn còn PENDING mới đổi được sang PAID. */
    private void credit(Payment payment, String title) {
        String now = LocalDateTime.now().format(FMT);
        if (paymentRepository.markPaid(payment.getId(), now) != 1) return;
        User u = userRepository.findById(payment.getUserId()).orElseThrow();
        u.setWalletBalance(u.getWalletBalance() + payment.getAmount());
        userRepository.save(u);
        walletTransactionRepository.save(new WalletTransaction(
                u.getId(), title, payment.getAmount(), "TOPUP", u.getWalletBalance(), now));
        notificationService.notifyUser(
                u.getId(),
                "Nạp tiền thành công",
                "Ví Cầu Lông đã được cộng " + money(payment.getAmount()) + ". Số dư mới: " + money(u.getWalletBalance()) + ".",
                "WALLET",
                "S18",
                payment.getId());
    }

    private Payment reload(Payment p) {
        return paymentRepository.findById(p.getId()).orElse(p);
    }

    private Map<String, Object> requestPayos(long orderCode, int amount, String description) {
        long expiredAt = System.currentTimeMillis() / 1000 + EXPIRE_MINUTES * 60L;
        try {
            String dataToSign = "amount=" + amount
                    + "&cancelUrl=" + cancelUrl
                    + "&description=" + description
                    + "&orderCode=" + orderCode
                    + "&returnUrl=" + returnUrl;
            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("orderCode", orderCode);
            payload.put("amount", amount);
            payload.put("description", description);
            payload.put("cancelUrl", cancelUrl);
            payload.put("returnUrl", returnUrl);
            payload.put("expiredAt", expiredAt);
            payload.put("signature", hmacSha256(dataToSign, checksumKey));
            @SuppressWarnings("unchecked")
            Map<String, Object> resp = restClient.post()
                    .uri(PAYOS_API)
                    .header("x-client-id", clientId)
                    .header("x-api-key", apiKey)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(payload)
                    .retrieve()
                    .body(Map.class);
            if (resp != null && "00".equals(String.valueOf(resp.get("code")))
                    && resp.get("data") instanceof Map<?, ?> d && d.get("qrCode") != null) {
                @SuppressWarnings("unchecked")
                Map<String, Object> data = (Map<String, Object>) d;
                return data;
            }
            log.warn("PayOS từ chối tạo đơn nạp {}: {}", orderCode, resp);
        } catch (Exception e) {
            log.warn("Không gọi được PayOS khi tạo đơn nạp {}: {}", orderCode, e.getMessage());
        }
        throw new TopupException(502, "Không tạo được mã thanh toán PayOS. Vui lòng thử lại.");
    }

    private long newOrderCode() {
        long code = System.currentTimeMillis();
        while (paymentRepository.findByPayosOrderCode(code).isPresent()) code++;
        return code;
    }

    private static String hmacSha256(String data, String key) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(key.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        StringBuilder hex = new StringBuilder();
        for (byte b : mac.doFinal(data.getBytes(StandardCharsets.UTF_8))) hex.append(String.format("%02x", b));
        return hex.toString();
    }

    private static double toDouble(Object o) {
        if (o instanceof Number n) return n.doubleValue();
        try { return o == null ? 0 : Double.parseDouble(String.valueOf(o)); } catch (NumberFormatException e) { return 0; }
    }

    private static boolean notBlank(String s) {
        return s != null && !s.isBlank();
    }

    private static String money(double v) {
        return String.format("%,.0fđ", v).replace(',', '.');
    }
}
