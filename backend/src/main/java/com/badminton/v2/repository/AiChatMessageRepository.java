package com.badminton.v2.repository;

import com.badminton.v2.entity.AiChatMessage;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface AiChatMessageRepository extends JpaRepository<AiChatMessage, Long> {
    List<AiChatMessage> findBySessionIdOrderByIdDesc(Long sessionId);

    /** Đếm tin của người dùng từ mốc [since] ("yyyy-MM-dd HH:mm:ss") để giới hạn lượt hỏi. */
    long countByUserIdAndRoleAndCreatedAtGreaterThanEqual(Long userId, String role, String since);
}
