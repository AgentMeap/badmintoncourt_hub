package com.badminton.v2.entity;

import jakarta.persistence.*;

/**
 * Một tin nhắn trong phiên chat AI.
 * role = USER (người dùng hỏi) hoặc MODEL (trợ lý trả lời).
 * payloadJson (chỉ với MODEL) = {"cards": [...], "quickChips": [...], "inScope": true}.
 */
@Entity
@Table(name = "ai_chat_messages")
public class AiChatMessage {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long sessionId;
    private Long userId;
    private String role;

    @Column(length = 4000)
    private String content;

    @Column(length = 20000)
    private String payloadJson;

    /** "yyyy-MM-dd HH:mm:ss" - so sánh chuỗi được để đếm lượt hỏi theo phút / ngày. */
    private String createdAt;

    public AiChatMessage() {}

    public AiChatMessage(Long sessionId, Long userId, String role, String content, String payloadJson, String createdAt) {
        this.sessionId = sessionId;
        this.userId = userId;
        this.role = role;
        this.content = content;
        this.payloadJson = payloadJson;
        this.createdAt = createdAt;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getSessionId() { return sessionId; }
    public void setSessionId(Long sessionId) { this.sessionId = sessionId; }
    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }
    public String getRole() { return role; }
    public void setRole(String role) { this.role = role; }
    public String getContent() { return content; }
    public void setContent(String content) { this.content = content; }
    public String getPayloadJson() { return payloadJson; }
    public void setPayloadJson(String payloadJson) { this.payloadJson = payloadJson; }
    public String getCreatedAt() { return createdAt; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }
}
