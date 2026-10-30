package com.badminton.v2.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "courts")
public class Court {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long venueId;
    private String name; // Sân 1, Sân 2...
    private String courtType; // STANDARD, VIP
    private boolean isActive;

    public Court() {}

    public Court(Long venueId, String name, String courtType, boolean isActive) {
        this.venueId = venueId;
        this.name = name;
        this.courtType = courtType;
        this.isActive = isActive;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public Long getVenueId() { return venueId; }
    public void setVenueId(Long venueId) { this.venueId = venueId; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getCourtType() { return courtType; }
    public void setCourtType(String courtType) { this.courtType = courtType; }
    public boolean isActive() { return isActive; }
    public void setActive(boolean active) { isActive = active; }
}
