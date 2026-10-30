package com.badminton.v2.repository;

import com.badminton.v2.entity.MatchParticipant;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.Optional;

public interface MatchParticipantRepository extends JpaRepository<MatchParticipant, Long> {
    List<MatchParticipant> findByMatchIdOrderByIdAsc(Long matchId);
    Optional<MatchParticipant> findByMatchIdAndUserId(Long matchId, Long userId);
}
