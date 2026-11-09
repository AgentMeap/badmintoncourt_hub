package com.badminton.v2.controller;

import com.badminton.v2.entity.User;
import com.badminton.v2.entity.WalletTransaction;
import com.badminton.v2.repository.UserRepository;
import com.badminton.v2.repository.WalletTransactionRepository;
import com.badminton.v2.service.NotificationService;
import com.badminton.v2.service.EmailOtpService;
import com.badminton.v2.security.CurrentUser;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/api/wallet")
public class WalletWithdrawController {

    private final UserRepository userRepository;
    private final WalletTransactionRepository walletTransactionRepository;
    private final NotificationService notificationService;
    private final EmailOtpService emailOtpService;
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    public WalletWithdrawController(UserRepository userRepository,
                                    WalletTransactionRepository walletTransactionRepository,
                                    NotificationService notificationService,
                                    EmailOtpService emailOtpService) {
        this.userRepository = userRepository;
        this.walletTransactionRepository = walletTransactionRepository;
        this.notificationService = notificationService;
        this.emailOtpService = emailOtpService;
    }

    @PostMapping("/withdraw")
    @Transactional
    public ResponseEntity<?> withdrawFromWallet(@RequestBody Map<String, Object> body) {
        Long userId = CurrentUser.idOr(body.get("userId"));
        String otpCode = String.valueOf(body.getOrDefault("otpCode", "")).trim();
        double amount = Double.parseDouble(String.valueOf(body.get("amount")));
        String bankName = String.valueOf(body.getOrDefault("bankName", "Ngân hàng"));
        String bankAccountNumber = String.valueOf(body.getOrDefault("bankAccountNumber", ""));
        String bankAccountHolder = String.valueOf(body.getOrDefault("bankAccountHolder", ""));

        if (amount <= 0) {
            return ResponseEntity.badRequest().body(Map.of("error", "Số tiền rút phải lớn hơn 0!"));
        }

        Optional<User> opt = userRepository.findById(userId);
        if (opt.isEmpty()) return ResponseEntity.notFound().build();
        User user = opt.get();
        // Xác thực OTP gửi tới email của chính tài khoản (mục đích WITHDRAW_WALLET)
        if (!emailOtpService.verifyOtp(user.getEmail(), otpCode, "WITHDRAW_WALLET")) {
            return ResponseEntity.badRequest().body(Map.of("error", "Mã OTP không chính xác hoặc đã hết hạn."));
        }

        if (user.getWalletBalance() < amount) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "Số dư Ví Cầu Lông không đủ (" + (long) user.getWalletBalance() + "đ < " + (long) amount + "đ)!"
            ));
        }

        user.setWalletBalance(user.getWalletBalance() - amount);
        userRepository.save(user);

        String title = "Rút về " + bankName + " • " + bankAccountNumber;
        WalletTransaction tx = new WalletTransaction(
                userId,
                title,
                -amount,
                "WITHDRAW",
                user.getWalletBalance(),
                LocalDateTime.now().format(FMT)
        );
        walletTransactionRepository.save(tx);

        notificationService.notifyUser(
                userId,
                "Yêu cầu rút tiền " + (long) amount + "đ thành công",
                "Tiền sẽ được chuyển về " + bankName + " (" + bankAccountNumber + ") trong 1-2 ngày làm việc.",
                "PAYMENT",
                "S18",
                userId
        );

        return ResponseEntity.ok(Map.of(
                "success", true,
                "message", "Tạo yêu cầu rút tiền thành công!",
                "walletBalance", user.getWalletBalance(),
                "transaction", tx
        ));
    }
}
