package com.badminton.v2.repository;

import com.badminton.v2.entity.Booking;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.Optional;

public interface BookingRepository extends JpaRepository<Booking, Long> {
    List<Booking> findByVenueIdAndPlayDateOrderByStartTimeAsc(Long venueId, String playDate);
    List<Booking> findByCourtIdAndPlayDateOrderByStartTimeAsc(Long courtId, String playDate);
    List<Booking> findByCustomerIdOrderByIdDesc(Long customerId);
    List<Booking> findByVenueIdOrderByIdDesc(Long venueId);
    List<Booking> findByStatus(String status);
    Optional<Booking> findByBookingCode(String bookingCode);
    Optional<Booking> findByQrCheckInToken(String qrCheckInToken);
}
