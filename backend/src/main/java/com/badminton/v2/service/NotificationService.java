package com.badminton.v2.service;

import com.badminton.v2.entity.NotificationItem;
import com.badminton.v2.repository.NotificationRepository;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Optional;

@Service
public class NotificationService {

    private final NotificationRepository notificationRepository;
    private final PushService pushService;
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    public NotificationService(NotificationRepository notificationRepository, PushService pushService) {
        this.notificationRepository = notificationRepository;
        this.pushService = pushService;
    }

    public NotificationItem notifyUser(Long userId, String title, String body, String type, String targetScreen, Long referenceId) {
        if (userId == null) return null;
        NotificationItem item = new NotificationItem(
                userId,
                title,
                body,
                type,
                targetScreen,
                referenceId,
                false,
                LocalDateTime.now().format(FMT)
        );
        NotificationItem saved = notificationRepository.save(item);
        pushService.pushAsync(saved); // thông báo đẩy về điện thoại (nếu đã cấu hình FCM)
        return saved;
    }

    public List<NotificationItem> getUserNotifications(Long userId) {
        return notificationRepository.findByUserIdOrderByIdDesc(userId);
    }

    public long getUnreadCount(Long userId) {
        return notificationRepository.countByUserIdAndIsReadFalse(userId);
    }

    /** Id thông báo mới nhất của người dùng (0 nếu chưa có). */
    public long latestId(Long userId) {
        return notificationRepository.findTopByUserIdOrderByIdDesc(userId).map(NotificationItem::getId).orElse(0L);
    }

    public Optional<NotificationItem> find(Long id) {
        return notificationRepository.findById(id);
    }

    public NotificationItem markAsRead(Long id) {
        return notificationRepository.findById(id).map(n -> {
            n.setRead(true);
            return notificationRepository.save(n);
        }).orElse(null);
    }

    public void markAllAsRead(Long userId) {
        List<NotificationItem> list = notificationRepository.findByUserIdOrderByIdDesc(userId);
        for (NotificationItem item : list) {
            if (!item.isRead()) {
                item.setRead(true);
                notificationRepository.save(item);
            }
        }
    }
}
