package com.badminton.v2.repository;

import com.badminton.v2.entity.MatchMessage;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface MatchMessageRepository extends JpaRepository<MatchMessage, Long> {
    List<MatchMessage> findTop100ByMatchIdOrderByIdDesc(Long matchId);
    List<MatchMessage> findByMatchIdAndIdGreaterThanOrderByIdAsc(Long matchId, Long afterId);
    long countByMatchId(Long matchId);
}
