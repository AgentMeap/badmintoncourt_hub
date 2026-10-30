package com.badminton.v2.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "pricing_rules")
public class PricingRule {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long venueId;
    private String dayType; // WEEKDAY, WEEKEND
    private String startTime; // 05:00
    private String endTime; // 17:00
    private double pricePerHour;

    public PricingRule() {}

    public PricingRule(Long venueId, String dayType, String startTime, String endTime, double pricePerHour) {
        this.venueId = venueId;
        this.dayType = dayType;
        this.startTime = startTime;
        this.endTime = endTime;
        this.pricePerHour = pricePerHour;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getVenueId() { return venueId; }
    public void setVenueId(Long venueId) { this.venueId = venueId; }
    public String getDayType() { return dayType; }
    public void setDayType(String dayType) { this.dayType = dayType; }
    public String getStartTime() { return startTime; }
    public void setStartTime(String startTime) { this.startTime = startTime; }
    public String getEndTime() { return endTime; }
    public void setEndTime(String endTime) { this.endTime = endTime; }
    public double getPricePerHour() { return pricePerHour; }
    public void setPricePerHour(double pricePerHour) { this.pricePerHour = pricePerHour; }
}
