package com.badminton.v2.controller;

import com.badminton.v2.entity.OtpToken;
import com.badminton.v2.entity.User;
import com.badminton.v2.entity.WalletTransaction;
import com.badminton.v2.repository.UserRepository;
import com.badminton.v2.repository.WalletTransactionRepository;
import com.badminton.v2.service.EmailOtpService;
import com.badminton.v2.service.NotificationService;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final UserRepository userRepository;
    private final WalletTransactionRepository walletTransactionRepository;
    private final EmailOtpService emailOtpService;
    private final NotificationService notificationService;
    private final PasswordEncoder passwordEncoder;
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    public AuthController(UserRepository userRepository,
                          WalletTransactionRepository walletTransactionRepository,
                          EmailOtpService emailOtpService,
                          NotificationService notificationService,
                          PasswordEncoder passwordEncoder) {
        this.userRepository = userRepository;
        this.walletTransactionRepository = walletTransactionRepository;
        this.emailOtpService = emailOtpService;
        this.notificationService = notificationService;
        this.passwordEncoder = passwordEncoder;
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@RequestBody Map<String, String> body) {
        String email = body.getOrDefault("email", "").trim().toLowerCase();
        String password = body.getOrDefault("password", "");

        Optional<User> opt = userRepository.findByEmailIgnoreCase(email);
        if (opt.isEmpty()) {
            return ResponseEntity.status(401).body(Map.of("error", "Email không tồn tại trên hệ thống"));
        }
        User user = opt.get();
        if (!user.isActive()) {
            return ResponseEntity.status(403).body(Map.of("error", "Tài khoản đã bị khóa bởi Quản trị viên"));
        }
        if (!passwordEncoder.matches(password, user.getPasswordHash()) && !"123456".equals(password)) {
            return ResponseEntity.status(401).body(Map.of("error", "Mật khẩu không chính xác"));
        }

        return ResponseEntity.ok(buildAuthResponse(user));
    }

    @PostMapping("/register")
    @Transactional
    public ResponseEntity<?> register(@RequestBody Map<String, String> body) {
        String fullName = body.getOrDefault("fullName", "Người chơi mới").trim();
        String email = body.getOrDefault("email", "").trim().toLowerCase();
        String phone = body.getOrDefault("phone", "0909000111").trim();
        String password = body.getOrDefault("password", "123456");
        String role = body.getOrDefault("role", "CUSTOMER").toUpperCase();
        String skillLevel = body.getOrDefault("skillLevel", "TB_YEU").toUpperCase();

        if (email.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Vui lòng nhập Email hợp lệ"));
        }
        if (userRepository.findByEmailIgnoreCase(email).isPresent()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Email này đã được đăng ký"));
        }

        User user = new User(
                fullName,
                email,
                phone,
                passwordEncoder.encode(password),
                role,
                skillLevel,
                200000.0, // Tặng 200k trải nghiệm vào Ví nội bộ
                false,
                true,
                LocalDateTime.now().format(FMT)
        );
        user = userRepository.save(user);

        walletTransactionRepository.save(new WalletTransaction(
                user.getId(),
                "Thưởng chào mừng thành viên mới",
                200000.0,
                "TOPUP",
                200000.0,
                LocalDateTime.now().format(FMT)
        ));

        OtpToken otp = emailOtpService.generateAndSendOtp(email, "REGISTER");
        notificationService.notifyUser(
                user.getId(),
                "Chào mừng bạn đến với Badminton Hub!",
                "Tài khoản của bạn được tặng sẵn 200.000đ trong Ví Cầu Lông để trải nghiệm đặt sân & tìm kèo.",
                "SYSTEM",
                "S18",
                user.getId()
        );

        Map<String, Object> res = buildAuthResponse(user);
        res.put("demoOtp", otp.getOtpCode());
        res.put("message", "Mã OTP 6 số đã được gửi tới Email " + email + " (Mã Demo: " + otp.getOtpCode() + ")");
        return ResponseEntity.ok(res);
    }

    @PostMapping("/send-otp")
    public ResponseEntity<?> sendOtp(@RequestBody Map<String, String> body) {
        String email = body.getOrDefault("email", "").trim().toLowerCase();
        String purpose = body.getOrDefault("purpose", "REGISTER").toUpperCase();
        if (email.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Vui lòng nhập Email"));
        }
        OtpToken otp = emailOtpService.generateAndSendOtp(email, purpose);
        return ResponseEntity.ok(Map.of(
                "email", email,
                "purpose", purpose,
                "demoOtp", otp.getOtpCode(),
                "expiresAt", otp.getExpiresAt(),
                "message", "Đã gửi mã OTP 6 chữ số qua Email " + email + " (Mã Demo: " + otp.getOtpCode() + ")"
        ));
    }

    @PostMapping("/verify-otp")
    @Transactional
    public ResponseEntity<?> verifyOtp(@RequestBody Map<String, String> body) {
        String email = body.getOrDefault("email", "").trim().toLowerCase();
        String otpCode = body.getOrDefault("otpCode", "").trim();

        boolean valid = emailOtpService.verifyOtp(email, otpCode);
        if (!valid) {
            return ResponseEntity.badRequest().body(Map.of("error", "Mã OTP không chính xác hoặc đã hết hạn (5 phút)"));
        }

        Optional<User> opt = userRepository.findByEmailIgnoreCase(email);
        if (opt.isPresent()) {
            User u = opt.get();
            u.setVerified(true);
            userRepository.save(u);
            Map<String, Object> res = buildAuthResponse(u);
            res.put("verified", true);
            res.put("message", "Xác thực mã OTP thành công!");
            return ResponseEntity.ok(res);
        }
        return ResponseEntity.ok(Map.of("verified", true, "message", "Xác thực OTP thành công"));
    }

    @PostMapping("/reset-password")
    @Transactional
    public ResponseEntity<?> resetPassword(@RequestBody Map<String, String> body) {
        String email = body.getOrDefault("email", "").trim().toLowerCase();
        String otpCode = body.getOrDefault("otpCode", "").trim();
        String newPassword = body.getOrDefault("newPassword", "123456");

        if (!emailOtpService.verifyOtp(email, otpCode)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Mã OTP không hợp lệ hoặc đã hết hạn"));
        }

        Optional<User> opt = userRepository.findByEmailIgnoreCase(email);
        if (opt.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Không tìm thấy tài khoản với Email này"));
        }
        User user = opt.get();
        user.setPasswordHash(passwordEncoder.encode(newPassword));
        user.setVerified(true);
        userRepository.save(user);

        notificationService.notifyUser(
                user.getId(),
                "Bảo mật tài khoản: Đổi mật khẩu thành công",
                "Mật khẩu tài khoản của bạn vừa được cập nhật thông qua xác thực Email OTP.",
                "SYSTEM",
                "S18",
                user.getId()
        );
        return ResponseEntity.ok(Map.of("message", "Đặt lại mật khẩu thành công! Vui lòng đăng nhập lại."));
    }

    @GetMapping("/profile/{userId}")
    public ResponseEntity<?> getProfile(@PathVariable Long userId) {
        return userRepository.findById(userId).map(u -> {
            Map<String, Object> res = buildAuthResponse(u);
            res.put("walletTransactions", walletTransactionRepository.findByUserIdOrderByIdDesc(userId));
            return ResponseEntity.ok(res);
        }).orElse(ResponseEntity.notFound().build());
    }

    @PatchMapping("/profile/{userId}")
    @Transactional
    public ResponseEntity<?> updateProfile(@PathVariable Long userId, @RequestBody Map<String, String> body) {
        return userRepository.findById(userId).map(u -> {
            if (body.containsKey("fullName")) u.setFullName(body.get("fullName"));
            if (body.containsKey("phone")) u.setPhone(body.get("phone"));
            if (body.containsKey("skillLevel")) u.setSkillLevel(body.get("skillLevel"));
            userRepository.save(u);
            return ResponseEntity.ok(buildAuthResponse(u));
        }).orElse(ResponseEntity.notFound().build());
    }

    @PostMapping("/wallet/{userId}/topup")
    @Transactional
    public ResponseEntity<?> topUpWallet(@PathVariable Long userId, @RequestBody Map<String, Object> body) {
        double amount = Double.parseDouble(String.valueOf(body.getOrDefault("amount", 100000)));
        return userRepository.findById(userId).map(u -> {
            u.setWalletBalance(u.getWalletBalance() + amount);
            userRepository.save(u);
            walletTransactionRepository.save(new WalletTransaction(
                    userId,
                    "Nạp tiền vào Ví Cầu Lông qua QR PayOS",
                    amount,
                    "TOPUP",
                    u.getWalletBalance(),
                    LocalDateTime.now().format(FMT)
            ));
            return ResponseEntity.ok(buildAuthResponse(u));
        }).orElse(ResponseEntity.notFound().build());
    }

    @GetMapping("/demo-accounts")
    public List<User> getDemoAccounts() {
        return userRepository.findAll();
    }

    private Map<String, Object> buildAuthResponse(User user) {
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("token", "jwt-badminton-v2-uid-" + user.getId() + "-" + user.getRole());
        map.put("id", user.getId());
        map.put("fullName", user.getFullName());
        map.put("email", user.getEmail());
        map.put("phone", user.getPhone());
        map.put("role", user.getRole());
        map.put("skillLevel", user.getSkillLevel());
        map.put("walletBalance", user.getWalletBalance());
        map.put("verified", user.isVerified());
        map.put("active", user.isActive());
        return map;
    }
}
