package com.badminton.v2.entity;

import jakarta.persistence.*;

/** Tin nhắn trong nhóm chat của một kèo giao lưu (chủ kèo + thành viên đã duyệt). */
@Entity
@Table(name = "match_messages")
public class MatchMessage {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long matchId;
    private Long userId;
    private String userName;
    @Column(length = 500)
    private String content;
    private String createdAt;

    public MatchMessage() {}

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getMatchId() { return matchId; }
    public void setMatchId(Long matchId) { this.matchId = matchId; }
    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }
    public String getUserName() { return userName; }
    public void setUserName(String userName) { this.userName = userName; }
    public String getContent() { return content; }
    public void setContent(String content) { this.content = content; }
    public String getCreatedAt() { return createdAt; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }
}
