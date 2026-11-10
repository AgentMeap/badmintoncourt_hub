package com.badminton.v2.controller;

import com.badminton.v2.entity.Payment;
import com.badminton.v2.repository.PaymentRepository;
import com.badminton.v2.security.CurrentUser;
import com.badminton.v2.service.WalletTopupService;
import com.badminton.v2.service.WalletTopupService.TopupException;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/** Nạp tiền vào Ví Cầu Lông qua PayOS VietQR. */
@RestController
@RequestMapping("/api/wallet/topup")
public class WalletTopupController {

    private final WalletTopupService topupService;
    private final PaymentRepository paymentRepository;

    public WalletTopupController(WalletTopupService topupService, PaymentRepository paymentRepository) {
        this.topupService = topupService;
        this.paymentRepository = paymentRepository;
    }

    /** Tạo đơn nạp: { amount } -> mã QR + link thanh toán PayOS. */
    @PostMapping("/payos")
    public ResponseEntity<?> create(@RequestBody Map<String, Object> body) {
        Long userId = CurrentUser.idOr(body.get("userId"));
        CurrentUser.requireSelfOrAdmin(userId);
        double amount;
        try {
            amount = Double.parseDouble(String.valueOf(body.get("amount")));
        } catch (NumberFormatException e) {
            return ResponseEntity.badRequest().body(Map.of("error", "Số tiền nạp không hợp lệ."));
        }
        try {
            return ResponseEntity.ok(topupService.view(topupService.create(userId, amount)));
        } catch (TopupException e) {
            return ResponseEntity.status(e.getStatus()).body(Map.of("error", e.getMessage()));
        }
    }

    /** App hỏi định kỳ: backend hỏi lại PayOS, đã thanh toán thì cộng ví. */
    @GetMapping("/{orderCode}")
    public ResponseEntity<?> status(@PathVariable Long orderCode) {
        Payment p = find(orderCode);
        if (p == null) return notFound(orderCode);
        return ResponseEntity.ok(topupService.view(topupService.sync(p)));
    }

    /** Nút "giả lập đã thanh toán" khi demo. */
    @PostMapping("/{orderCode}/simulate")
    public ResponseEntity<?> simulate(@PathVariable Long orderCode) {
        Payment p = find(orderCode);
        if (p == null) return notFound(orderCode);
        try {
            return ResponseEntity.ok(topupService.view(topupService.simulatePaid(p)));
        } catch (TopupException e) {
            return ResponseEntity.status(e.getStatus()).body(Map.of("error", e.getMessage()));
        }
    }

    /** Kiểm tra lại các đơn nạp còn chờ của tôi (gọi khi mở màn Ví). */
    @PostMapping("/sync")
    public ResponseEntity<?> syncMine(@RequestBody(required = false) Map<String, Object> body) {
        Long userId = CurrentUser.idOr(body == null ? null : body.get("userId"));
        CurrentUser.requireSelfOrAdmin(userId);
        return ResponseEntity.ok(Map.of("credited", topupService.syncPending(userId)));
    }

    private Payment find(Long orderCode) {
        Payment p = paymentRepository.findByPayosOrderCode(orderCode).orElse(null);
        if (!WalletTopupService.isTopup(p)) return null;
        CurrentUser.requireSelfOrAdmin(p.getUserId());
        return p;
    }

    private ResponseEntity<?> notFound(Long orderCode) {
        return ResponseEntity.status(404).body(Map.of("error", "Không tìm thấy đơn nạp " + orderCode));
    }
}
