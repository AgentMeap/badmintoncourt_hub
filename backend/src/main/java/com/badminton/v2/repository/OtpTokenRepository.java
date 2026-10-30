package com.badminton.v2.repository;

import com.badminton.v2.entity.OtpToken;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.Optional;

public interface OtpTokenRepository extends JpaRepository<OtpToken, Long> {
    Optional<OtpToken> findTopByEmailIgnoreCaseAndOtpCodeAndIsUsedFalseOrderByIdDesc(String email, String otpCode);
    Optional<OtpToken> findTopByEmailIgnoreCaseOrderByIdDesc(String email);
}
