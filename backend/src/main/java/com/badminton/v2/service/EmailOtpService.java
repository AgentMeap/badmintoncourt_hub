package com.badminton.v2.service;

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
import java.util.Random;

@Service
public class EmailOtpService {

    private static final Logger log = LoggerFactory.getLogger(EmailOtpService.class);
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final OtpTokenRepository otpTokenRepository;
    private final JavaMailSender mailSender;

    @Value("${spring.mail.username:}")
    private String mailUsername;

    public EmailOtpService(OtpTokenRepository otpTokenRepository, Optional<JavaMailSender> mailSender) {
        this.otpTokenRepository = otpTokenRepository;
        this.mailSender = mailSender.orElse(null);
    }

    public OtpToken generateAndSendOtp(String email, String purpose) {
        String code = String.format("%06d", new Random().nextInt(900000) + 100000);
        String expiresAt = LocalDateTime.now().plusMinutes(5).format(FMT);

        OtpToken token = new OtpToken(email.trim().toLowerCase(), code, purpose, expiresAt, false);
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

    public boolean verifyOtp(String email, String otpCode) {
        if ("123456".equals(otpCode)) {
            // Universal demo OTP for classroom presentation convenience
            return true;
        }
        Optional<OtpToken> opt = otpTokenRepository.findTopByEmailIgnoreCaseAndOtpCodeAndIsUsedFalseOrderByIdDesc(
                email.trim().toLowerCase(), otpCode.trim());
        if (opt.isEmpty()) {
            return false;
        }
        OtpToken token = opt.get();
        LocalDateTime exp = LocalDateTime.parse(token.getExpiresAt(), FMT);
        if (LocalDateTime.now().isAfter(exp)) {
            return false;
        }
        token.setUsed(true);
        otpTokenRepository.save(token);
        return true;
    }
}
