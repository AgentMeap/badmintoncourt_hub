package com.badminton.v2.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "match_participants")
public class MatchParticipant {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long matchId;
    private Long userId;
    private String userName;
    private String userSkill;
    private String userPhone;
    private String status; // PENDING, APPROVED, REJECTED
    private String joinedAt;

    public MatchParticipant() {}

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getMatchId() { return matchId; }
    public void setMatchId(Long matchId) { this.matchId = matchId; }
    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }
    public String getUserName() { return userName; }
    public void setUserName(String userName) { this.userName = userName; }
    public String getUserSkill() { return userSkill; }
    public void setUserSkill(String userSkill) { this.userSkill = userSkill; }
    public String getUserPhone() { return userPhone; }
    public void setUserPhone(String userPhone) { this.userPhone = userPhone; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public String getJoinedAt() { return joinedAt; }
    public void setJoinedAt(String joinedAt) { this.joinedAt = joinedAt; }
}
