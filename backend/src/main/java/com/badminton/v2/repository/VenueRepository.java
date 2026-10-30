package com.badminton.v2.repository;

import com.badminton.v2.entity.Venue;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface VenueRepository extends JpaRepository<Venue, Long> {
    List<Venue> findByStatusOrderByIdDesc(String status);
    List<Venue> findByOwnerIdOrderByIdDesc(Long ownerId);
}
