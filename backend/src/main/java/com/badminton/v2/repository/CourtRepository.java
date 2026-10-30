package com.badminton.v2.repository;

import com.badminton.v2.entity.Court;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface CourtRepository extends JpaRepository<Court, Long> {
    List<Court> findByVenueIdOrderByIdAsc(Long venueId);
}
