package com.badminton.v2.entity;

import jakarta.persistence.*;

/** Mã thiết bị FCM của người dùng (mỗi điện thoại một mã) để gửi thông báo đẩy. */
@Entity
@Table(name = "device_tokens")
public class DeviceToken {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long userId;
    @Column(length = 512, unique = true)
    private String token;
    /** ANDROID / IOS / WEB */
    private String platform;
    private String updatedAt;

    public DeviceToken() {}

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }
    public String getToken() { return token; }
    public void setToken(String token) { this.token = token; }
    public String getPlatform() { return platform; }
    public void setPlatform(String platform) { this.platform = platform; }
    public String getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(String updatedAt) { this.updatedAt = updatedAt; }
}
