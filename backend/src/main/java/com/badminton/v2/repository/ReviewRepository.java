package com.badminton.v2.repository;

import com.badminton.v2.entity.Review;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface ReviewRepository extends JpaRepository<Review, Long> {
    List<Review> findByVenueIdOrderByIdDesc(Long venueId);
    List<Review> findByUserIdOrderByIdDesc(Long userId);
    boolean existsByBookingCode(String bookingCode);
}
