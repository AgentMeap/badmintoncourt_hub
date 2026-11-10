package com.badminton.v2.entity;

import jakarta.persistence.*;

/** Trạng thái đọc nhóm chat của một thành viên trong một kèo: tin đã đọc tới đâu, lúc nào đang mở chat, có tắt thông báo không. */
@Entity
@Table(name = "match_chat_reads")
public class MatchChatRead {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long matchId;
    private Long userId;
    /** Id tin nhắn mới nhất đã đọc (0 = chưa đọc tin nào). */
    private Long lastReadMessageId;
    /** Lần cuối app hỏi tin (khung chat đang mở), dạng yyyy-MM-dd HH:mm:ss. */
    private String lastSeenAt;
    /** Tắt thông báo nhóm chat của kèo này. */
    private Boolean muted;

    public MatchChatRead() {}

    public MatchChatRead(Long matchId, Long userId) {
        this.matchId = matchId;
        this.userId = userId;
        this.lastReadMessageId = 0L;
        this.muted = false;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getMatchId() { return matchId; }
    public void setMatchId(Long matchId) { this.matchId = matchId; }
    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }
    public Long getLastReadMessageId() { return lastReadMessageId == null ? 0L : lastReadMessageId; }
    public void setLastReadMessageId(Long lastReadMessageId) { this.lastReadMessageId = lastReadMessageId; }
    public String getLastSeenAt() { return lastSeenAt; }
    public void setLastSeenAt(String lastSeenAt) { this.lastSeenAt = lastSeenAt; }
    public boolean isMuted() { return Boolean.TRUE.equals(muted); }
    public void setMuted(Boolean muted) { this.muted = muted; }
}
