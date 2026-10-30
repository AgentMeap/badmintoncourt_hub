package com.badminton.v2.repository;

import com.badminton.v2.entity.PayoutRequest;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface PayoutRequestRepository extends JpaRepository<PayoutRequest, Long> {
    List<PayoutRequest> findByOwnerIdOrderByIdDesc(Long ownerId);
    List<PayoutRequest> findAllByOrderByIdDesc();
}
