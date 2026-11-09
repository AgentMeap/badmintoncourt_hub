package com.badminton.v2.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "reviews")
public class Review {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String bookingCode;
    private Long venueId;
    private String venueName;
    private Long userId;
    private String userName;
    private int rating; // 1 to 5 stars
    private String tags; // e.g. "Mặt sân tốt, Ánh sáng tốt"
    @Column(length = 2000)
    private String comment;
    private String createdAt;

    public Review() {}

    public Review(String bookingCode, Long venueId, String venueName, Long userId, String userName, int rating, String tags, String comment, String createdAt) {
        this.bookingCode = bookingCode;
        this.venueId = venueId;
        this.venueName = venueName;
        this.userId = userId;
        this.userName = userName;
        this.rating = rating;
        this.tags = tags;
        this.comment = comment;
        this.createdAt = createdAt;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getBookingCode() { return bookingCode; }
    public void setBookingCode(String bookingCode) { this.bookingCode = bookingCode; }

    public Long getVenueId() { return venueId; }
    public void setVenueId(Long venueId) { this.venueId = venueId; }

    public String getVenueName() { return venueName; }
    public void setVenueName(String venueName) { this.venueName = venueName; }

    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }

    public String getUserName() { return userName; }
    public void setUserName(String userName) { this.userName = userName; }

    public int getRating() { return rating; }
    public void setRating(int rating) { this.rating = rating; }

    public String getTags() { return tags; }
    public void setTags(String tags) { this.tags = tags; }

    public String getComment() { return comment; }
    public void setComment(String comment) { this.comment = comment; }

    public String getCreatedAt() { return createdAt; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }
}
