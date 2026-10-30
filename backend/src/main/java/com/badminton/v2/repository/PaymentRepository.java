package com.badminton.v2.repository;

import com.badminton.v2.entity.Payment;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.Optional;
import java.util.List;

public interface PaymentRepository extends JpaRepository<Payment, Long> {
    Optional<Payment> findByPayosOrderCode(Long payosOrderCode);
    Optional<Payment> findTopByBookingIdOrderByIdDesc(Long bookingId);
    List<Payment> findByStatusOrderByIdDesc(String status);
}
