package com.badminton.v2.repository;

import com.badminton.v2.entity.MatchChatRead;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.Optional;

public interface MatchChatReadRepository extends JpaRepository<MatchChatRead, Long> {
    Optional<MatchChatRead> findByMatchIdAndUserId(Long matchId, Long userId);
}
