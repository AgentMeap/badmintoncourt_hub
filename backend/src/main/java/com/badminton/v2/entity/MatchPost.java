package com.badminton.v2.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "match_posts")
public class MatchPost {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long hostId;
    private String hostName;
    private String hostSkill;
    private Long bookingId; // Optional or linked
    private Long venueId;
    private String venueName;
    private String venueAddress;
    private String courtName;
    private String title;
    private String playDate;
    private String startTime;
    private String endTime;
    private String requiredSkill; // NEWBIE, TB_YEU, TRUNG_BINH, KHA, ALL
    private int maxPlayers;
    private int currentPlayers;
    private double feePerPlayer;
    private String status; // OPEN, FULL, COMPLETED, CANCELLED
    private String createdAt;

    public MatchPost() {}

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getHostId() { return hostId; }
    public void setHostId(Long hostId) { this.hostId = hostId; }
    public String getHostName() { return hostName; }
    public void setHostName(String hostName) { this.hostName = hostName; }
    public String getHostSkill() { return hostSkill; }
    public void setHostSkill(String hostSkill) { this.hostSkill = hostSkill; }
    public Long getBookingId() { return bookingId; }
    public void setBookingId(Long bookingId) { this.bookingId = bookingId; }
    public Long getVenueId() { return venueId; }
    public void setVenueId(Long venueId) { this.venueId = venueId; }
    public String getVenueName() { return venueName; }
    public void setVenueName(String venueName) { this.venueName = venueName; }
    public String getVenueAddress() { return venueAddress; }
    public void setVenueAddress(String venueAddress) { this.venueAddress = venueAddress; }
    public String getCourtName() { return courtName; }
    public void setCourtName(String courtName) { this.courtName = courtName; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public String getPlayDate() { return playDate; }
    public void setPlayDate(String playDate) { this.playDate = playDate; }
    public String getStartTime() { return startTime; }
    public void setStartTime(String startTime) { this.startTime = startTime; }
    public String getEndTime() { return endTime; }
    public void setEndTime(String endTime) { this.endTime = endTime; }
    public String getRequiredSkill() { return requiredSkill; }
    public void setRequiredSkill(String requiredSkill) { this.requiredSkill = requiredSkill; }
    public int getMaxPlayers() { return maxPlayers; }
    public void setMaxPlayers(int maxPlayers) { this.maxPlayers = maxPlayers; }
    public int getCurrentPlayers() { return currentPlayers; }
    public void setCurrentPlayers(int currentPlayers) { this.currentPlayers = currentPlayers; }
    public double getFeePerPlayer() { return feePerPlayer; }
    public void setFeePerPlayer(double feePerPlayer) { this.feePerPlayer = feePerPlayer; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public String getCreatedAt() { return createdAt; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }
}
