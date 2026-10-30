package com.badminton.v2.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "otp_tokens")
public class OtpToken {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String email;
    private String otpCode;
    private String purpose; // REGISTER, RESET_PASSWORD, PAYOUT
    private String expiresAt;
    private boolean isUsed;

    public OtpToken() {}

    public OtpToken(String email, String otpCode, String purpose, String expiresAt, boolean isUsed) {
        this.email = email;
        this.otpCode = otpCode;
        this.purpose = purpose;
        this.expiresAt = expiresAt;
        this.isUsed = isUsed;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
    public String getOtpCode() { return otpCode; }
    public void setOtpCode(String otpCode) { this.otpCode = otpCode; }
    public String getPurpose() { return purpose; }
    public void setPurpose(String purpose) { this.purpose = purpose; }
    public String getExpiresAt() { return expiresAt; }
    public void setExpiresAt(String expiresAt) { this.expiresAt = expiresAt; }
    public boolean isUsed() { return isUsed; }
    public void setUsed(boolean used) { isUsed = used; }
}
