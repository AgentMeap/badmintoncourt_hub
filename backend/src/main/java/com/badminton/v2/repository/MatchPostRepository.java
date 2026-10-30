package com.badminton.v2.repository;

import com.badminton.v2.entity.MatchPost;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface MatchPostRepository extends JpaRepository<MatchPost, Long> {
    List<MatchPost> findAllByOrderByIdDesc();
    List<MatchPost> findByVenueIdOrderByIdDesc(Long venueId);
}
