package com.badminton.v2;

import com.badminton.v2.entity.NotificationItem;
import com.badminton.v2.entity.User;
import com.badminton.v2.repository.DeviceTokenRepository;
import com.badminton.v2.service.NotificationService;
import com.badminton.v2.service.PushService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Thông báo đẩy: đăng ký / bỏ mã thiết bị, nội dung tin FCM; chưa cấu hình FCM thì thông báo vẫn tạo bình thường. */
class PushNotificationTest extends IntegrationTestBase {

    @Autowired private DeviceTokenRepository tokenRepository;
    @Autowired private PushService pushService;
    @Autowired private NotificationService notificationService;

    @Test
    @DisplayName("Đăng ký mã thiết bị: cần đăng nhập, mã chuyển sang người đăng nhập sau, bỏ mã khi đăng xuất")
    void registerAndUnregister() throws Exception {
        User a = newUser("CUSTOMER", 0);
        User b = newUser("CUSTOMER", 0);
        String token = "test-fcm-token-" + a.getId();

        mvc.perform(postAs(null, Map.of("token", token), "/api/devices")).andExpect(status().isUnauthorized());
        mvc.perform(postAs(tokenOf(a), Map.of("token", ""), "/api/devices")).andExpect(status().isBadRequest());

        var res = body(mvc.perform(postAs(tokenOf(a), Map.of("token", token, "platform", "android"), "/api/devices"))
                .andExpect(status().isOk()).andReturn());
        assertTrue(res.path("registered").asBoolean());
        assertFalse(res.path("pushEnabled").asBoolean(), "test không cấu hình FCM");
        assertEquals(a.getId(), tokenRepository.findByToken(token).orElseThrow().getUserId());
        assertEquals("ANDROID", tokenRepository.findByToken(token).orElseThrow().getPlatform());

        // Cùng điện thoại, người khác đăng nhập -> mã chuyển sang người đó (không nhận nhầm thông báo)
        mvc.perform(postAs(tokenOf(b), Map.of("token", token), "/api/devices")).andExpect(status().isOk());
        assertEquals(b.getId(), tokenRepository.findByToken(token).orElseThrow().getUserId());
        assertEquals(1, tokenRepository.findAll().stream().filter(d -> token.equals(d.getToken())).count());

        // a không xoá được mã của b
        var notMine = body(mvc.perform(postAs(tokenOf(a), Map.of("token", token), "/api/devices/unregister"))
                .andExpect(status().isOk()).andReturn());
        assertFalse(notMine.path("removed").asBoolean());
        var removed = body(mvc.perform(postAs(tokenOf(b), Map.of("token", token), "/api/devices/unregister"))
                .andExpect(status().isOk()).andReturn());
        assertTrue(removed.path("removed").asBoolean());
        assertTrue(tokenRepository.findByToken(token).isEmpty());
    }

    @Test
    @DisplayName("Chưa cấu hình FCM: tạo thông báo vẫn chạy bình thường (không gửi đẩy)")
    void notifyWithoutFcm() {
        User a = newUser("CUSTOMER", 0);
        pushService.register(a.getId(), "token-no-fcm-" + a.getId(), "ANDROID");
        assertFalse(pushService.isEnabled());
        NotificationItem n = notificationService.notifyUser(a.getId(), "Tiêu đề", "Nội dung", "MATCHMAKING", "S30", 5L);
        assertNotNull(n.getId());
    }

    @Test
    @DisplayName("Nội dung tin FCM: có notification + data để mở đúng màn; tin nhắn cùng kèo dùng chung tag")
    @SuppressWarnings("unchecked")
    void messageShape() {
        NotificationItem chat = new NotificationItem(1L, "3 tin nhắn mới · Kèo A", "Minh: mai mang cầu", "CHAT", "S30", 42L, false, "2026-11-10 18:00:00");
        Map<String, Object> m = PushService.messageOf(chat);
        Map<String, String> data = (Map<String, String>) m.get("data");
        assertEquals("CHAT", data.get("type"));
        assertEquals("S30", data.get("targetScreen"));
        assertEquals("42", data.get("referenceId"));
        Map<String, Object> notification = (Map<String, Object>) m.get("notification");
        assertEquals("3 tin nhắn mới · Kèo A", notification.get("title"));
        Map<String, Object> android = (Map<String, Object>) ((Map<String, Object>) m.get("android")).get("notification");
        assertEquals("chat-42", android.get("tag"));
    }
}
