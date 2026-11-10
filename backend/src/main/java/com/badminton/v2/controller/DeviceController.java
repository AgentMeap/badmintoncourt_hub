package com.badminton.v2.controller;

import com.badminton.v2.security.AuthUser;
import com.badminton.v2.security.CurrentUser;
import com.badminton.v2.service.PushService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * Mã thiết bị cho thông báo đẩy (FCM).
 * <ul>
 *   <li>POST /api/devices            {token, platform}  app gửi sau khi đăng nhập / khi mã đổi</li>
 *   <li>POST /api/devices/unregister {token}            app gửi khi đăng xuất</li>
 * </ul>
 */
@RestController
@RequestMapping("/api/devices")
public class DeviceController {

    private final PushService pushService;

    public DeviceController(PushService pushService) {
        this.pushService = pushService;
    }

    private static Long me() {
        return CurrentUser.get().map(AuthUser::id).orElse(null);
    }

    @PostMapping
    public ResponseEntity<?> register(@RequestBody Map<String, Object> body) {
        Long me = me();
        if (me == null) return ResponseEntity.status(401).body(Map.of("error", "Vui lòng đăng nhập."));
        String token = body.get("token") == null ? "" : String.valueOf(body.get("token")).trim();
        if (token.isEmpty() || token.length() > 512) {
            return ResponseEntity.badRequest().body(Map.of("error", "Mã thiết bị không hợp lệ."));
        }
        pushService.register(me, token, body.get("platform") == null ? null : String.valueOf(body.get("platform")));
        return ResponseEntity.ok(Map.of("registered", true, "pushEnabled", pushService.isEnabled()));
    }

    @PostMapping("/unregister")
    public ResponseEntity<?> unregister(@RequestBody Map<String, Object> body) {
        Long me = me();
        if (me == null) return ResponseEntity.status(401).body(Map.of("error", "Vui lòng đăng nhập."));
        String token = body.get("token") == null ? "" : String.valueOf(body.get("token")).trim();
        return ResponseEntity.ok(Map.of("removed", pushService.unregister(me, token)));
    }
}
