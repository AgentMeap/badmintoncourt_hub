package com.badminton.v2.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "notifications")
public class NotificationItem {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long userId;
    private String title;
    @Column(length = 1000)
    private String body;
    private String type; // BOOKING, PAYMENT, MATCHMAKING, SYSTEM
    private String targetScreen; // S13, S15, S18, S21, S23...
    private Long referenceId;
    private boolean isRead;
    private String createdAt;

    public NotificationItem() {}

    public NotificationItem(Long userId, String title, String body, String type, String targetScreen, Long referenceId, boolean isRead, String createdAt) {
        this.userId = userId;
        this.title = title;
        this.body = body;
        this.type = type;
        this.targetScreen = targetScreen;
        this.referenceId = referenceId;
        this.isRead = isRead;
        this.createdAt = createdAt;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public String getBody() { return body; }
    public void setBody(String body) { this.body = body; }
    public String getType() { return type; }
    public void setType(String type) { this.type = type; }
    public String getTargetScreen() { return targetScreen; }
    public void setTargetScreen(String targetScreen) { this.targetScreen = targetScreen; }
    public Long getReferenceId() { return referenceId; }
    public void setReferenceId(Long referenceId) { this.referenceId = referenceId; }
    public boolean isRead() { return isRead; }
    public void setRead(boolean read) { isRead = read; }
    public String getCreatedAt() { return createdAt; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }
}
