package com.badminton.v2.config;

import com.badminton.v2.entity.User;
import com.badminton.v2.entity.Venue;
import com.badminton.v2.repository.BookingRepository;
import com.badminton.v2.repository.UserRepository;
import com.badminton.v2.repository.VenueRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;

/**
 * Chủ sân thứ hai để trình bày dòng tiền theo từng chủ sân (sân của chủ A -> tiền của chủ A).
 * Chạy sau DataSeeder, kể cả khi database đã có dữ liệu: nếu chưa có owner2@badminton.vn thì tạo
 * và chuyển 4 cơ sở đã duyệt (chưa có vé nào) của owner@badminton.vn sang. Tắt bằng APP_DEMO_SECOND_OWNER=false.
 */
@Component
public class DemoOwnerSeeder {

    private static final Logger log = LoggerFactory.getLogger(DemoOwnerSeeder.class);
    public static final String OWNER2_EMAIL = "owner2@badminton.vn";
    private static final String OWNER1_EMAIL = "owner@badminton.vn";
    private static final int VENUES_TO_MOVE = 4;

    private final UserRepository userRepository;
    private final VenueRepository venueRepository;
    private final BookingRepository bookingRepository;
    private final PasswordEncoder passwordEncoder;

    @Value("${app.demo.second-owner:true}")
    private boolean enabled;

    public DemoOwnerSeeder(UserRepository userRepository,
                           VenueRepository venueRepository,
                           BookingRepository bookingRepository,
                           PasswordEncoder passwordEncoder) {
        this.userRepository = userRepository;
        this.venueRepository = venueRepository;
        this.bookingRepository = bookingRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @EventListener(ApplicationReadyEvent.class)
    @Transactional
    public void seed() {
        if (!enabled || userRepository.findByEmailIgnoreCase(OWNER2_EMAIL).isPresent()) return;
        User owner1 = userRepository.findByEmailIgnoreCase(OWNER1_EMAIL).orElse(null);
        if (owner1 == null) return;

        List<Venue> candidates = venueRepository.findByOwnerIdOrderByIdDesc(owner1.getId()).stream()
                .filter(v -> "APPROVED".equals(v.getStatus()))
                .filter(v -> bookingRepository.findByVenueIdOrderByIdDesc(v.getId()).isEmpty())
                .limit(VENUES_TO_MOVE)
                .toList();
        if (candidates.isEmpty()) return;

        String now = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
        User owner2 = userRepository.save(new User(
                "Phạm Chủ Sân 2 (Court Owner)", OWNER2_EMAIL, "0917777888",
                passwordEncoder.encode("123456"), "COURT_OWNER", "KHA", 0.0, true, true, now));
        for (Venue v : candidates) {
            v.setOwnerId(owner2.getId());
            v.setOwnerName(owner2.getFullName());
            venueRepository.save(v);
        }
        log.info("Đã tạo {} và chuyển {} cơ sở: {}", OWNER2_EMAIL, candidates.size(),
                candidates.stream().map(Venue::getName).toList());
    }
}
