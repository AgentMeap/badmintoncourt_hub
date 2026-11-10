package com.badminton.v2.controller;

import com.badminton.v2.entity.OtpToken;
import com.badminton.v2.entity.User;
import com.badminton.v2.entity.WalletTransaction;
import com.badminton.v2.repository.UserRepository;
import com.badminton.v2.repository.WalletTransactionRepository;
import com.badminton.v2.service.EmailOtpService;
import com.badminton.v2.service.NotificationService;
import com.badminton.v2.security.AuthUser;
import com.badminton.v2.security.CurrentUser;
import com.badminton.v2.security.FirebaseTokenVerifier;
import com.badminton.v2.security.JwtService;
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
    private final JwtService jwtService;
    private final FirebaseTokenVerifier firebaseTokenVerifier;
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    public AuthController(UserRepository userRepository,
                          WalletTransactionRepository walletTransactionRepository,
                          EmailOtpService emailOtpService,
                          NotificationService notificationService,
                          PasswordEncoder passwordEncoder,
                          JwtService jwtService,
                          FirebaseTokenVerifier firebaseTokenVerifier) {
        this.userRepository = userRepository;
        this.walletTransactionRepository = walletTransactionRepository;
        this.emailOtpService = emailOtpService;
        this.notificationService = notificationService;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
        this.firebaseTokenVerifier = firebaseTokenVerifier;
    }

    /** Mục đích OTP cần đăng nhập: mã luôn gửi tới email của chính tài khoản. */
    private static final Set<String> ACCOUNT_OTP_PURPOSES = Set.of("WITHDRAW_WALLET", "PAYOUT");
    private static final Set<String> OTP_PURPOSES = Set.of("REGISTER", "RESET_PASSWORD", "WITHDRAW_WALLET", "PAYOUT");

    /** Mật khẩu demo "123456" chỉ được chấp nhận khi bật app.demo-mode. */
    private boolean isDemoPassword(String password) {
        return emailOtpService.isDemoMode() && EmailOtpService.DEMO_OTP.equals(password);
    }

    // Đăng nhập Google qua Firebase: app gửi Firebase ID token, máy chủ kiểm tra rồi cấp JWT riêng
    @PostMapping("/google")
    @Transactional
    public ResponseEntity<?> loginWithGoogle(@RequestBody Map<String, String> body) {
        if (!firebaseTokenVerifier.isConfigured()) {
            return ResponseEntity.status(503).body(Map.of(
                    "error", "Máy chủ chưa cấu hình đăng nhập Google (thiếu FIREBASE_PROJECT_ID)."));
        }
        FirebaseTokenVerifier.FirebaseUser firebaseUser;
        try {
            firebaseUser = firebaseTokenVerifier.verify(body.getOrDefault("idToken", ""));
        } catch (FirebaseTokenVerifier.InvalidTokenException e) {
            return ResponseEntity.status(401).body(Map.of(
                    "error", "Phiên đăng nhập Google không hợp lệ hoặc đã hết hạn. Vui lòng thử lại."));
        }
        if (firebaseUser.email() == null || !firebaseUser.emailVerified()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Tài khoản Google chưa có email đã xác thực."));
        }

        boolean created = false;
        User user;
        Optional<User> existing = userRepository.findByEmailIgnoreCase(firebaseUser.email());
        if (existing.isPresent()) {
            user = existing.get();
            if (!user.isActive()) {
                return ResponseEntity.status(403).body(Map.of("error", "Tài khoản đã bị khóa bởi Quản trị viên"));
            }
            boolean changed = false;
            if (!user.isVerified()) {
                // Google đã xác thực email nên không cần OTP nữa
                user.setVerified(true);
                changed = true;
            }
            if (firebaseUser.picture() != null && !firebaseUser.picture().equals(user.getAvatarUrl())) {
                user.setAvatarUrl(firebaseUser.picture());
                changed = true;
            }
            if (changed) user = userRepository.save(user);
        } else {
            String name = firebaseUser.name() != null && !firebaseUser.name().isBlank()
                    ? firebaseUser.name()
                    : firebaseUser.email().split("@")[0];
            user = userRepository.save(new User(
                    name,
                    firebaseUser.email(),
                    "",
                    // Tài khoản Google không có mật khẩu đăng nhập; đặt chuỗi ngẫu nhiên không đoán được
                    passwordEncoder.encode(UUID.randomUUID().toString()),
                    "CUSTOMER",
                    "TB_YEU",
                    200000.0,
                    true,
                    true,
                    LocalDateTime.now().format(FMT)
            ));
            user.setAvatarUrl(firebaseUser.picture());
            user.setLocalPassword(false);
            user = userRepository.save(user);
            walletTransactionRepository.save(new WalletTransaction(
                    user.getId(),
                    "Thưởng chào mừng thành viên mới",
                    200000.0,
                    "TOPUP",
                    200000.0,
                    LocalDateTime.now().format(FMT)
            ));
            notificationService.notifyUser(
                    user.getId(),
                    "Chào mừng bạn đến với Badminton Hub!",
                    "Bạn đã đăng nhập bằng Google. Ví Cầu Lông được tặng sẵn 200.000đ để trải nghiệm đặt sân & tìm kèo.",
                    "SYSTEM",
                    "S18",
                    user.getId()
            );
            created = true;
        }

        Map<String, Object> res = buildAuthResponse(user);
        res.put("newUser", created);
        return ResponseEntity.ok(res);
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
        if (!passwordEncoder.matches(password, user.getPasswordHash()) && !isDemoPassword(password)) {
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
        // Chỉ tự đăng ký được Người chơi hoặc Chủ sân; tài khoản Admin không tạo qua API công khai
        if (!List.of("CUSTOMER", "COURT_OWNER").contains(role)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Vai trò đăng ký không hợp lệ."));
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

        // Chưa xác thực email nên KHÔNG trả token đăng nhập; token cấp sau bước verify-otp
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("id", user.getId());
        res.put("email", user.getEmail());
        res.put("verified", false);
        res.put("message", "Mã OTP 6 số đã được gửi tới Email " + email);
        if (emailOtpService.isDemoMode()) res.put("demoOtp", otp.getOtpCode());
        return ResponseEntity.ok(res);
    }

    @PostMapping("/send-otp")
    public ResponseEntity<?> sendOtp(@RequestBody Map<String, String> body) {
        String email = body.getOrDefault("email", "").trim().toLowerCase();
        String purpose = body.getOrDefault("purpose", "REGISTER").trim().toUpperCase();
        if (!OTP_PURPOSES.contains(purpose)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Mục đích OTP không hợp lệ"));
        }
        if (ACCOUNT_OTP_PURPOSES.contains(purpose)) {
            // Rút ví / giải ngân: phải đăng nhập, mã gửi tới email của chính tài khoản (bỏ qua email gửi lên)
            Optional<AuthUser> current = CurrentUser.get();
            if (current.isEmpty()) {
                return ResponseEntity.status(401).body(Map.of("error", "Vui lòng đăng nhập để nhận mã xác thực."));
            }
            email = current.get().email().trim().toLowerCase();
        }
        if (email.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Vui lòng nhập Email"));
        }
        OtpToken otp = emailOtpService.generateAndSendOtp(email, purpose);
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("email", email);
        res.put("purpose", purpose);
        res.put("expiresAt", otp.getExpiresAt());
        res.put("message", "Đã gửi mã OTP 6 chữ số qua Email " + email);
        if (emailOtpService.isDemoMode()) res.put("demoOtp", otp.getOtpCode());
        return ResponseEntity.ok(res);
    }

    @PostMapping("/verify-otp")
    @Transactional
    public ResponseEntity<?> verifyOtp(@RequestBody Map<String, String> body) {
        String email = body.getOrDefault("email", "").trim().toLowerCase();
        String otpCode = body.getOrDefault("otpCode", "").trim();

        // Endpoint này chỉ xác thực email khi đăng ký; rút ví / giải ngân / quên mật khẩu
        // tự kiểm tra OTP trong API của chúng
        boolean valid = emailOtpService.verifyOtp(email, otpCode, "REGISTER");
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
        return ResponseEntity.badRequest().body(Map.of("error", "Không tìm thấy tài khoản với Email này"));
    }

    @PostMapping("/reset-password")
    @Transactional
    public ResponseEntity<?> resetPassword(@RequestBody Map<String, String> body) {
        String email = body.getOrDefault("email", "").trim().toLowerCase();
        String otpCode = body.getOrDefault("otpCode", "").trim();
        String newPassword = body.getOrDefault("newPassword", "");
        if (newPassword.length() < 6) {
            return ResponseEntity.badRequest().body(Map.of("error", "Mật khẩu mới phải có ít nhất 6 ký tự!"));
        }

        if (!emailOtpService.verifyOtp(email, otpCode, "RESET_PASSWORD")) {
            return ResponseEntity.badRequest().body(Map.of("error", "Mã OTP không hợp lệ hoặc đã hết hạn"));
        }

        Optional<User> opt = userRepository.findByEmailIgnoreCase(email);
        if (opt.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Không tìm thấy tài khoản với Email này"));
        }
        User user = opt.get();
        user.setPasswordHash(passwordEncoder.encode(newPassword));
        user.setLocalPassword(true);
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
        CurrentUser.requireSelfOrAdmin(userId);
        return userRepository.findById(userId).map(u -> {
            Map<String, Object> res = buildAuthResponse(u);
            res.put("walletTransactions", walletTransactionRepository.findByUserIdOrderByIdDesc(userId));
            return ResponseEntity.ok(res);
        }).orElse(ResponseEntity.notFound().build());
    }

    @PatchMapping("/profile/{userId}")
    @Transactional
    public ResponseEntity<?> updateProfile(@PathVariable Long userId, @RequestBody Map<String, String> body) {
        CurrentUser.requireSelfOrAdmin(userId);
        return userRepository.findById(userId).map(u -> {
            if (body.containsKey("fullName")) u.setFullName(body.get("fullName"));
            if (body.containsKey("phone")) u.setPhone(body.get("phone"));
            if (body.containsKey("skillLevel")) u.setSkillLevel(body.get("skillLevel"));
            if (body.containsKey("introVideoUrl")) u.setIntroVideoUrl(body.get("introVideoUrl"));
            userRepository.save(u);
            return ResponseEntity.ok(buildAuthResponse(u));
        }).orElse(ResponseEntity.notFound().build());
    }

    @PostMapping("/change-password")
    @Transactional
    public ResponseEntity<?> changePassword(@RequestBody Map<String, Object> body) {
        Long userId = CurrentUser.idOr(body.get("userId"));
        String currentPassword = String.valueOf(body.getOrDefault("currentPassword", ""));
        String newPassword = String.valueOf(body.getOrDefault("newPassword", ""));

        Optional<User> opt = userRepository.findById(userId);
        if (opt.isEmpty()) return ResponseEntity.notFound().build();
        User u = opt.get();

        if (!u.hasLocalPassword()) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "Tài khoản đăng nhập bằng Google chưa có mật khẩu. Hãy dùng \"Quên mật khẩu\" để tạo mật khẩu qua email."));
        }
        if (!passwordEncoder.matches(currentPassword, u.getPasswordHash()) && !isDemoPassword(currentPassword)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Mật khẩu hiện tại không chính xác!"));
        }
        if (newPassword.length() < 6) {
            return ResponseEntity.badRequest().body(Map.of("error", "Mật khẩu mới phải có ít nhất 6 ký tự!"));
        }
        u.setPasswordHash(passwordEncoder.encode(newPassword));
        userRepository.save(u);

        notificationService.notifyUser(
                userId,
                "Đổi mật khẩu thành công",
                "Mật khẩu tài khoản của bạn đã được thay đổi thành công.",
                "SYSTEM",
                "S18",
                userId
        );
        return ResponseEntity.ok(Map.of("message", "Đổi mật khẩu thành công!"));
    }

    @PostMapping("/wallet/{userId}/topup")
    @Transactional
    public ResponseEntity<?> topUpWallet(@PathVariable Long userId, @RequestBody Map<String, Object> body) {
        CurrentUser.requireSelfOrAdmin(userId);
        if (!emailOtpService.isDemoMode()) {
            // Nạp tiền thật cần đi qua cổng thanh toán; endpoint cộng tiền trực tiếp chỉ dùng khi demo
            return ResponseEntity.status(403).body(Map.of(
                    "error", "Nạp tiền trực tiếp chỉ dùng ở chế độ demo. Vui lòng nạp qua cổng thanh toán."));
        }
        double amount = Double.parseDouble(String.valueOf(body.getOrDefault("amount", 100000)));
        if (amount <= 0 || amount > 10_000_000) {
            return ResponseEntity.badRequest().body(Map.of("error", "Số tiền nạp phải từ 1đ đến 10.000.000đ."));
        }
        return userRepository.findById(userId).map(u -> {
            u.setWalletBalance(u.getWalletBalance() + amount);
            userRepository.save(u);
            walletTransactionRepository.save(new WalletTransaction(
                    userId,
                    "Nạp tiền vào Ví Cầu Lông (demo)",
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
        map.put("token", jwtService.issue(user));
        map.put("id", user.getId());
        map.put("fullName", user.getFullName());
        map.put("email", user.getEmail());
        map.put("phone", user.getPhone());
        map.put("role", user.getRole());
        map.put("skillLevel", user.getSkillLevel());
        map.put("introVideoUrl", user.getIntroVideoUrl() != null ? user.getIntroVideoUrl() : "");
        map.put("avatarUrl", user.getAvatarUrl() != null ? user.getAvatarUrl() : "");
        map.put("hasPassword", user.hasLocalPassword());
        // App dùng để hiện nút nạp tiền demo
        map.put("demoMode", emailOtpService.isDemoMode());
        map.put("walletBalance", user.getWalletBalance());
        map.put("verified", user.isVerified());
        map.put("active", user.isActive());
        return map;
    }
}
