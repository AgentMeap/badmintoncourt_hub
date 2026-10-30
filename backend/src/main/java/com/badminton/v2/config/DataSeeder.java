package com.badminton.v2.config;

import com.badminton.v2.entity.*;
import com.badminton.v2.repository.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.CommandLineRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;

@Component
public class DataSeeder implements CommandLineRunner {

    private static final Logger log = LoggerFactory.getLogger(DataSeeder.class);
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final UserRepository userRepository;
    private final VenueRepository venueRepository;
    private final CourtRepository courtRepository;
    private final PricingRuleRepository pricingRuleRepository;
    private final BookingRepository bookingRepository;
    private final PaymentRepository paymentRepository;
    private final WalletTransactionRepository walletTransactionRepository;
    private final PayoutRequestRepository payoutRequestRepository;
    private final MatchPostRepository matchPostRepository;
    private final MatchParticipantRepository matchParticipantRepository;
    private final NotificationRepository notificationRepository;
    private final PasswordEncoder passwordEncoder;

    public DataSeeder(UserRepository userRepository,
                      VenueRepository venueRepository,
                      CourtRepository courtRepository,
                      PricingRuleRepository pricingRuleRepository,
                      BookingRepository bookingRepository,
                      PaymentRepository paymentRepository,
                      WalletTransactionRepository walletTransactionRepository,
                      PayoutRequestRepository payoutRequestRepository,
                      MatchPostRepository matchPostRepository,
                      MatchParticipantRepository matchParticipantRepository,
                      NotificationRepository notificationRepository,
                      PasswordEncoder passwordEncoder) {
        this.userRepository = userRepository;
        this.venueRepository = venueRepository;
        this.courtRepository = courtRepository;
        this.pricingRuleRepository = pricingRuleRepository;
        this.bookingRepository = bookingRepository;
        this.paymentRepository = paymentRepository;
        this.walletTransactionRepository = walletTransactionRepository;
        this.payoutRequestRepository = payoutRequestRepository;
        this.matchPostRepository = matchPostRepository;
        this.matchParticipantRepository = matchParticipantRepository;
        this.notificationRepository = notificationRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @Override
    public void run(String... args) {
        if (userRepository.count() > 0) {
            log.info("SQLite database already seeded ({} users).", userRepository.count());
            return;
        }

        String now = LocalDateTime.now().format(FMT);
        String today = LocalDate.now().toString();
        String hash = passwordEncoder.encode("123456");

        // 1. Seed Users (3 Core Roles + Extra Community Players)
        User customer = userRepository.save(new User(
                "Nguyễn Hữu Đạt (Customer)", "customer@badminton.vn", "0909123456",
                hash, "CUSTOMER", "TB_YEU", 350000.0, true, true, now
        ));
        User owner = userRepository.save(new User(
                "Trần Chủ Sân (Court Owner)", "owner@badminton.vn", "0918888999",
                hash, "COURT_OWNER", "KHA", 1500000.0, true, true, now
        ));
        User admin = userRepository.save(new User(
                "Quản Trị Viên (Platform Admin)", "admin@badminton.vn", "0988777666",
                hash, "ADMIN", "KHA", 0.0, true, true, now
        ));
        User player2 = userRepository.save(new User(
                "Lê Minh Hoàng", "hoang@badminton.vn", "0903222333",
                hash, "CUSTOMER", "TRUNG_BINH", 180000.0, true, true, now
        ));

        // Wallet Transactions for Customer
        walletTransactionRepository.save(new WalletTransaction(
                customer.getId(), "Hoàn tiền 100% hủy vé #BK-202601 (Trước 24h)", 240000.0, "REFUND", 350000.0, now
        ));
        walletTransactionRepository.save(new WalletTransaction(
                customer.getId(), "Nạp tiền khởi tạo Ví Cầu Lông", 110000.0, "TOPUP", 110000.0, now
        ));

        // 2. Seed Venues: 20 APPROVED + 1 PENDING quanh Nhà Văn Hóa Sinh Viên (Làng ĐH Quốc Gia TP.HCM)
        Venue v1 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân CLB TDTT ĐH Thể Dục Thể Thao TP.HCM",
                "Khuôn viên ĐH Thể Dục Thể Thao, KP.6, P. Linh Trung, TP. Thủ Đức",
                10.8682, 106.7975,
                "Nhà thi đấu trường ĐH TDTT, 6 sân thảm Yonex tiêu chuẩn thi đấu, trần cao 12m, thông gió tự nhiên, bãi đỗ xe rộng rãi.",
                "https://images.unsplash.com/photo-1541534741688-6078c6bfb5c5?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.9, 6, 60000.0, 100000.0, now
        ));
        Venue v2 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông TPT Sport Làng Đại Học",
                "Đường Tôn Thất Tùng, P. Đông Hòa, TP. Dĩ An (Cạnh KTX Khu B)",
                10.8805, 106.7925,
                "Điểm hẹn cầu lông sinh viên quen thuộc nhất Làng ĐH. 6 sân thảm đệm êm, ánh sáng chuẩn chống chói, giá cực kỳ ưu đãi.",
                "https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.8, 6, 50000.0, 90000.0, now
        ));
        Venue v3 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông ĐH Nông Lâm TP.HCM",
                "Khuôn viên ĐH Nông Lâm, Quốc lộ 1A, P. Linh Trung, TP. Thủ Đức",
                10.8702, 106.7891,
                "Cụm sân trong nhà thoáng mát, sàn thi đấu đạt chuẩn thể thao học đường, phục vụ sinh viên và cán bộ giảng viên.",
                "https://images.unsplash.com/photo-1574629810360-7efbbe195018?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.7, 4, 55000.0, 95000.0, now
        ));
        Venue v4 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông KTX Khu B ĐHQG",
                "Đường Tô Vĩnh Diện, P. Đông Hòa, TP. Dĩ An, Bình Dương",
                10.8832, 106.7820,
                "Khu thể thao đa năng KTX Khu B, không gian trẻ trung sôi động, chuyên tổ chức các giải đấu phong trào sinh viên.",
                "https://images.unsplash.com/photo-1521537634581-0dced2fee2ef?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.7, 4, 45000.0, 80000.0, now
        ));
        Venue v5 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông Ao An (Bình An)",
                "1015 Mỹ Phước - Tân Vạn, P. Bình An, TP. Dĩ An, Bình Dương",
                10.8872, 106.8123,
                "5 sân thảm mới tinh, sạch sẽ, bãi đỗ xe máy & ô tô thuận tiện ngay mặt tiền đường lớn.",
                "https://images.unsplash.com/photo-1613918108466-292b78a8ef95?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.8, 5, 60000.0, 100000.0, now
        ));
        Venue v6 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông Aurora Sport Linh Trung",
                "158 Đường số 17, P. Linh Trung, TP. Thủ Đức",
                10.8641, 106.7832,
                "Tổ hợp thể thao hiện đại, 6 sân thảm cao cấp có khán đài mini, phòng tắm nóng lạnh và quầy nước giải khát tiện nghi.",
                "https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.9, 6, 70000.0, 110000.0, now
        ));
        Venue v7 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông Lan Anh Linh Trung",
                "119 Đường số 7, P. Linh Trung, TP. Thủ Đức",
                10.8622, 106.7815,
                "6 sân thảm Yonex chống trượt, trần cao không gian thoáng mát, chuyên mở các lớp hướng dẫn kỹ thuật cầu lông.",
                "https://images.unsplash.com/photo-1517649763962-0c623266ddc0?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.8, 6, 65000.0, 105000.0, now
        ));
        Venue v8 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông Đông Hòa Dĩ An",
                "93 Nguyễn Công Hoan, P. Đông Hòa, TP. Dĩ An, Bình Dương",
                10.8885, 106.7865,
                "Sân trải thảm PVC chất lượng cao, không gian sáng sủa, mức giá bình dân phù hợp học sinh sinh viên.",
                "https://images.unsplash.com/photo-1562771242-a02d9090c90c?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.7, 6, 55000.0, 95000.0, now
        ));
        Venue v9 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông Gia Hân Dĩ An",
                "80 Võ Thị Sáu, P. Đông Hòa, TP. Dĩ An, Bình Dương",
                10.8906, 106.7822,
                "Đại cụm 15 sân quy mô lớn nhất khu vực Dĩ An - Làng ĐH. Thảm thi đấu tiêu chuẩn quốc gia, mở cửa linh hoạt 24/7.",
                "https://images.unsplash.com/photo-1612872087720-bb876e2e67d1?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.9, 15, 50000.0, 90000.0, now
        ));
        Venue v10 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông TH Badminton",
                "166 Võ Thị Sáu, KP. Tây A, P. Đông Hòa, TP. Dĩ An",
                10.8924, 106.7786,
                "Sân mới đầu tư hiện đại bậc nhất giáp ranh Làng ĐH. Thảm chống trượt BWF, trần cao thoáng đãng, hệ thống đèn LED bảo vệ mắt.",
                "https://images.unsplash.com/photo-1587280501635-68a0e82cd5ff?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.9, 8, 60000.0, 110000.0, now
        ));
        Venue v11 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông HL Sport Dĩ An",
                "Đường Nguyễn Du, P. Đông Hòa, TP. Dĩ An, Bình Dương",
                10.8951, 106.7812,
                "Thiết kế hiện đại, sạch sẽ, khu vực nhà chờ máy lạnh, quầy phụ kiện và dịch vụ căng vợt lấy liền chuyên nghiệp.",
                "https://images.unsplash.com/photo-1599474924187-334a4ae5bd3c?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.8, 6, 60000.0, 100000.0, now
        ));
        Venue v12 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông Hải Anh Linh Xuân",
                "174 Đường số 8, P. Linh Xuân, TP. Thủ Đức",
                10.8718, 106.7726,
                "Sân mới đi vào hoạt động, mặt thảm đẹp sạch sẽ, không gian thoáng đãng, vị trí thuận tiện đi lại từ Làng ĐH.",
                "https://images.unsplash.com/photo-1622163642998-1ea32b0bbc67?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.7, 4, 55000.0, 90000.0, now
        ));
        Venue v13 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông Đồng Giao Linh Xuân",
                "25 Đường số 11, KP. 4, P. Linh Xuân, TP. Thủ Đức",
                10.8732, 106.7691,
                "Cụm 4 sân gần chợ Linh Xuân, điểm giao lưu thân quen của các tay vợt sinh viên và dân công sở buổi tối.",
                "https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.7, 4, 50000.0, 85000.0, now
        ));
        Venue v14 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông 68 Linh Xuân",
                "Quốc Lộ 1K (Sau Kim Hạnh II), P. Linh Xuân, TP. Thủ Đức",
                10.8781, 106.7682,
                "5 sân có hệ thống phun sương làm mát mái tôn mùa hè, bãi xe cực rộng đỗ được ô tô và xe tải miễn phí.",
                "https://images.unsplash.com/photo-1521537634581-0dced2fee2ef?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.8, 5, 50000.0, 90000.0, now
        ));
        Venue v15 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông Thảo Nguyên",
                "5/115B Xa Lộ Hà Nội, P. Linh Trung, TP. Thủ Đức",
                10.8552, 106.7854,
                "Không gian thể thao ấm cúng, phù hợp nhóm bạn thân thuê sân riêng tập luyện kỹ chiến thuật.",
                "https://images.unsplash.com/photo-1613918108466-292b78a8ef95?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.6, 4, 60000.0, 100000.0, now
        ));
        Venue v16 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông SHB Badminton",
                "127 Lê Văn Chí, P. Linh Trung, TP. Thủ Đức",
                10.8584, 106.7721,
                "Hệ thống thể thao quy mô khủng 18 sân đạt chuẩn, gần Ngã tư Thủ Đức, tổ chức nhiều giải đấu quy mô sinh viên.",
                "https://images.unsplash.com/photo-1574629810360-7efbbe195018?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.9, 12, 65000.0, 120000.0, now
        ));
        Venue v17 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông Lan Phương",
                "22 Đường số 5, P. Linh Trung, TP. Thủ Đức",
                10.8592, 106.7684,
                "Gần trục đường Hoàng Diệu 2, mặt sân sạch sẽ, ánh sáng tốt, có cộng đồng ghép kèo hoạt động đều đặn mỗi ngày.",
                "https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.7, 4, 60000.0, 100000.0, now
        ));
        Venue v18 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông UTE (ĐH Sư Phạm Kỹ Thuật)",
                "01 Võ Văn Ngân, P. Linh Chiểu, TP. Thủ Đức",
                10.8512, 106.7725,
                "Nhà thi đấu ĐH Sư Phạm Kỹ Thuật, sàn gỗ & thảm thi đấu chuẩn đại học, điểm hẹn của cộng đồng sinh viên Thủ Đức.",
                "https://images.unsplash.com/photo-1541534741688-6078c6bfb5c5?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.8, 5, 60000.0, 100000.0, now
        ));
        Venue v19 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông Rạng Đông",
                "07 Einstein, P. Bình Thọ, TP. Thủ Đức",
                10.8491, 106.7652,
                "Cụm sân trung tâm làng đại học Thủ Đức cũ, thảm PVC tiêu chuẩn, không gian sạch sẽ thoáng mát.",
                "https://images.unsplash.com/photo-1612872087720-bb876e2e67d1?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.8, 4, 70000.0, 115000.0, now
        ));
        Venue v20 = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông An Bình Dĩ An",
                "Đường Nguyễn Viết Xuân, P. An Bình, TP. Dĩ An, Bình Dương",
                10.8821, 106.7584,
                "Cụm 5 sân cầu lông khu vực An Bình, thảm đẹp bám chân, giá vé học sinh - sinh viên cực kỳ cạnh tranh.",
                "https://images.unsplash.com/photo-1517649763962-0c623266ddc0?w=800",
                "05:00", "23:00", "APPROVED", 0.05, 4.7, 5, 55000.0, 95000.0, now
        ));
        Venue vPending = venueRepository.save(new Venue(
                owner.getId(), owner.getFullName(),
                "Sân Cầu Lông TH Badminton Cơ sở 2 (Làng ĐH)",
                "Đường Vành Đai ĐHQG, P. Đông Hòa, TP. Dĩ An, Bình Dương",
                10.8790, 106.8045,
                "Cơ sở mới xây dựng 6 sân VIP máy lạnh cạnh KTX Khu A, đang gửi hồ sơ chờ Admin phê duyệt lên bản đồ nền tảng.",
                "https://images.unsplash.com/photo-1587280501635-68a0e82cd5ff?w=800",
                "05:00", "23:00", "PENDING", 0.05, 5.0, 6, 75000.0, 125000.0, now
        ));

        // 3. Seed Courts & Pricing Rules cho toàn bộ 21 cơ sở
        List<Venue> allVenues = List.of(
                v1, v2, v3, v4, v5, v6, v7, v8, v9, v10,
                v11, v12, v13, v14, v15, v16, v17, v18, v19, v20,
                vPending
        );
        Court v1Court1 = null;
        Court v1Court2 = null;
        Court v1Court4 = null;
        for (Venue v : allVenues) {
            for (int i = 1; i <= v.getTotalCourts(); i++) {
                Court c = courtRepository.save(new Court(v.getId(), "Sân " + i, i <= 2 ? "VIP" : "STANDARD", true));
                if (v.getId().equals(v1.getId())) {
                    if (i == 1) v1Court1 = c;
                    if (i == 2) v1Court2 = c;
                    if (i == 4) v1Court4 = c;
                }
            }
            pricingRuleRepository.save(new PricingRule(v.getId(), "ALL", "05:00", "17:00", v.getBasePricePerHour()));
            pricingRuleRepository.save(new PricingRule(v.getId(), "ALL", "17:00", "23:00", v.getPeakPricePerHour()));
        }

        // 4. Seed Bookings (Online CONFIRMED, WALK_IN, MAINTENANCE)
        Booking bOnline = new Booking();
        bOnline.setBookingCode("BK-202610");
        bOnline.setVenueId(v1.getId());
        bOnline.setVenueName(v1.getName());
        bOnline.setCourtId(v1Court2.getId());
        bOnline.setCourtName(v1Court2.getName());
        bOnline.setCustomerId(customer.getId());
        bOnline.setCustomerName(customer.getFullName());
        bOnline.setCustomerPhone(customer.getPhone());
        bOnline.setBookingType("ONLINE");
        bOnline.setPlayDate(today);
        bOnline.setStartTime("18:00");
        bOnline.setEndTime("20:00");
        bOnline.setTotalPrice(240000.0);
        bOnline.setStatus("CONFIRMED");
        bOnline.setRescheduledCount(0);
        bOnline.setQrCheckInToken("QR-BK-202610");
        bOnline.setPaymentMethod("PAYOS_QR");
        bOnline.setCreatedAt(now);
        bOnline = bookingRepository.save(bOnline);

        Payment p1 = new Payment();
        p1.setBookingId(bOnline.getId());
        p1.setBookingCode(bOnline.getBookingCode());
        p1.setPayosOrderCode(902841L);
        p1.setPaymentMethod("PAYOS_QR");
        p1.setAmount(240000.0);
        p1.setStatus("PAID");
        p1.setPaidAt(now);
        p1.setCreatedAt(now);
        paymentRepository.save(p1);

        Booking bWalkIn = new Booking();
        bWalkIn.setBookingCode("WI-889012");
        bWalkIn.setVenueId(v1.getId());
        bWalkIn.setVenueName(v1.getName());
        bWalkIn.setCourtId(v1Court1.getId());
        bWalkIn.setCourtName(v1Court1.getName());
        bWalkIn.setCustomerName("Khách vãng lai: Anh Tuấn");
        bWalkIn.setCustomerPhone("0912333444");
        bWalkIn.setBookingType("WALK_IN");
        bWalkIn.setPlayDate(today);
        bWalkIn.setStartTime("17:00");
        bWalkIn.setEndTime("19:00");
        bWalkIn.setTotalPrice(240000.0);
        bWalkIn.setStatus("CONFIRMED");
        bWalkIn.setQrCheckInToken("QR-WI-889012");
        bWalkIn.setPaymentMethod("CASH");
        bWalkIn.setCreatedAt(now);
        bookingRepository.save(bWalkIn);

        Booking bMaint = new Booking();
        bMaint.setBookingCode("MT-550123");
        bMaint.setVenueId(v1.getId());
        bMaint.setVenueName(v1.getName());
        bMaint.setCourtId(v1Court4.getId());
        bMaint.setCourtName(v1Court4.getName());
        bMaint.setCustomerName("Bảo trì thay lưới & vệ sinh thảm");
        bMaint.setCustomerPhone("-");
        bMaint.setBookingType("MAINTENANCE");
        bMaint.setPlayDate(today);
        bMaint.setStartTime("18:00");
        bMaint.setEndTime("20:00");
        bMaint.setTotalPrice(0.0);
        bMaint.setStatus("CONFIRMED");
        bMaint.setQrCheckInToken("QR-MT-550123");
        bMaint.setPaymentMethod("NONE");
        bMaint.setCreatedAt(now);
        bookingRepository.save(bMaint);

        // 5. Seed Matchmaking Posts & Participants (Luồng 5)
        MatchPost m1 = new MatchPost();
        m1.setHostId(customer.getId());
        m1.setHostName(customer.getFullName());
        m1.setHostSkill(customer.getSkillLevel());
        m1.setBookingId(bOnline.getId());
        m1.setVenueId(v1.getId());
        m1.setVenueName(v1.getName());
        m1.setVenueAddress(v1.getAddress());
        m1.setCourtName("Sân 2");
        m1.setTitle("Giao lưu vui vẻ tối nay - Tuyển thêm 2 bạn nam/nữ đánh đôi");
        m1.setPlayDate(today);
        m1.setStartTime("18:00");
        m1.setEndTime("20:00");
        m1.setRequiredSkill("TB_YEU");
        m1.setMaxPlayers(6);
        m1.setCurrentPlayers(4);
        m1.setFeePerPlayer(65000.0);
        m1.setStatus("OPEN");
        m1.setCreatedAt(now);
        m1 = matchPostRepository.save(m1);

        MatchParticipant mp1 = new MatchParticipant();
        mp1.setMatchId(m1.getId());
        mp1.setUserId(player2.getId());
        mp1.setUserName(player2.getFullName());
        mp1.setUserSkill(player2.getSkillLevel());
        mp1.setUserPhone(player2.getPhone());
        mp1.setStatus("PENDING");
        mp1.setJoinedAt(now);
        matchParticipantRepository.save(mp1);

        MatchPost m2 = new MatchPost();
        m2.setHostId(player2.getId());
        m2.setHostName(player2.getFullName());
        m2.setHostSkill(player2.getSkillLevel());
        m2.setVenueId(v2.getId());
        m2.setVenueName(v2.getName());
        m2.setVenueAddress(v2.getAddress());
        m2.setCourtName("Sân 3");
        m2.setTitle("Kèo trình độ Trung Bình - Cầu Hải Yến S70");
        m2.setPlayDate(today);
        m2.setStartTime("19:00");
        m2.setEndTime("21:00");
        m2.setRequiredSkill("TRUNG_BINH");
        m2.setMaxPlayers(8);
        m2.setCurrentPlayers(5);
        m2.setFeePerPlayer(75000.0);
        m2.setStatus("OPEN");
        m2.setCreatedAt(now);
        matchPostRepository.save(m2);

        // 6. Seed Payout Request (Luồng 3)
        PayoutRequest pr = new PayoutRequest();
        pr.setPayoutCode("PO-202689");
        pr.setVenueId(v1.getId());
        pr.setVenueName(v1.getName());
        pr.setOwnerId(owner.getId());
        pr.setOwnerName(owner.getFullName());
        pr.setGrossAmount(2000000.0);
        pr.setCommissionFee(100000.0);
        pr.setNetPayoutAmount(1900000.0);
        pr.setBankName("Vietcombank");
        pr.setBankAccountNumber("0071001234567");
        pr.setBankAccountHolder("TRAN CHU SAN");
        pr.setStatus("PENDING");
        pr.setCreatedAt(now);
        payoutRequestRepository.save(pr);

        // 7. Seed Notifications (Module 5)
        notificationRepository.save(new NotificationItem(
                customer.getId(),
                "Thanh toán PayOS VietQR thành công (#BK-202610)",
                "Vé đặt Sân 2 (18:00-20:00) tại Sân Cầu Lông Viettel Quận 10 đã sẵn sàng. Bấm để mở mã QR Check-in.",
                "PAYMENT", "S13", bOnline.getId(), false, now
        ));
        notificationRepository.save(new NotificationItem(
                customer.getId(),
                "Có người xin tham gia Kèo giao lưu của bạn!",
                "Lê Minh Hoàng (Trình độ: TRUNG_BINH) vừa gửi yêu cầu tham gia kèo tối nay của bạn.",
                "MATCHMAKING", "S15", m1.getId(), false, now
        ));
        notificationRepository.save(new NotificationItem(
                customer.getId(),
                "Hoàn tiền hủy sân +240.000đ vào Ví Cầu Lông",
                "Đã hoàn 100% giá trị vé #BK-202601 vào Ví nội bộ của bạn.",
                "BOOKING", "S18", customer.getId(), true, now
        ));

        log.info("Seeded Badminton V2 SQLite database successfully!");
    }
}
