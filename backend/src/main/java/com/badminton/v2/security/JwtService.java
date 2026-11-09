package com.badminton.v2.security;

import com.badminton.v2.entity.User;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Cấp và kiểm tra JWT (HS256) cho phiên đăng nhập của app.
 * Payload: sub = id người dùng, role, email, iat, exp (giây).
 */
@Service
public class JwtService {

    private static final Logger log = LoggerFactory.getLogger(JwtService.class);
    private static final Base64.Encoder B64 = Base64.getUrlEncoder().withoutPadding();
    private static final Base64.Decoder B64D = Base64.getUrlDecoder();
    private static final String HEADER = B64.encodeToString(
            "{\"alg\":\"HS256\",\"typ\":\"JWT\"}".getBytes(StandardCharsets.UTF_8));

    private final byte[] secret;
    private final long expirationSeconds;
    private final ObjectMapper objectMapper;

    public JwtService(@Value("${app.jwt.secret}") String secret,
                      @Value("${app.jwt.expiration-ms:604800000}") long expirationMs,
                      ObjectMapper objectMapper) {
        this.secret = secret.getBytes(StandardCharsets.UTF_8);
        this.expirationSeconds = Math.max(60, expirationMs / 1000);
        this.objectMapper = objectMapper;
        if (this.secret.length < 32) {
            log.warn("app.jwt.secret ngắn hơn 32 byte - hãy đặt JWT_SECRET dài hơn khi triển khai thật.");
        }
    }

    /** Tạo token đăng nhập cho [user]. */
    public String issue(User user) {
        long now = Instant.now().getEpochSecond();
        Map<String, Object> claims = new LinkedHashMap<>();
        claims.put("sub", String.valueOf(user.getId()));
        claims.put("role", user.getRole());
        claims.put("email", user.getEmail());
        claims.put("iat", now);
        claims.put("exp", now + expirationSeconds);
        try {
            String payload = B64.encodeToString(objectMapper.writeValueAsBytes(claims));
            String unsigned = HEADER + "." + payload;
            return unsigned + "." + B64.encodeToString(sign(unsigned));
        } catch (Exception e) {
            throw new IllegalStateException("Không tạo được token đăng nhập", e);
        }
    }

    /** Kiểm tra chữ ký + hạn dùng. Token sai / hết hạn trả về null. */
    public AuthUser verify(String token) {
        if (token == null) return null;
        String[] parts = token.split("\\.");
        if (parts.length != 3 || !HEADER.equals(parts[0])) return null;
        try {
            byte[] expected = sign(parts[0] + "." + parts[1]);
            if (!MessageDigest.isEqual(expected, B64D.decode(parts[2]))) return null;

            @SuppressWarnings("unchecked")
            Map<String, Object> claims = objectMapper.readValue(B64D.decode(parts[1]), Map.class);
            long exp = ((Number) claims.get("exp")).longValue();
            if (Instant.now().getEpochSecond() >= exp) return null;
            return new AuthUser(
                    Long.valueOf(String.valueOf(claims.get("sub"))),
                    String.valueOf(claims.get("role")),
                    String.valueOf(claims.get("email"))
            );
        } catch (Exception e) {
            return null;
        }
    }

    private byte[] sign(String data) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(secret, "HmacSHA256"));
        return mac.doFinal(data.getBytes(StandardCharsets.US_ASCII));
    }
}
