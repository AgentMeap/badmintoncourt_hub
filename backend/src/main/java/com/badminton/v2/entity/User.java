package com.badminton.v2.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;

@Entity
@Table(name = "users")
public class User {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String fullName;

    @Column(unique = true, nullable = false)
    private String email;

    private String phone;
    private String passwordHash;
    private String role; // CUSTOMER, COURT_OWNER, ADMIN
    private String skillLevel; // NEWBIE, TB_YEU, TRUNG_BINH, KHA
    private double walletBalance;
    private String introVideoUrl;
    private boolean isVerified;
    private boolean isActive;
    /** Ảnh đại diện (lấy từ tài khoản Google khi đăng nhập bằng Google). */
    private String avatarUrl;
    /**
     * false = tài khoản tạo bằng Google, chưa tự đặt mật khẩu (null = tài khoản cũ, coi như có).
     * Nullable để SQLite thêm được cột vào bảng đã có dữ liệu.
     */
    private Boolean localPassword;
    private String createdAt;

    public User() {}

    public User(String fullName, String email, String phone, String passwordHash, String role, String skillLevel, double walletBalance, boolean isVerified, boolean isActive, String createdAt) {
        this.fullName = fullName;
        this.email = email;
        this.phone = phone;
        this.passwordHash = passwordHash;
        this.role = role;
        this.skillLevel = skillLevel;
        this.walletBalance = walletBalance;
        this.isVerified = isVerified;
        this.isActive = isActive;
        this.createdAt = createdAt;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getFullName() { return fullName; }
    public void setFullName(String fullName) { this.fullName = fullName; }
    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
    public String getPhone() { return phone; }
    public void setPhone(String phone) { this.phone = phone; }
    @JsonIgnore
    public String getPasswordHash() { return passwordHash; }
    public void setPasswordHash(String passwordHash) { this.passwordHash = passwordHash; }
    public String getRole() { return role; }
    public void setRole(String role) { this.role = role; }
    public String getSkillLevel() { return skillLevel; }
    public void setSkillLevel(String skillLevel) { this.skillLevel = skillLevel; }
    public double getWalletBalance() { return walletBalance; }
    public void setWalletBalance(double walletBalance) { this.walletBalance = walletBalance; }
    public String getIntroVideoUrl() { return introVideoUrl; }
    public void setIntroVideoUrl(String introVideoUrl) { this.introVideoUrl = introVideoUrl; }
    public boolean isVerified() { return isVerified; }
    public void setVerified(boolean verified) { isVerified = verified; }
    public boolean isActive() { return isActive; }
    public String getAvatarUrl() { return avatarUrl; }
    public void setAvatarUrl(String avatarUrl) { this.avatarUrl = avatarUrl; }
    public boolean hasLocalPassword() { return localPassword == null || localPassword; }
    public void setLocalPassword(Boolean localPassword) { this.localPassword = localPassword; }
    public void setActive(boolean active) { isActive = active; }
    public String getCreatedAt() { return createdAt; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }
}
