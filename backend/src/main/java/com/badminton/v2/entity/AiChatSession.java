package com.badminton.v2.entity;

import jakarta.persistence.*;

/** Một cuộc trò chuyện với Trợ lý AI của một người dùng (mỗi lúc chỉ có 1 phiên đang mở). */
@Entity
@Table(name = "ai_chat_sessions")
public class AiChatSession {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long userId;
    /** false khi người dùng bấm "Cuộc trò chuyện mới". Nullable để thêm cột an toàn trên SQLite. */
    private Boolean active;
    private String createdAt;
    private String updatedAt;

    public AiChatSession() {}

    public AiChatSession(Long userId, String createdAt) {
        this.userId = userId;
        this.active = true;
        this.createdAt = createdAt;
        this.updatedAt = createdAt;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }
    public boolean isActive() { return active == null || active; }
    public void setActive(boolean active) { this.active = active; }
    public String getCreatedAt() { return createdAt; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }
    public String getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(String updatedAt) { this.updatedAt = updatedAt; }
}
