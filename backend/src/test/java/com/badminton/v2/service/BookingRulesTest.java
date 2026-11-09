package com.badminton.v2.service;

import com.badminton.v2.entity.Booking;
import com.badminton.v2.entity.Venue;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

import static org.junit.jupiter.api.Assertions.*;

/** Luật giá / giữ chỗ dùng chung cho đặt sân, vãng lai và Trợ lý AI (không cần Spring). */
class BookingRulesTest {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private Venue venue(String open, String close) {
        Venue v = new Venue();
        v.setOpenTime(open);
        v.setCloseTime(close);
        v.setBasePricePerHour(60000);
        v.setPeakPricePerHour(100000);
        return v;
    }

    /** Ngày trong tuần (thứ 2..thứ 6) gần nhất kể từ hôm nay. */
    private LocalDate weekday() {
        LocalDate d = LocalDate.now();
        while (d.getDayOfWeek().getValue() >= 6) d = d.plusDays(1);
        return d;
    }

    @Test
    void peakHoursAndWeekend() {
        LocalDate wd = weekday();
        assertFalse(BookingRules.isPeak(wd, 16));
        assertTrue(BookingRules.isPeak(wd, BookingRules.PEAK_START_HOUR));
        LocalDate saturday = wd.plusDays(6 - wd.getDayOfWeek().getValue());
        assertTrue(BookingRules.isPeak(saturday, 8));
    }

    @Test
    void priceSplitsNormalAndPeakHours() {
        Venue v = venue("05:00", "23:00");
        String date = weekday().toString();
        // 16:00-18:00 = 1 giờ thường + 1 giờ vàng
        assertEquals(160000, BookingRules.priceFor(v, date, "16:00", "18:00"), 0.01);
        assertEquals(120000, BookingRules.priceFor(v, date, "08:00", "10:00"), 0.01);
        assertEquals(0, BookingRules.priceFor(v, date, "10:00", "10:00"), 0.01);
    }

    @Test
    void openingHoursAndMidnightClose() {
        assertEquals(5 * 60, BookingRules.openMinutes(venue("05:00", "23:00")));
        assertEquals(23 * 60, BookingRules.closeMinutes(venue("05:00", "23:00")));
        // Đóng cửa 00:00 (<= giờ mở) được hiểu là 24:00
        assertEquals(24 * 60, BookingRules.closeMinutes(venue("06:00", "00:00")));
        assertEquals("07:00", BookingRules.hourLabel(7));
        assertEquals(19 * 60 + 30, BookingRules.toMinutes("19:30"));
    }

    @Test
    void holdExpiryAndCourtBlocking() {
        Booking active = new Booking();
        active.setStatus("HELD");
        active.setHoldExpiresAt(LocalDateTime.now().plusMinutes(3).format(FMT));
        assertTrue(BookingRules.isHoldActive(active));
        assertTrue(BookingRules.blocksCourt(active));

        Booking expired = new Booking();
        expired.setStatus("HELD");
        expired.setHoldExpiresAt(LocalDateTime.now().minusMinutes(1).format(FMT));
        assertFalse(BookingRules.isHoldActive(expired));
        assertFalse(BookingRules.blocksCourt(expired));

        Booking cancelled = new Booking();
        cancelled.setStatus("CANCELLED");
        assertFalse(BookingRules.blocksCourt(cancelled));

        Booking confirmed = new Booking();
        confirmed.setStatus("CONFIRMED");
        assertTrue(BookingRules.blocksCourt(confirmed));
    }

    @Test
    void overlap() {
        assertTrue(BookingRules.overlaps(18 * 60, 20 * 60, 19 * 60, 21 * 60));
        assertFalse(BookingRules.overlaps(18 * 60, 20 * 60, 20 * 60, 22 * 60));
    }
}
