package com.badminton.v2.service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import org.springframework.transaction.annotation.Transactional;

import com.badminton.v2.entity.OtpToken;
import com.badminton.v2.repository.OtpTokenRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Optional;

@Service
public class EmailOtpService {

    private static final Logger log = LoggerFactory.getLogger(EmailOtpService.class);
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final OtpTokenRepository otpTokenRepository;
    private final JavaMailSender mailSender;

    private static final SecureRandom RANDOM = new SecureRandom();
    /** Mã OTP luôn đúng khi bật chế độ demo (app.demo-mode). */
    public static final String DEMO_OTP = "123456";

    @Value("${spring.mail.username:}")
    private String mailUsername;

    @Value("${app.demo-mode:true}")
    private boolean demoMode;

    public boolean isDemoMode() {
        return demoMode;
    }

    public EmailOtpService(OtpTokenRepository otpTokenRepository, Optional<JavaMailSender> mailSender) {
        this.otpTokenRepository = otpTokenRepository;
        this.mailSender = mailSender.orElse(null);
    }

    public OtpToken generateAndSendOtp(String email, String purpose) {
        String code = String.format("%06d", RANDOM.nextInt(900000) + 100000);
        String expiresAt = LocalDateTime.now().plusMinutes(5).format(FMT);

        OtpToken token = new OtpToken(email.trim().toLowerCase(), code, purpose.trim().toUpperCase(), expiresAt, false);
        otpTokenRepository.save(token);

        log.info("============================================================");
        log.info("[MODULE 4 - EMAIL OTP] Email: {} | Purpose: {} | OTP: {} (Expires: {})", email, purpose, code, expiresAt);
        log.info("============================================================");

        if (mailSender != null && mailUsername != null && !mailUsername.isBlank()) {
            try {
                SimpleMailMessage msg = new SimpleMailMessage();
                msg.setFrom(mailUsername);
                msg.setTo(email);
                msg.setSubject("[Badminton Hub] Mã xác thực bảo mật OTP của bạn: " + code);
                msg.setText("Xin chào,\n\nMã OTP xác thực (" + purpose + ") của bạn là: " + code
                        + "\nMã có hiệu lực trong vòng 5 phút. Tuyệt đối không chia sẻ mã này cho người khác.\n\nTrân trọng,\nBadminton Court Hub");
                mailSender.send(msg);
            } catch (Exception e) {
                log.warn("SMTP Mail not configured or failed ({}), using Console/Demo OTP fallback: {}", e.getMessage(), code);
            }
        }
        return token;
    }

    /** Số lần nhập sai tối đa cho một mã; vượt quá thì phải gửi mã mới. */
    public static final int MAX_FAILED_ATTEMPTS = 5;

    /**
     * Kiểm tra mã OTP mới nhất của [email] cho đúng mục đích [purpose]
     * (REGISTER, RESET_PASSWORD, WITHDRAW_WALLET, PAYOUT). Đúng thì đánh dấu đã dùng.
     * Mã của mục đích khác (VD mã đăng ký) không dùng được để rút tiền.
     */
    @Transactional
    public boolean verifyOtp(String email, String otpCode, String purpose) {
        if (email == null || otpCode == null || purpose == null) return false;
        String code = otpCode.trim();
        if (demoMode && DEMO_OTP.equals(code)) {
            // Mã demo dùng khi trình bày trên lớp; tắt bằng APP_DEMO_MODE=false
            return true;
        }
        Optional<OtpToken> opt = otpTokenRepository.findTopByEmailIgnoreCaseAndPurposeAndIsUsedFalseOrderByIdDesc(
                email.trim().toLowerCase(), purpose.trim().toUpperCase());
        if (opt.isEmpty()) {
            return false;
        }
        OtpToken token = opt.get();
        LocalDateTime exp = LocalDateTime.parse(token.getExpiresAt(), FMT);
        if (LocalDateTime.now().isAfter(exp) || token.getFailedAttempts() >= MAX_FAILED_ATTEMPTS) {
            return false;
        }
        boolean match = MessageDigest.isEqual(
                token.getOtpCode().getBytes(StandardCharsets.UTF_8), code.getBytes(StandardCharsets.UTF_8));
        if (!match) {
            token.setFailedAttempts(token.getFailedAttempts() + 1);
            otpTokenRepository.save(token);
            return false;
        }
        token.setUsed(true);
        otpTokenRepository.save(token);
        return true;
    }
}
