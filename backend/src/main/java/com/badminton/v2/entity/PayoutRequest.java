package com.badminton.v2.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "payout_requests")
public class PayoutRequest {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String payoutCode;
    private Long venueId;
    private String venueName;
    private Long ownerId;
    private String ownerName;
    private double grossAmount;
    private double commissionFee;
    private double netPayoutAmount;
    private String bankName;
    private String bankAccountNumber;
    private String bankAccountHolder;
    private String status; // PENDING, APPROVED, PAID, REJECTED
    private String createdAt;
    private String paidAt;

    public PayoutRequest() {}

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getPayoutCode() { return payoutCode; }
    public void setPayoutCode(String payoutCode) { this.payoutCode = payoutCode; }
    public Long getVenueId() { return venueId; }
    public void setVenueId(Long venueId) { this.venueId = venueId; }
    public String getVenueName() { return venueName; }
    public void setVenueName(String venueName) { this.venueName = venueName; }
    public Long getOwnerId() { return ownerId; }
    public void setOwnerId(Long ownerId) { this.ownerId = ownerId; }
    public String getOwnerName() { return ownerName; }
    public void setOwnerName(String ownerName) { this.ownerName = ownerName; }
    public double getGrossAmount() { return grossAmount; }
    public void setGrossAmount(double grossAmount) { this.grossAmount = grossAmount; }
    public double getCommissionFee() { return commissionFee; }
    public void setCommissionFee(double commissionFee) { this.commissionFee = commissionFee; }
    public double getNetPayoutAmount() { return netPayoutAmount; }
    public void setNetPayoutAmount(double netPayoutAmount) { this.netPayoutAmount = netPayoutAmount; }
    public String getBankName() { return bankName; }
    public void setBankName(String bankName) { this.bankName = bankName; }
    public String getBankAccountNumber() { return bankAccountNumber; }
    public void setBankAccountNumber(String bankAccountNumber) { this.bankAccountNumber = bankAccountNumber; }
    public String getBankAccountHolder() { return bankAccountHolder; }
    public void setBankAccountHolder(String bankAccountHolder) { this.bankAccountHolder = bankAccountHolder; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public String getCreatedAt() { return createdAt; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }
    public String getPaidAt() { return paidAt; }
    public void setPaidAt(String paidAt) { this.paidAt = paidAt; }
}
