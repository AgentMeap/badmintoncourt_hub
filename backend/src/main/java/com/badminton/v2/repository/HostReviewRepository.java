package com.badminton.v2.repository;

import com.badminton.v2.entity.HostReview;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.Optional;

public interface HostReviewRepository extends JpaRepository<HostReview, Long> {
    Optional<HostReview> findByMatchIdAndRaterId(Long matchId, Long raterId);
    List<HostReview> findByHostIdOrderByIdDesc(Long hostId);
    List<HostReview> findTop20ByHostIdOrderByIdDesc(Long hostId);
}
