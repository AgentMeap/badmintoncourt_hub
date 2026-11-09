package com.badminton.v2.service;

import com.badminton.v2.entity.Booking;
import com.badminton.v2.entity.Venue;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;

/**
 * Quy tắc đặt sân dùng chung cho API đặt sân và Trợ lý AI (giống BookingRules ở app Flutter):
 * giá theo giờ, giờ vàng, giữ chỗ còn hạn, giờ mở cửa.
 */
public final class BookingRules {

    /** Từ giờ này là giờ vàng (ngày thường). Cuối tuần luôn tính giờ vàng. */
    public static final int PEAK_START_HOUR = 17;
    public static final int HOLD_MINUTES = 5;
    public static final int FULL_REFUND_HOURS = 24;
    public static final int HALF_REFUND_HOURS = 6;
    public static final int RESCHEDULE_CUTOFF_HOURS = 6;

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static final List<String> INACTIVE = List.of("CANCELLED", "EXPIRED");

    private BookingRules() {
    }

    public static int toMinutes(String hhmm) {
        String[] parts = hhmm.split(":");
        return Integer.parseInt(parts[0]) * 60 + Integer.parseInt(parts[1]);
    }

    public static String hourLabel(int hour) {
        return String.format("%02d:00", hour);
    }

    public static int openMinutes(Venue venue) {
        return toMinutes(venue.getOpenTime() != null ? venue.getOpenTime() : "05:00");
    }

    /** Giờ đóng cửa (phút); đóng <= mở thì coi như mở tới 24:00. */
    public static int closeMinutes(Venue venue) {
        int close = toMinutes(venue.getCloseTime() != null ? venue.getCloseTime() : "23:00");
        return close <= openMinutes(venue) ? 24 * 60 : close;
    }

    public static boolean isPeak(LocalDate date, int hour) {
        DayOfWeek day = date.getDayOfWeek();
        return day == DayOfWeek.SATURDAY || day == DayOfWeek.SUNDAY || hour >= PEAK_START_HOUR;
    }

    /** Tổng tiền các giờ [startHour, endHour). */
    public static double priceFor(Venue venue, LocalDate date, int startHour, int endHour) {
        double total = 0;
        for (int h = startHour; h < endHour; h++) {
            total += isPeak(date, h) ? venue.getPeakPricePerHour() : venue.getBasePricePerHour();
        }
        return total;
    }

    public static double priceFor(Venue venue, String playDate, String start, String end) {
        return priceFor(venue, LocalDate.parse(playDate), toMinutes(start) / 60, toMinutes(end) / 60);
    }

    /** Vé đang giữ chỗ (HELD) và chưa quá hạn thanh toán. */
    public static boolean isHoldActive(Booking b) {
        if (!"HELD".equals(b.getStatus())) return false;
        if (b.getHoldExpiresAt() == null || b.getHoldExpiresAt().isBlank()) return true;
        try {
            return LocalDateTime.now().isBefore(LocalDateTime.parse(b.getHoldExpiresAt(), FMT));
        } catch (Exception e) {
            return true;
        }
    }

    /** Vé còn chiếm sân (bỏ vé đã hủy / hết hạn và giữ chỗ đã quá hạn). */
    public static boolean blocksCourt(Booking b) {
        if (INACTIVE.contains(b.getStatus())) return false;
        return !"HELD".equals(b.getStatus()) || isHoldActive(b);
    }

    /** Hai khoảng giờ [s1, e1) và [s2, e2) (phút) có chồng nhau không. */
    public static boolean overlaps(int s1, int e1, int s2, int e2) {
        return s1 < e2 && e1 > s2;
    }
}
