package com.badminton.v2;

import com.badminton.v2.entity.Court;
import com.badminton.v2.entity.PayoutRequest;
import com.badminton.v2.entity.User;
import com.badminton.v2.entity.Venue;
import com.badminton.v2.repository.PayoutRequestRepository;
import com.badminton.v2.service.BookingRules;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Giai đoạn 5: dashboard chủ sân / Admin, lịch theo ngày, vãng lai, kiểm duyệt, giải ngân. */
class OwnerAdminTest extends IntegrationTestBase {

    @Autowired
    private PayoutRequestRepository payoutRequestRepository;

    private Map<String, Object> walkIn(Venue venue, Court court, LocalDate date, String start, String end) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("venueId", venue.getId());
        body.put("courtId", court.getId());
        body.put("bookingType", "WALK_IN");
        body.put("customerName", "Khách vãng lai: Test");
        body.put("playDate", date.toString());
        body.put("startTime", start);
        body.put("endTime", end);
        body.put("totalPrice", 1); // máy chủ phải tự tính giá
        return body;
    }

    @Test
    @DisplayName("Dashboard chủ sân có số liệu hôm nay, 7 ngày, từng cơ sở và tiền giải ngân nhất quán")
    void ownerDashboard() throws Exception {
        var d = body(mvc.perform(getAs(tokenOf(OWNER), "/api/owner/{id}/dashboard", user(OWNER).getId()))
                .andExpect(status().isOk()).andReturn());
        assertTrue(d.path("today").has("revenue"));
        assertTrue(d.path("today").has("occupancyPercent"));
        assertEquals(7, d.path("last7Days").size());
        assertEquals(LocalDate.now().toString(), d.path("last7Days").get(6).path("date").asText());
        assertEquals(d.path("venues").size(), d.path("venueStats").size());

        double gross = d.path("availablePayoutGross").asDouble();
        double net = d.path("availableNetPayout").asDouble();
        assertEquals(gross - Math.round(gross * 0.05), net, 0.01);
    }

    @Test
    @DisplayName("Lịch một cơ sở theo ngày: chủ sân xem được, chủ sân khác / người chơi bị chặn, ngày sai -> 400")
    void venueBookingsOfDay() throws Exception {
        Venue venue = ownerApprovedVenue();
        String owner = tokenOf(OWNER);

        var res = body(mvc.perform(getAs(owner, "/api/owner/venues/{id}/bookings", venue.getId())
                        .param("date", LocalDate.now().toString()))
                .andExpect(status().isOk()).andReturn());
        assertEquals(LocalDate.now().toString(), res.path("playDate").asText());
        assertEquals(courtsOf(venue).size(), res.path("courts").size());
        assertTrue(res.path("bookings").isArray());
        assertTrue(res.path("summary").has("revenue"));

        mvc.perform(getAs(owner, "/api/owner/venues/{id}/bookings", venue.getId()).param("date", "30-02-2026"))
                .andExpect(status().isBadRequest());

        User otherOwner = newUser("COURT_OWNER", 0);
        mvc.perform(getAs(tokenOf(otherOwner), "/api/owner/venues/{id}/bookings", venue.getId()))
                .andExpect(status().isForbidden());
        mvc.perform(getAs(tokenOf(CUSTOMER), "/api/owner/venues/{id}/bookings", venue.getId()))
                .andExpect(status().isForbidden());
        // Admin xem được mọi cơ sở
        mvc.perform(getAs(tokenOf(ADMIN), "/api/owner/venues/{id}/bookings", venue.getId()))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("Vãng lai: giá do máy chủ tính, hiện trong lịch ngày; ngoài giờ mở cửa -> 400; trùng -> 409")
    void walkInBooking() throws Exception {
        Venue venue = ownerApprovedVenue();
        Court court = courtsOf(venue).get(0);
        LocalDate date = LocalDate.now().plusDays(16);
        String owner = tokenOf(OWNER);

        var saved = body(mvc.perform(postAs(owner, walkIn(venue, court, date, "17:00", "19:00"), "/api/owner/bookings/walk-in"))
                .andExpect(status().isOk()).andReturn());
        assertEquals(BookingRules.priceFor(venue, date.toString(), "17:00", "19:00"),
                saved.path("totalPrice").asDouble(), 0.01);
        assertEquals("CASH", saved.path("paymentMethod").asText());

        var day = body(mvc.perform(getAs(owner, "/api/owner/venues/{id}/bookings", venue.getId())
                        .param("date", date.toString()))
                .andExpect(status().isOk()).andReturn());
        boolean found = false;
        for (var b : day.path("bookings")) {
            if (b.path("id").asLong() == saved.path("id").asLong()) found = true;
        }
        assertTrue(found, "Vé vãng lai phải có trong lịch ngày");

        mvc.perform(postAs(owner, walkIn(venue, court, date, "18:00", "20:00"), "/api/owner/bookings/walk-in"))
                .andExpect(status().isConflict());
        mvc.perform(postAs(owner, walkIn(venue, court, date, "02:00", "04:00"), "/api/owner/bookings/walk-in"))
                .andExpect(status().isBadRequest());
        mvc.perform(postAs(tokenOf(newUser("COURT_OWNER", 0)), walkIn(venue, court, date, "06:00", "07:00"),
                        "/api/owner/bookings/walk-in"))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("Kiểm duyệt cơ sở: từ chối cần lý do, chỉ chuyển trạng thái hợp lệ")
    void venueModeration() throws Exception {
        String admin = tokenOf(ADMIN);
        Venue pending = venueRepository.save(new Venue(
                user(OWNER).getId(), "Chủ sân test", "Sân test kiểm duyệt", "Địa chỉ test", 10.87, 106.80,
                "Mô tả", null, "05:00", "23:00", "PENDING", 0.05, 0, 4, 60000.0, 100000.0,
                LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"))));

        mvc.perform(patchAs(admin, Map.of("status", "REJECTED"), "/api/admin/venues/{id}/status", pending.getId()))
                .andExpect(status().isBadRequest());
        mvc.perform(patchAs(admin, Map.of("status", "SUSPENDED"), "/api/admin/venues/{id}/status", pending.getId()))
                .andExpect(status().isConflict());

        var rejected = body(mvc.perform(patchAs(admin, Map.of("status", "REJECTED", "reason", "Thiếu bảng giá"),
                        "/api/admin/venues/{id}/status", pending.getId()))
                .andExpect(status().isOk()).andReturn());
        assertEquals("REJECTED", rejected.path("status").asText());

        mvc.perform(patchAs(admin, Map.of("status", "REJECTED", "reason", "Lần 2"),
                        "/api/admin/venues/{id}/status", pending.getId()))
                .andExpect(status().isConflict());
        mvc.perform(patchAs(admin, Map.of("status", "APPROVED"), "/api/admin/venues/{id}/status", pending.getId()))
                .andExpect(status().isOk());
        mvc.perform(patchAs(tokenOf(OWNER), Map.of("status", "APPROVED"), "/api/admin/venues/{id}/status", pending.getId()))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("Duyệt giải ngân: chỉ xử lý 1 lần, từ chối cần lý do, trạng thái lạ -> 400")
    void payoutDecision() throws Exception {
        String admin = tokenOf(ADMIN);
        User owner = user(OWNER);
        PayoutRequest pr = new PayoutRequest();
        pr.setPayoutCode("PO-TEST-" + System.nanoTime() % 100000);
        pr.setVenueId(ownerApprovedVenue().getId());
        pr.setVenueName("Test");
        pr.setOwnerId(owner.getId());
        pr.setOwnerName(owner.getFullName());
        pr.setGrossAmount(100000);
        pr.setCommissionFee(5000);
        pr.setNetPayoutAmount(95000);
        pr.setBankName("Vietcombank");
        pr.setBankAccountNumber("0071001234567");
        pr.setBankAccountHolder("TEST");
        pr.setStatus("PENDING");
        pr.setCreatedAt(LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")));
        pr = payoutRequestRepository.save(pr);

        mvc.perform(patchAs(admin, Map.of("status", "DONE"), "/api/admin/payout-requests/{id}/status", pr.getId()))
                .andExpect(status().isBadRequest());
        mvc.perform(patchAs(admin, Map.of("status", "REJECTED"), "/api/admin/payout-requests/{id}/status", pr.getId()))
                .andExpect(status().isBadRequest());

        var paid = body(mvc.perform(patchAs(admin, Map.of("status", "PAID"), "/api/admin/payout-requests/{id}/status", pr.getId()))
                .andExpect(status().isOk()).andReturn());
        assertEquals("PAID", paid.path("status").asText());
        assertFalse(paid.path("paidAt").asText().isBlank());

        mvc.perform(patchAs(admin, Map.of("status", "REJECTED", "reason", "Thử lại"),
                        "/api/admin/payout-requests/{id}/status", pr.getId()))
                .andExpect(status().isConflict());
    }

    @Test
    @DisplayName("Yêu cầu giải ngân vượt doanh thu online còn lại -> 400")
    void payoutRequestOverLimit() throws Exception {
        var d = body(mvc.perform(getAs(tokenOf(OWNER), "/api/owner/{id}/dashboard", user(OWNER).getId()))
                .andExpect(status().isOk()).andReturn());
        double available = d.path("availablePayoutGross").asDouble();

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("grossAmount", available + 1_000_000);
        body.put("bankName", "Vietcombank");
        body.put("bankAccountNumber", "0071001234567");
        body.put("bankAccountHolder", "TRAN CHU SAN");
        body.put("otpCode", "123456");
        mvc.perform(postAs(tokenOf(OWNER), body, "/api/owner/payout-requests"))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("Dashboard Admin: GMV 7 ngày, người dùng theo vai trò, không lộ mật khẩu")
    void adminDashboard() throws Exception {
        var res = mvc.perform(getAs(tokenOf(ADMIN), "/api/admin/dashboard")).andExpect(status().isOk()).andReturn();
        var d = body(res);
        assertEquals(7, d.path("gmvLast7Days").size());
        assertTrue(d.path("usersByRole").path("CUSTOMER").asInt() >= 1);
        assertTrue(d.path("users").isArray());
        assertFalse(res.getResponse().getContentAsString().contains("passwordHash"));
    }
}
