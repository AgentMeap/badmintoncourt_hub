package com.badminton.v2.repository;

import com.badminton.v2.entity.AiChatSession;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface AiChatSessionRepository extends JpaRepository<AiChatSession, Long> {
    List<AiChatSession> findByUserIdOrderByIdDesc(Long userId);
}
