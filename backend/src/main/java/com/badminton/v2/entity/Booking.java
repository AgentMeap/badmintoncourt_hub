package com.badminton.v2.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "bookings")
public class Booking {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(unique = true)
    private String bookingCode;

    private Long venueId;
    private String venueName;
    private Long courtId;
    private String courtName;
    private Long customerId; // Nullable if WALK_IN
    private String customerName;
    private String customerPhone;
    private String bookingType; // ONLINE, WALK_IN, MAINTENANCE
    private String playDate; // YYYY-MM-DD
    private String startTime; // HH:mm
    private String endTime; // HH:mm
    private double totalPrice;
    private String status; // HELD, CONFIRMED, CHECKED_IN, COMPLETED, CANCELLED, EXPIRED
    private String holdExpiresAt;
    private int rescheduledCount;
    private String qrCheckInToken;
    private String paymentMethod; // PAYOS_QR, WALLET, CASH
    private String createdAt;

    public Booking() {}

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getBookingCode() { return bookingCode; }
    public void setBookingCode(String bookingCode) { this.bookingCode = bookingCode; }
    public Long getVenueId() { return venueId; }
    public void setVenueId(Long venueId) { this.venueId = venueId; }
    public String getVenueName() { return venueName; }
    public void setVenueName(String venueName) { this.venueName = venueName; }
    public Long getCourtId() { return courtId; }
    public void setCourtId(Long courtId) { this.courtId = courtId; }
    public String getCourtName() { return courtName; }
    public void setCourtName(String courtName) { this.courtName = courtName; }
    public Long getCustomerId() { return customerId; }
    public void setCustomerId(Long customerId) { this.customerId = customerId; }
    public String getCustomerName() { return customerName; }
    public void setCustomerName(String customerName) { this.customerName = customerName; }
    public String getCustomerPhone() { return customerPhone; }
    public void setCustomerPhone(String customerPhone) { this.customerPhone = customerPhone; }
    public String getBookingType() { return bookingType; }
    public void setBookingType(String bookingType) { this.bookingType = bookingType; }
    public String getPlayDate() { return playDate; }
    public void setPlayDate(String playDate) { this.playDate = playDate; }
    public String getStartTime() { return startTime; }
    public void setStartTime(String startTime) { this.startTime = startTime; }
    public String getEndTime() { return endTime; }
    public void setEndTime(String endTime) { this.endTime = endTime; }
    public double getTotalPrice() { return totalPrice; }
    public void setTotalPrice(double totalPrice) { this.totalPrice = totalPrice; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public String getHoldExpiresAt() { return holdExpiresAt; }
    public void setHoldExpiresAt(String holdExpiresAt) { this.holdExpiresAt = holdExpiresAt; }
    public int getRescheduledCount() { return rescheduledCount; }
    public void setRescheduledCount(int rescheduledCount) { this.rescheduledCount = rescheduledCount; }
    public String getQrCheckInToken() { return qrCheckInToken; }
    public void setQrCheckInToken(String qrCheckInToken) { this.qrCheckInToken = qrCheckInToken; }
    public String getPaymentMethod() { return paymentMethod; }
    public void setPaymentMethod(String paymentMethod) { this.paymentMethod = paymentMethod; }
    public String getCreatedAt() { return createdAt; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }
}
