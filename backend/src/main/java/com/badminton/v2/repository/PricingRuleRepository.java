package com.badminton.v2.repository;

import com.badminton.v2.entity.PricingRule;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface PricingRuleRepository extends JpaRepository<PricingRule, Long> {
    List<PricingRule> findByVenueIdOrderByStartTimeAsc(Long venueId);
}
