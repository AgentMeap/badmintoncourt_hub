package com.badminton.v2.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.security.PublicKey;
import java.security.Signature;
import java.security.cert.CertificateFactory;
import java.time.Instant;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Kiểm tra Firebase ID token (sau khi app đăng nhập Google qua Firebase Auth) theo hướng dẫn
 * "Verify ID tokens using a third-party JWT library" của Firebase:
 * chữ ký RS256 bằng khóa công khai của Google, aud = project id, iss = securetoken, còn hạn.
 *
 * <p>Chỉ cần biến môi trường FIREBASE_PROJECT_ID, không cần file service account.
 */
@Service
public class FirebaseTokenVerifier {

    private static final Logger log = LoggerFactory.getLogger(FirebaseTokenVerifier.class);
    private static final String CERTS_URL =
            "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com";
    private static final Pattern MAX_AGE = Pattern.compile("max-age=(\\d+)");
    private static final long CLOCK_SKEW_SECONDS = 60;
    private static final Base64.Decoder B64D = Base64.getUrlDecoder();

    /** Thông tin người dùng lấy từ token đã kiểm tra. */
    public record FirebaseUser(String uid, String email, boolean emailVerified, String name, String picture) {
    }

    /** Token không hợp lệ (sai chữ ký, hết hạn, sai project...). */
    public static class InvalidTokenException extends Exception {
        public InvalidTokenException(String message) {
            super(message);
        }
    }

    private final String projectId;
    private final RestClient restClient;
    private final ObjectMapper objectMapper;

    private volatile Map<String, PublicKey> publicKeys = Map.of();
    private volatile long keysExpireAt = 0;

    public FirebaseTokenVerifier(@Value("${app.firebase.project-id:}") String projectId,
                                 RestClient restClient,
                                 ObjectMapper objectMapper) {
        this.projectId = projectId == null ? "" : projectId.trim();
        this.restClient = restClient;
        this.objectMapper = objectMapper;
    }

    public boolean isConfigured() {
        return !projectId.isEmpty();
    }

    public FirebaseUser verify(String idToken) throws InvalidTokenException {
        if (!isConfigured()) throw new InvalidTokenException("FIREBASE_PROJECT_ID chưa được cấu hình");
        if (idToken == null || idToken.isBlank()) throw new InvalidTokenException("Thiếu idToken");
        String[] parts = idToken.split("\\.");
        if (parts.length != 3) throw new InvalidTokenException("Sai định dạng JWT");

        Map<String, Object> header = readJson(parts[0]);
        Map<String, Object> claims = readJson(parts[1]);

        if (!"RS256".equals(header.get("alg"))) throw new InvalidTokenException("Sai thuật toán ký");
        PublicKey key = publicKey(String.valueOf(header.get("kid")));
        if (key == null) throw new InvalidTokenException("Không tìm thấy khóa ký (kid)");
        if (!signatureValid(key, parts)) throw new InvalidTokenException("Sai chữ ký");

        long now = Instant.now().getEpochSecond();
        if (number(claims.get("exp")) <= now - CLOCK_SKEW_SECONDS) throw new InvalidTokenException("Token đã hết hạn");
        if (number(claims.get("iat")) > now + CLOCK_SKEW_SECONDS) throw new InvalidTokenException("iat không hợp lệ");
        if (claims.containsKey("auth_time") && number(claims.get("auth_time")) > now + CLOCK_SKEW_SECONDS) {
            throw new InvalidTokenException("auth_time không hợp lệ");
        }
        if (!projectId.equals(claims.get("aud"))) throw new InvalidTokenException("Sai audience (project id)");
        if (!("https://securetoken.google.com/" + projectId).equals(claims.get("iss"))) {
            throw new InvalidTokenException("Sai issuer");
        }
        Object sub = claims.get("sub");
        if (!(sub instanceof String uid) || uid.isBlank()) throw new InvalidTokenException("Thiếu sub");

        return new FirebaseUser(
                uid,
                claims.get("email") instanceof String e ? e.trim().toLowerCase() : null,
                Boolean.TRUE.equals(claims.get("email_verified")),
                claims.get("name") instanceof String n ? n : null,
                claims.get("picture") instanceof String p ? p : null
        );
    }

    private boolean signatureValid(PublicKey key, String[] parts) throws InvalidTokenException {
        try {
            Signature sig = Signature.getInstance("SHA256withRSA");
            sig.initVerify(key);
            sig.update((parts[0] + "." + parts[1]).getBytes(StandardCharsets.US_ASCII));
            return sig.verify(B64D.decode(parts[2]));
        } catch (Exception e) {
            throw new InvalidTokenException("Không kiểm tra được chữ ký");
        }
    }

    /** Khóa công khai của Google theo kid; tải lại khi hết hạn cache hoặc gặp kid mới. */
    private PublicKey publicKey(String kid) throws InvalidTokenException {
        long now = Instant.now().getEpochSecond();
        if (now >= keysExpireAt || !publicKeys.containsKey(kid)) {
            refreshKeys();
        }
        return publicKeys.get(kid);
    }

    private synchronized void refreshKeys() throws InvalidTokenException {
        try {
            ResponseEntity<Map> res = restClient.get().uri(CERTS_URL).retrieve().toEntity(Map.class);
            Map<?, ?> body = res.getBody();
            if (body == null) throw new InvalidTokenException("Không tải được khóa của Google");
            CertificateFactory factory = CertificateFactory.getInstance("X.509");
            Map<String, PublicKey> keys = new HashMap<>();
            for (Map.Entry<?, ?> e : body.entrySet()) {
                byte[] pem = String.valueOf(e.getValue()).getBytes(StandardCharsets.US_ASCII);
                keys.put(String.valueOf(e.getKey()),
                        factory.generateCertificate(new ByteArrayInputStream(pem)).getPublicKey());
            }
            long maxAge = 3600;
            String cacheControl = res.getHeaders().getCacheControl();
            if (cacheControl != null) {
                Matcher m = MAX_AGE.matcher(cacheControl);
                if (m.find()) maxAge = Long.parseLong(m.group(1));
            }
            publicKeys = keys;
            keysExpireAt = Instant.now().getEpochSecond() + maxAge;
        } catch (InvalidTokenException e) {
            throw e;
        } catch (Exception e) {
            log.warn("Không tải được khóa công khai Firebase: {}", e.getMessage());
            throw new InvalidTokenException("Không tải được khóa của Google");
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> readJson(String base64Url) throws InvalidTokenException {
        try {
            return objectMapper.readValue(B64D.decode(base64Url), Map.class);
        } catch (Exception e) {
            throw new InvalidTokenException("Sai định dạng JWT");
        }
    }

    private static long number(Object value) throws InvalidTokenException {
        if (value instanceof Number n) return n.longValue();
        throw new InvalidTokenException("Thiếu thời gian trong token");
    }
}
