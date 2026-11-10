package com.badminton.v2;

import com.badminton.v2.entity.Booking;
import com.badminton.v2.entity.Court;
import com.badminton.v2.entity.User;
import com.badminton.v2.entity.Venue;
import com.badminton.v2.repository.BookingRepository;
import com.fasterxml.jackson.databind.JsonNode;
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

/** Dòng tiền: vé hủy muộn vẫn tính phần giữ lại cho chủ sân, Admin thấy tiền nền tảng đang giữ, chặn tự đăng ký Admin. */
class PlatformCashflowTest extends IntegrationTestBase {

    @Autowired private BookingRepository bookingRepository;

    private JsonNode ownerDashboard() throws Exception {
        return body(mvc.perform(getAs(tokenOf(OWNER), "/api/owner/{id}/dashboard", user(OWNER).getId()))
                .andExpect(status().isOk()).andReturn());
    }

    /** Giữ chỗ + trả bằng Ví, trả về vé đã CONFIRMED. */
    private Booking paidBooking(User customer, String start, String end) throws Exception {
        Venue venue = ownerApprovedVenue();
        Court court = courtsOf(venue).get(3);
        Map<String, Object> slot = new LinkedHashMap<>();
        slot.put("venueId", venue.getId());
        slot.put("courtId", court.getId());
        slot.put("playDate", LocalDate.now().plusDays(13).toString());
        slot.put("startTime", start);
        slot.put("endTime", end);
        long id = body(mvc.perform(postAs(tokenOf(customer), slot, "/api/bookings/hold"))
                .andExpect(status().isOk()).andReturn()).path("id").asLong();
        mvc.perform(postAs(tokenOf(customer), Map.of("bookingId", id), "/api/payments/pay-with-wallet"))
                .andExpect(status().isOk());
        return bookingRepository.findById(id).orElseThrow();
    }

    @Test
    @DisplayName("Hủy vé trong 6–24h: khách nhận 50%, chủ sân giữ 50% trong doanh thu được giải ngân")
    void lateCancelRetainedForOwner() throws Exception {
        User customer = newUser("CUSTOMER", 5_000_000);
        Booking b = paidBooking(customer, "06:00", "08:00");
        double price = b.getTotalPrice();

        // Dời giờ chơi về khoảng 12 tiếng nữa để rơi vào mốc hoàn 50%
        LocalDateTime play = LocalDateTime.now().plusHours(12);
        b.setPlayDate(play.toLocalDate().toString());
        b.setStartTime(play.format(DateTimeFormatter.ofPattern("HH:mm")));
        bookingRepository.save(b);

        JsonNode before = ownerDashboard();
        var cancel = body(mvc.perform(postAs(tokenOf(customer), Map.of("reason", "test"), "/api/bookings/{id}/cancel", b.getId()))
                .andExpect(status().isOk()).andReturn());
        assertNotNull(cancel);
        JsonNode after = ownerDashboard();

        Booking cancelled = bookingRepository.findById(b.getId()).orElseThrow();
        assertEquals("CANCELLED", cancelled.getStatus());
        assertEquals(price / 2, cancelled.getRetainedAmount(), 1.0);
        assertEquals(5_000_000 - price + Math.round(price / 2),
                userRepository.findById(customer.getId()).orElseThrow().getWalletBalance(), 1.0);

        // Doanh thu online chủ sân: trước đó đã gồm cả vé, sau khi hủy chỉ còn phần giữ lại
        assertEquals(before.path("onlineGrossRevenue").asDouble() - price / 2,
                after.path("onlineGrossRevenue").asDouble(), 1.0);
        // Tiền có thể rút không âm (các test khác có thể đã xin rút hết)
        assertEquals(Math.max(0, before.path("availablePayoutGross").asDouble() - price / 2),
                after.path("availablePayoutGross").asDouble(), 1.0);
        // Phí sàn chỉ tính trên tiền online
        assertEquals(Math.round(after.path("onlineGrossRevenue").asDouble() * 0.05),
                after.path("commissionFee").asDouble(), 1.0);
    }

    @Test
    @DisplayName("Hủy trước 24h: hoàn 100%, chủ sân không giữ gì")
    void earlyCancelRetainsNothing() throws Exception {
        User customer = newUser("CUSTOMER", 5_000_000);
        Booking b = paidBooking(customer, "08:00", "09:00");
        mvc.perform(postAs(tokenOf(customer), Map.of(), "/api/bookings/{id}/cancel", b.getId())).andExpect(status().isOk());
        assertEquals(0.0, bookingRepository.findById(b.getId()).orElseThrow().getRetainedAmount(), 0.001);
        assertEquals(5_000_000, userRepository.findById(customer.getId()).orElseThrow().getWalletBalance(), 0.01);
    }

    @Test
    @DisplayName("Admin thấy dòng tiền nền tảng")
    void adminCashflow() throws Exception {
        JsonNode cf = body(mvc.perform(getAs(tokenOf(ADMIN), "/api/admin/dashboard"))
                .andExpect(status().isOk()).andReturn()).path("cashflow");
        for (String k : new String[]{"ownerOnlineRevenue", "payoutPaidNet", "platformFeeEarned", "payoutPendingNet",
                "ownerUnrequested", "userWalletTotal", "heldMatchDeposits", "platformHolding"}) {
            assertTrue(cf.has(k), k);
        }
        assertTrue(cf.path("platformHolding").asDouble() >= cf.path("userWalletTotal").asDouble());
    }

    @Test
    @DisplayName("Không tự đăng ký được tài khoản Admin")
    void cannotRegisterAdmin() throws Exception {
        String email = "hacker" + System.nanoTime() + "@test.vn";
        mvc.perform(postAs(null, Map.of("email", email, "password", "123456", "fullName", "X", "role", "ADMIN"),
                "/api/auth/register")).andExpect(status().isBadRequest());
        assertTrue(userRepository.findByEmailIgnoreCase(email).isEmpty());
        mvc.perform(postAs(null, Map.of("email", "o" + email, "password", "123456", "fullName", "Chủ sân", "role", "COURT_OWNER"),
                "/api/auth/register")).andExpect(status().isOk());
    }
}
