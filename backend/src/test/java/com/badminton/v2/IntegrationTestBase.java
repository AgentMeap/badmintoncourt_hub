package com.badminton.v2;

import com.badminton.v2.entity.Court;
import com.badminton.v2.entity.User;
import com.badminton.v2.entity.Venue;
import com.badminton.v2.repository.CourtRepository;
import com.badminton.v2.repository.UserRepository;
import com.badminton.v2.repository.VenueRepository;
import com.badminton.v2.security.JwtService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;

/**
 * Nền chung cho test tích hợp: khởi động toàn bộ Spring Boot trên một file SQLite TẠM
 * (không đụng tới badminton_v2.db của máy dev), DataSeeder tự nạp dữ liệu demo.
 * Gọi API qua MockMvc nên đi qua đủ AuthInterceptor (JWT, phân quyền, tài khoản bị khóa).
 */
@SpringBootTest
@AutoConfigureMockMvc
public abstract class IntegrationTestBase {

    /** Một file DB cho cả lần chạy test (mọi lớp test dùng chung một Spring context). */
    private static final String TEST_DB = Path.of(System.getProperty("java.io.tmpdir"),
            "badminton-v2-test-" + UUID.randomUUID() + ".db").toString().replace('\\', '/');

    private static final AtomicInteger SEQ = new AtomicInteger();
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    @DynamicPropertySource
    static void testProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url",
                () -> "jdbc:sqlite:" + TEST_DB + "?journal_mode=WAL&busy_timeout=10000&foreign_keys=ON");
        // Không gọi Gemini thật khi test (máy dev có thể đang đặt GEMINI_API_KEY)
        registry.add("app.gemini.api-key", () -> "");
        registry.add("app.demo-mode", () -> "true");
        // Không gọi PayOS thật khi test (máy dev có thể có key trong application-secret.properties)
        registry.add("app.demo.second-owner", () -> "false");
        registry.add("app.payos.client-id", () -> "");
        registry.add("app.payos.api-key", () -> "");
        registry.add("app.payos.checksum-key", () -> "");
        // Không tải bản đồ đường OSM khi chạy test (RouteApiTest tự nạp lưới đường giả)
        registry.add("app.routing.enabled", () -> "false");
    }

    @Autowired protected MockMvc mvc;
    @Autowired protected ObjectMapper json;
    @Autowired protected UserRepository userRepository;
    @Autowired protected VenueRepository venueRepository;
    @Autowired protected CourtRepository courtRepository;
    @Autowired protected JwtService jwtService;

    // ------------------------------------------------------------------ tài khoản

    protected static final String CUSTOMER = "customer@badminton.vn";
    protected static final String OWNER = "owner@badminton.vn";
    protected static final String ADMIN = "admin@badminton.vn";

    protected User user(String email) {
        return userRepository.findByEmailIgnoreCase(email).orElseThrow();
    }

    protected String tokenOf(String email) {
        return jwtService.issue(user(email));
    }

    protected String tokenOf(User user) {
        return jwtService.issue(user);
    }

    /** Tạo tài khoản mới (email duy nhất) để test không ảnh hưởng lẫn nhau. */
    protected User newUser(String role, double walletBalance) {
        int n = SEQ.incrementAndGet();
        String email = role.toLowerCase() + "-test-" + n + "-" + UUID.randomUUID().toString().substring(0, 6) + "@test.vn";
        return userRepository.save(new User(
                "Test " + role + " " + n, email, "09000000" + String.format("%02d", n % 100),
                "x", role, "TB_YEU", walletBalance, true, true, LocalDateTime.now().format(FMT)));
    }

    // ------------------------------------------------------------------- dữ liệu

    /** Cơ sở đã duyệt của chủ sân demo, kèm danh sách sân. */
    protected Venue ownerApprovedVenue() {
        Long ownerId = user(OWNER).getId();
        return venueRepository.findByOwnerIdOrderByIdDesc(ownerId).stream()
                .filter(v -> "APPROVED".equals(v.getStatus()))
                .reduce((first, second) -> second) // cơ sở tạo sớm nhất
                .orElseThrow();
    }

    protected List<Court> courtsOf(Venue venue) {
        return courtRepository.findByVenueIdOrderByIdAsc(venue.getId());
    }

    // ---------------------------------------------------------------------- HTTP

    protected MockHttpServletRequestBuilder auth(MockHttpServletRequestBuilder req, String token) {
        return token == null ? req : req.header("Authorization", "Bearer " + token);
    }

    protected MockHttpServletRequestBuilder getAs(String token, String url, Object... vars) {
        return auth(get(url, vars), token);
    }

    protected MockHttpServletRequestBuilder postAs(String token, Object body, String url, Object... vars) throws Exception {
        return auth(post(url, vars).contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(body)), token);
    }

    protected MockHttpServletRequestBuilder patchAs(String token, Object body, String url, Object... vars) throws Exception {
        return auth(patch(url, vars).contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(body)), token);
    }

    protected JsonNode body(MvcResult result) throws Exception {
        return json.readTree(result.getResponse().getContentAsString(StandardCharsets.UTF_8));
    }
}
