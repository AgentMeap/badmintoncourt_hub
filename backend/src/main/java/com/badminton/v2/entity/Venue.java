package com.badminton.v2.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "venues")
public class Venue {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long ownerId;
    private String ownerName;
    private String name;
    private String address;
    private double latitude;
    private double longitude;
    @Column(length = 1000)
    private String description;
    private String imageUrl;
    private String openTime;
    private String closeTime;
    private String status; // PENDING, APPROVED, REJECTED, SUSPENDED
    private double commissionRate;
    private double rating;
    private int totalCourts;
    private double basePricePerHour;
    private double peakPricePerHour;
    private String createdAt;

    public Venue() {}

    public Venue(Long ownerId, String ownerName, String name, String address, double latitude, double longitude, String description, String imageUrl, String openTime, String closeTime, String status, double commissionRate, double rating, int totalCourts, double basePricePerHour, double peakPricePerHour, String createdAt) {
        this.ownerId = ownerId;
        this.ownerName = ownerName;
        this.name = name;
        this.address = address;
        this.latitude = latitude;
        this.longitude = longitude;
        this.description = description;
        this.imageUrl = imageUrl;
        this.openTime = openTime;
        this.closeTime = closeTime;
        this.status = status;
        this.commissionRate = commissionRate;
        this.rating = rating;
        this.totalCourts = totalCourts;
        this.basePricePerHour = basePricePerHour;
        this.peakPricePerHour = peakPricePerHour;
        this.createdAt = createdAt;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getOwnerId() { return ownerId; }
    public void setOwnerId(Long ownerId) { this.ownerId = ownerId; }
    public String getOwnerName() { return ownerName; }
    public void setOwnerName(String ownerName) { this.ownerName = ownerName; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getAddress() { return address; }
    public void setAddress(String address) { this.address = address; }
    public double getLatitude() { return latitude; }
    public void setLatitude(double latitude) { this.latitude = latitude; }
    public double getLongitude() { return longitude; }
    public void setLongitude(double longitude) { this.longitude = longitude; }
    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }
    public String getImageUrl() { return imageUrl; }
    public void setImageUrl(String imageUrl) { this.imageUrl = imageUrl; }
    public String getOpenTime() { return openTime; }
    public void setOpenTime(String openTime) { this.openTime = openTime; }
    public String getCloseTime() { return closeTime; }
    public void setCloseTime(String closeTime) { this.closeTime = closeTime; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public double getCommissionRate() { return commissionRate; }
    public void setCommissionRate(double commissionRate) { this.commissionRate = commissionRate; }
    public double getRating() { return rating; }
    public void setRating(double rating) { this.rating = rating; }
    public int getTotalCourts() { return totalCourts; }
    public void setTotalCourts(int totalCourts) { this.totalCourts = totalCourts; }
    public double getBasePricePerHour() { return basePricePerHour; }
    public void setBasePricePerHour(double basePricePerHour) { this.basePricePerHour = basePricePerHour; }
    public double getPeakPricePerHour() { return peakPricePerHour; }
    public void setPeakPricePerHour(double peakPricePerHour) { this.peakPricePerHour = peakPricePerHour; }
    public String getCreatedAt() { return createdAt; }
    public void setCreatedAt(String createdAt) { this.createdAt = createdAt; }
}
