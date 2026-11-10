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
 * Tài khoản demo thêm. Chủ sân thứ hai để trình bày dòng tiền theo từng chủ sân (sân của chủ A -> tiền của chủ A).
 * Chạy sau DataSeeder, kể cả khi database đã có dữ liệu: nếu chưa có owner2@badminton.vn thì tạo
 * và chuyển 4 cơ sở đã duyệt (chưa có vé nào) của owner@badminton.vn sang. Tắt bằng APP_DEMO_SECOND_OWNER=false.
 */
@Component
public class DemoOwnerSeeder {

    private static final Logger log = LoggerFactory.getLogger(DemoOwnerSeeder.class);
    public static final String OWNER2_EMAIL = "owner2@badminton.vn";
    private static final String OWNER1_EMAIL = "owner@badminton.vn";
    private static final int VENUES_TO_MOVE = 4;
    public static final String PLAYER_FEMALE_EMAIL = "lan@badminton.vn";

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
        if (!enabled) return;
        seedPlayers();
        seedSecondOwner();
    }

    /**
     * Người chơi demo: đặt giới tính cho tài khoản mẫu cũ (chưa có) và thêm một người chơi nữ
     * (lan@badminton.vn) để trình bày kèo có giá nam / nữ khác nhau.
     */
    private void seedPlayers() {
        for (String email : List.of("customer@badminton.vn", "hoang@badminton.vn", OWNER1_EMAIL)) {
            userRepository.findByEmailIgnoreCase(email).ifPresent(u -> {
                if (u.getGender() == null) {
                    u.setGender("MALE");
                    userRepository.save(u);
                }
            });
        }
        if (userRepository.findByEmailIgnoreCase(PLAYER_FEMALE_EMAIL).isEmpty()) {
            String now = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
            User lan = new User("Nguyễn Ngọc Lan", PLAYER_FEMALE_EMAIL, "0906555444",
                    passwordEncoder.encode("123456"), "CUSTOMER", "TB_YEU", 300000.0, true, true, now);
            lan.setGender("FEMALE");
            userRepository.save(lan);
            log.info("Đã tạo người chơi nữ demo {}", PLAYER_FEMALE_EMAIL);
        }
    }

    private void seedSecondOwner() {
        if (userRepository.findByEmailIgnoreCase(OWNER2_EMAIL).isPresent()) return;
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
