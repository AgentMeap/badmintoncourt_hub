package com.badminton.v2.service;

import com.badminton.v2.entity.Booking;
import com.badminton.v2.repository.BookingRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;

@Component
public class BookingHoldScheduler {

    private static final Logger log = LoggerFactory.getLogger(BookingHoldScheduler.class);
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final BookingRepository bookingRepository;
    private final NotificationService notificationService;

    public BookingHoldScheduler(BookingRepository bookingRepository, NotificationService notificationService) {
        this.bookingRepository = bookingRepository;
        this.notificationService = notificationService;
    }

    @Scheduled(fixedRate = 30000)
    @Transactional
    public void releaseExpiredHeldBookings() {
        List<Booking> heldBookings = bookingRepository.findByStatus("HELD");
        LocalDateTime now = LocalDateTime.now();
        for (Booking b : heldBookings) {
            if (b.getHoldExpiresAt() != null && !b.getHoldExpiresAt().isBlank()) {
                try {
                    LocalDateTime exp = LocalDateTime.parse(b.getHoldExpiresAt(), FMT);
                    if (now.isAfter(exp)) {
                        b.setStatus("EXPIRED");
                        bookingRepository.save(b);
                        log.info("Released expired HELD booking {} on court {}", b.getBookingCode(), b.getCourtName());
                        if (b.getCustomerId() != null) {
                            notificationService.notifyUser(
                                    b.getCustomerId(),
                                    "Hết thời gian giữ chỗ đặt sân",
                                    "Đơn giữ chỗ " + b.getBookingCode() + " (" + b.getVenueName() + " - " + b.getCourtName() + ") đã hết hạn 5 phút chờ thanh toán.",
                                    "BOOKING",
                                    "S12",
                                    b.getId()
                            );
                        }
                    }
                } catch (Exception ignored) {
                }
            }
        }
    }
}
