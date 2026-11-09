package com.badminton.v2.entity;

import jakarta.persistence.*;

/** Thành viên đánh giá chủ kèo sau khi kèo kết thúc (mỗi người 1 đánh giá / kèo, sửa được trong 7 ngày). */
@Entity
@Table(name = "host_reviews")
public class HostReview {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long matchId;
    private String matchTitle;
    private Long hostId;
    private Long raterId;
    private String raterName;
    private int rating; // 1..5
    /** Trình độ nhóm so với mô tả: ACCURATE | HIGHER | LOWER. */
    private String skillAccuracy;
    /** Các nhãn, nối bằng ", ". */
    private String tags;
    @Column(length = 300)
    private String comment;
    private String createdAt;
    private String updatedAt;

    public HostReview() {}

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getMatchId() { return matchId; }
    public void setMatchId(Long matchId) { this.matchId = matchId; }
    public String getMatchTitle() { return matchTitle; }
    public void setMatchTitle(String matchTitle) { this.matchTitle = matchTitle; }
    public Long getHostId() { return hostId; }
    public void setHostId(Long hostId) { this.hostId = hostId; }
    public Long getRaterId() { return raterId; }
    public void setRaterId(Long raterId) { this.raterId = raterId; }
    public String getRaterName() { return raterName; }
    public void setRaterName(String raterName) { this.raterName = raterName; }
    public int getRating() { return rating; }
    public void setRating(int rating) { this.rating = rating; }
    public String getSkillAccuracy() { return skillAccuracy; }
    public void setSkillAccuracy(String skillAccuracy) { this.skillAccuracy = skillAccuracy; }
    public String getTags() { return tags; }
    public void setTags(String tags) { this.tags = tags; }
    public String getComment() { return comment; }
    public void setComment(String comment) { this.comment = comment; }
    public String getCreatedAt() { return createdAt; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }
    public String getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(String updatedAt) { this.updatedAt = updatedAt; }
}
