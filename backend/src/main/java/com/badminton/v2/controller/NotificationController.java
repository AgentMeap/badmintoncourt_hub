package com.badminton.v2.controller;

import com.badminton.v2.entity.NotificationItem;
import com.badminton.v2.service.NotificationService;
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
        List<NotificationItem> items = notificationService.getUserNotifications(userId);
        long unread = notificationService.getUnreadCount(userId);
        return ResponseEntity.ok(Map.of(
                "unreadCount", unread,
                "items", items
        ));
    }

    @PatchMapping("/{id}/read")
    public ResponseEntity<?> markRead(@PathVariable Long id) {
        NotificationItem item = notificationService.markAsRead(id);
        return ResponseEntity.ok(item != null ? item : Map.of("status", "ok"));
    }

    @PostMapping("/user/{userId}/read-all")
    public ResponseEntity<?> markAllRead(@PathVariable Long userId) {
        notificationService.markAllAsRead(userId);
        return ResponseEntity.ok(Map.of("message", "Đã đánh dấu đọc tất cả thông báo"));
    }
}
