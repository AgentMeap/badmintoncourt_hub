package com.badminton.v2.repository;

import com.badminton.v2.entity.NotificationItem;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface NotificationRepository extends JpaRepository<NotificationItem, Long> {
    List<NotificationItem> findByUserIdOrderByIdDesc(Long userId);
    long countByUserIdAndIsReadFalse(Long userId);
}
