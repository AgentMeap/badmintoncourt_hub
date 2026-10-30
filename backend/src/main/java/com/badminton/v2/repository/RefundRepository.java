package com.badminton.v2.repository;

import com.badminton.v2.entity.Refund;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface RefundRepository extends JpaRepository<Refund, Long> {
    List<Refund> findByCustomerIdOrderByIdDesc(Long customerId);
    List<Refund> findByBookingIdOrderByIdDesc(Long bookingId);
}
