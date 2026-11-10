package com.badminton.v2.repository;

import com.badminton.v2.entity.Payment;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.util.Optional;
import java.util.List;

public interface PaymentRepository extends JpaRepository<Payment, Long> {
    Optional<Payment> findByPayosOrderCode(Long payosOrderCode);
    Optional<Payment> findTopByBookingIdOrderByIdDesc(Long bookingId);
    List<Payment> findByStatusOrderByIdDesc(String status);
    List<Payment> findByUserIdAndPurposeAndStatusOrderByIdDesc(Long userId, String purpose, String status);

    /** PENDING -> PAID đúng một lần (trả về 1 nếu lần này đổi được). */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update Payment p set p.status = 'PAID', p.paidAt = :paidAt where p.id = :id and p.status = 'PENDING'")
    int markPaid(@Param("id") Long id, @Param("paidAt") String paidAt);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update Payment p set p.status = 'CANCELLED' where p.id = :id and p.status = 'PENDING'")
    int markCancelled(@Param("id") Long id);
}
