package com.badminton.v2.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "wallet_transactions")
public class WalletTransaction {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long userId;
    private String title;
    private double amount; // positive or negative
    private String type; // REFUND, BOOKING_PAYMENT, TOPUP, WITHDRAW
    private double balanceAfter;
    private String createdAt;

    public WalletTransaction() {}

    public WalletTransaction(Long userId, String title, double amount, String type, double balanceAfter, String createdAt) {
        this.userId = userId;
        this.title = title;
        this.amount = amount;
        this.type = type;
        this.balanceAfter = balanceAfter;
        this.createdAt = createdAt;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public double getAmount() { return amount; }
    public void setAmount(double amount) { this.amount = amount; }
    public String getType() { return type; }
    public void setType(String type) { this.type = type; }
    public double getBalanceAfter() { return balanceAfter; }
    public void setBalanceAfter(double balanceAfter) { this.balanceAfter = balanceAfter; }
    public String getCreatedAt() { return createdAt; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }
}
