package com.badminton.v2.service;

import com.badminton.v2.entity.DeviceToken;
import com.badminton.v2.entity.NotificationItem;
import com.badminton.v2.repository.DeviceTokenRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Thông báo đẩy qua Firebase Cloud Messaging (HTTP v1).
 * <ul>
 *   <li>Cấu hình: {@code app.fcm.credentials-file} = đường dẫn file JSON service account (Firebase Console >
 *       Project settings > Service accounts > Generate new private key). File này là bí mật, không commit.</li>
 *   <li>Không cấu hình: mọi lệnh gửi bị bỏ qua (app vẫn có thông báo trong app qua hỏi định kỳ).</li>
 *   <li>Gửi chạy nền (không làm chậm API). Mã thiết bị bị FCM báo hết hạn (UNREGISTERED / 404) thì xoá.</li>
 *   <li>Access token OAuth tự ký JWT RS256 bằng khoá của service account, giữ lại tới gần hết hạn (không cần thư viện ngoài).</li>
 * </ul>
 */
@Service
public class PushService {

    private static final Logger log = LoggerFactory.getLogger(PushService.class);
    private static final String SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final DeviceTokenRepository tokenRepository;
    private final ObjectMapper json;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    private final ExecutorService executor = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "fcm-push");
        t.setDaemon(true);
        return t;
    });

    private String projectId;
    private String clientEmail;
    private String tokenUri;
    private PrivateKey privateKey;
    private String accessToken;
    private Instant accessTokenExpiresAt = Instant.EPOCH;

    public PushService(DeviceTokenRepository tokenRepository, ObjectMapper json,
                       @Value("${app.fcm.credentials-file:}") String credentialsFile) {
        this.tokenRepository = tokenRepository;
        this.json = json;
        loadCredentials(credentialsFile == null ? "" : credentialsFile.trim());
    }

    private void loadCredentials(String file) {
        if (file.isEmpty()) {
            log.info("FCM chưa cấu hình (app.fcm.credentials-file trống): tắt thông báo đẩy.");
            return;
        }
        try {
            JsonNode sa = json.readTree(Files.readString(Path.of(file)));
            projectId = sa.path("project_id").asText();
            clientEmail = sa.path("client_email").asText();
            tokenUri = sa.path("token_uri").asText("https://oauth2.googleapis.com/token");
            String pem = sa.path("private_key").asText()
                    .replace("-----BEGIN PRIVATE KEY-----", "")
                    .replace("-----END PRIVATE KEY-----", "")
                    .replaceAll("\\s", "");
            privateKey = KeyFactory.getInstance("RSA")
                    .generatePrivate(new PKCS8EncodedKeySpec(Base64.getDecoder().decode(pem)));
            log.info("FCM đã bật cho project {}", projectId);
        } catch (Exception e) {
            projectId = null;
            privateKey = null;
            log.warn("Không đọc được file service account FCM '{}': {}. Tắt thông báo đẩy.", file, e.getMessage());
        }
    }

    public boolean isEnabled() {
        return privateKey != null && projectId != null && !projectId.isBlank();
    }

    // ------------------------------------------------------------------ Mã thiết bị

    /** Lưu / chuyển mã thiết bị cho người dùng (một mã chỉ thuộc một người). */
    public DeviceToken register(Long userId, String token, String platform) {
        DeviceToken d = tokenRepository.findByToken(token).orElseGet(DeviceToken::new);
        d.setUserId(userId);
        d.setToken(token);
        d.setPlatform(platform == null || platform.isBlank() ? "ANDROID" : platform.toUpperCase());
        d.setUpdatedAt(LocalDateTime.now().format(FMT));
        return tokenRepository.save(d);
    }

    /** Bỏ mã thiết bị (đăng xuất). Chỉ xoá nếu mã thuộc [userId]. */
    public boolean unregister(Long userId, String token) {
        return tokenRepository.findByToken(token).filter(d -> d.getUserId().equals(userId)).map(d -> {
            tokenRepository.delete(d);
            return true;
        }).orElse(false);
    }

    // ------------------------------------------------------------------ Gửi

    /** Gửi thông báo đẩy cho mọi thiết bị của người nhận (chạy nền, lỗi chỉ ghi log). */
    public void pushAsync(NotificationItem n) {
        if (!isEnabled() || n == null || n.getUserId() == null) return;
        List<DeviceToken> devices = tokenRepository.findByUserId(n.getUserId());
        if (devices.isEmpty()) return;
        Map<String, Object> message = messageOf(n);
        for (DeviceToken d : devices) {
            String token = d.getToken();
            executor.submit(() -> send(token, message));
        }
    }

    /** Thân tin FCM: notification (Android tự hiện khi app ở nền / đã đóng) + data để app mở đúng màn hình. */
    public static Map<String, Object> messageOf(NotificationItem n) {
        Map<String, String> data = new LinkedHashMap<>();
        if (n.getId() != null) data.put("id", String.valueOf(n.getId()));
        data.put("title", nz(n.getTitle()));
        data.put("body", nz(n.getBody()));
        data.put("type", nz(n.getType()));
        data.put("targetScreen", nz(n.getTargetScreen()));
        if (n.getReferenceId() != null) data.put("referenceId", String.valueOf(n.getReferenceId()));

        // Gộp trên máy: tin nhắn của cùng một kèo thay nhau, các thông báo khác giữ riêng
        String tag = "CHAT".equals(n.getType()) && n.getReferenceId() != null
                ? "chat-" + n.getReferenceId()
                : "n-" + (n.getId() == null ? UUID.randomUUID() : n.getId());
        Map<String, Object> androidNotification = new LinkedHashMap<>();
        androidNotification.put("tag", tag);
        androidNotification.put("click_action", "FLUTTER_NOTIFICATION_CLICK");

        Map<String, Object> message = new LinkedHashMap<>();
        message.put("notification", Map.of("title", nz(n.getTitle()), "body", nz(n.getBody())));
        message.put("data", data);
        message.put("android", Map.of("priority", "HIGH", "notification", androidNotification));
        return message;
    }

    private static String nz(String s) {
        return s == null ? "" : s;
    }

    private void send(String token, Map<String, Object> message) {
        try {
            Map<String, Object> m = new LinkedHashMap<>(message);
            m.put("token", token);
            String body = json.writeValueAsString(Map.of("message", m));
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create("https://fcm.googleapis.com/v1/projects/" + projectId + "/messages:send"))
                    .timeout(Duration.ofSeconds(15))
                    .header("Authorization", "Bearer " + accessToken())
                    .header("Content-Type", "application/json; charset=UTF-8")
                    .POST(HttpRequest.BodyPublishers.ofString(body, StandardCharsets.UTF_8))
                    .build();
            HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() == 404 || res.body().contains("UNREGISTERED")
                    || (res.statusCode() == 400 && res.body().contains("registration token"))) {
                // Ứng dụng đã gỡ / mã hết hạn
                tokenRepository.findByToken(token).ifPresent(tokenRepository::delete);
                log.info("Xoá mã thiết bị FCM không còn hợp lệ");
            } else if (res.statusCode() >= 300) {
                log.warn("FCM trả lỗi {}: {}", res.statusCode(), res.body());
            }
        } catch (Exception e) {
            log.warn("Gửi thông báo đẩy lỗi: {}", e.getMessage());
        }
    }

    /** Access token OAuth 2 cho FCM (ký JWT bằng khoá service account), dùng lại tới khi còn < 5 phút. */
    private synchronized String accessToken() throws Exception {
        if (accessToken != null && Instant.now().isBefore(accessTokenExpiresAt.minusSeconds(300))) return accessToken;
        long now = Instant.now().getEpochSecond();
        Base64.Encoder b64 = Base64.getUrlEncoder().withoutPadding();
        String header = b64.encodeToString("{\"alg\":\"RS256\",\"typ\":\"JWT\"}".getBytes(StandardCharsets.UTF_8));
        String claims = b64.encodeToString(json.writeValueAsBytes(Map.of(
                "iss", clientEmail, "scope", SCOPE, "aud", tokenUri, "iat", now, "exp", now + 3600)));
        Signature sig = Signature.getInstance("SHA256withRSA");
        sig.initSign(privateKey);
        sig.update((header + "." + claims).getBytes(StandardCharsets.UTF_8));
        String jwt = header + "." + claims + "." + b64.encodeToString(sig.sign());

        String form = "grant_type=" + URLEncoder.encode("urn:ietf:params:oauth:grant-type:jwt-bearer", StandardCharsets.UTF_8)
                + "&assertion=" + jwt;
        HttpResponse<String> res = http.send(HttpRequest.newBuilder()
                        .uri(URI.create(tokenUri))
                        .timeout(Duration.ofSeconds(15))
                        .header("Content-Type", "application/x-www-form-urlencoded")
                        .POST(HttpRequest.BodyPublishers.ofString(form))
                        .build(),
                HttpResponse.BodyHandlers.ofString());
        if (res.statusCode() >= 300) throw new IllegalStateException("Không lấy được access token FCM: " + res.body());
        JsonNode t = json.readTree(res.body());
        accessToken = t.path("access_token").asText();
        accessTokenExpiresAt = Instant.now().plusSeconds(t.path("expires_in").asLong(3600));
        return accessToken;
    }

    @PreDestroy
    void shutdown() {
        executor.shutdown();
    }
}
