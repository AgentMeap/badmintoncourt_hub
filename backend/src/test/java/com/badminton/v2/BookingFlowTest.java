package com.badminton.v2;

import com.badminton.v2.entity.Court;
import com.badminton.v2.entity.User;
import com.badminton.v2.entity.Venue;
import com.badminton.v2.service.BookingRules;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Giai đoạn 2: giữ chỗ, trùng lịch, trả chỗ, thanh toán bằng Ví. */
class BookingFlowTest extends IntegrationTestBase {

    private Map<String, Object> slot(Venue venue, Court court, LocalDate date, String start, String end) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("venueId", venue.getId());
        body.put("courtId", court.getId());
        body.put("playDate", date.toString());
        body.put("startTime", start);
        body.put("endTime", end);
        body.put("totalPrice", 1); // giá app gửi lên phải bị bỏ qua
        return body;
    }

    @Test
    @DisplayName("Giữ chỗ: giá do máy chủ tính, trùng giờ -> 409, trả chỗ xong người khác giữ được")
    void holdConflictAndRelease() throws Exception {
        Venue venue = ownerApprovedVenue();
        Court court = courtsOf(venue).get(1);
        LocalDate date = LocalDate.now().plusDays(12);
        User first = newUser("CUSTOMER", 0);
        User second = newUser("CUSTOMER", 0);

        var held = body(mvc.perform(postAs(tokenOf(first), slot(venue, court, date, "18:00", "20:00"), "/api/bookings/hold"))
                .andExpect(status().isOk()).andReturn());
        assertEquals("HELD", held.path("status").asText());
        assertEquals(first.getId().longValue(), held.path("customerId").asLong());
        assertEquals(BookingRules.priceFor(venue, date.toString(), "18:00", "20:00"),
                held.path("totalPrice").asDouble(), 0.01);

        // Chồng một phần giờ (19:00-21:00) trên cùng sân -> 409
        mvc.perform(postAs(tokenOf(second), slot(venue, court, date, "19:00", "21:00"), "/api/bookings/hold"))
                .andExpect(status().isConflict());

        // Người khác không trả chỗ hộ được
        mvc.perform(postAs(tokenOf(second), Map.of(), "/api/bookings/{id}/release", held.path("id").asLong()))
                .andExpect(status().is4xxClientError());

        mvc.perform(postAs(tokenOf(first), Map.of(), "/api/bookings/{id}/release", held.path("id").asLong()))
                .andExpect(status().isOk());
        mvc.perform(postAs(tokenOf(second), slot(venue, court, date, "19:00", "21:00"), "/api/bookings/hold"))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("Khung giờ sai: quá khứ, lẻ phút, ngoài giờ mở cửa -> 400")
    void invalidSlotsRejected() throws Exception {
        Venue venue = ownerApprovedVenue();
        Court court = courtsOf(venue).get(0);
        String token = tokenOf(newUser("CUSTOMER", 0));

        mvc.perform(postAs(token, slot(venue, court, LocalDate.now().minusDays(1), "18:00", "19:00"), "/api/bookings/hold"))
                .andExpect(status().isBadRequest());
        mvc.perform(postAs(token, slot(venue, court, LocalDate.now().plusDays(13), "18:30", "19:30"), "/api/bookings/hold"))
                .andExpect(status().isBadRequest());
        mvc.perform(postAs(token, slot(venue, court, LocalDate.now().plusDays(13), "02:00", "03:00"), "/api/bookings/hold"))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("Thanh toán Ví: trừ đúng số dư, vé CONFIRMED; trả lần 2 bị chặn; Ví không đủ -> 400")
    void payWithWallet() throws Exception {
        Venue venue = ownerApprovedVenue();
        Court court = courtsOf(venue).get(2);
        LocalDate date = LocalDate.now().plusDays(14);
        User rich = newUser("CUSTOMER", 5_000_000);
        String token = tokenOf(rich);

        var held = body(mvc.perform(postAs(token, slot(venue, court, date, "08:00", "10:00"), "/api/bookings/hold"))
                .andExpect(status().isOk()).andReturn());
        long bookingId = held.path("id").asLong();
        double price = held.path("totalPrice").asDouble();

        var paid = body(mvc.perform(postAs(token, Map.of("bookingId", bookingId), "/api/payments/pay-with-wallet"))
                .andExpect(status().isOk()).andReturn());
        assertEquals("CONFIRMED", paid.path("booking").path("status").asText());
        assertEquals(5_000_000 - price, paid.path("walletBalance").asDouble(), 0.01);

        mvc.perform(postAs(token, Map.of("bookingId", bookingId), "/api/payments/pay-with-wallet"))
                .andExpect(status().isConflict());

        // Ví 0đ
        String poor = tokenOf(newUser("CUSTOMER", 0));
        var held2 = body(mvc.perform(postAs(poor, slot(venue, court, date, "10:00", "11:00"), "/api/bookings/hold"))
                .andExpect(status().isOk()).andReturn());
        mvc.perform(postAs(poor, Map.of("bookingId", held2.path("id").asLong()), "/api/payments/pay-with-wallet"))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("Không xem được vé của người khác")
    void bookingDetailIsPrivate() throws Exception {
        Venue venue = ownerApprovedVenue();
        Court court = courtsOf(venue).get(3 % courtsOf(venue).size());
        User owner = newUser("CUSTOMER", 0);
        var held = body(mvc.perform(postAs(tokenOf(owner), slot(venue, court, LocalDate.now().plusDays(15), "06:00", "07:00"),
                        "/api/bookings/hold"))
                .andExpect(status().isOk()).andReturn());

        mvc.perform(getAs(tokenOf(newUser("CUSTOMER", 0)), "/api/bookings/{id}", held.path("id").asLong()))
                .andExpect(status().isForbidden());
        mvc.perform(getAs(tokenOf(owner), "/api/bookings/{id}", held.path("id").asLong()))
                .andExpect(status().isOk());
        // Chủ sân của cơ sở xem được
        mvc.perform(getAs(tokenOf(OWNER), "/api/bookings/{id}", held.path("id").asLong()))
                .andExpect(status().isOk());
    }
}
