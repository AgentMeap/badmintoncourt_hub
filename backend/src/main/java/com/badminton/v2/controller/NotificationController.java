package com.badminton.v2.controller;

import com.badminton.v2.entity.NotificationItem;
import com.badminton.v2.service.NotificationService;
import com.badminton.v2.security.CurrentUser;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/notifications")
public class NotificationController {

    private final NotificationService notificationService;

    public NotificationController(NotificationService notificationService) {
        this.notificationService = notificationService;
    }

    @GetMapping("/user/{userId}")
    public ResponseEntity<?> getUserNotifications(@PathVariable Long userId) {
        CurrentUser.requireSelfOrAdmin(userId);
        List<NotificationItem> items = notificationService.getUserNotifications(userId);
        long unread = notificationService.getUnreadCount(userId);
        return ResponseEntity.ok(Map.of(
                "unreadCount", unread,
                "items", items
        ));
    }

    /** Nhẹ, cho app hỏi định kỳ: {unreadCount, latestId}. latestId đổi = có thông báo mới. */
    @GetMapping("/user/{userId}/unread-count")
    public ResponseEntity<?> unreadCount(@PathVariable Long userId) {
        CurrentUser.requireSelfOrAdmin(userId);
        Map<String, Object> res = new java.util.LinkedHashMap<>();
        res.put("unreadCount", notificationService.getUnreadCount(userId));
        res.put("latestId", notificationService.latestId(userId));
        return ResponseEntity.ok(res);
    }

    @PatchMapping("/{id}/read")
    public ResponseEntity<?> markRead(@PathVariable Long id) {
        notificationService.find(id).ifPresent(n -> CurrentUser.requireSelfOrAdmin(n.getUserId()));
        NotificationItem item = notificationService.markAsRead(id);
        return ResponseEntity.ok(item != null ? item : Map.of("status", "ok"));
    }

    @PostMapping("/user/{userId}/read-all")
    public ResponseEntity<?> markAllRead(@PathVariable Long userId) {
        CurrentUser.requireSelfOrAdmin(userId);
        notificationService.markAllAsRead(userId);
        return ResponseEntity.ok(Map.of("message", "Đã đánh dấu đọc tất cả thông báo"));
    }
}
