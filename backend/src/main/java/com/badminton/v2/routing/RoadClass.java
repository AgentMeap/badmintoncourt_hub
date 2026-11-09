package com.badminton.v2.routing;

import java.util.HashMap;
import java.util.Map;

/**
 * Loại đường OSM (thẻ highway) và tốc độ trung bình trong đô thị TP.HCM (km/h).
 * Tốc độ 0 = phương tiện đó không được đi (VD xe máy không vào cao tốc).
 */
public enum RoadClass {
    MOTORWAY("motorway", 0, 70, 0, "đường cao tốc"),
    MOTORWAY_LINK("motorway_link", 0, 40, 0, "nhánh cao tốc"),
    TRUNK("trunk", 40, 50, 4.5, "quốc lộ"),
    TRUNK_LINK("trunk_link", 30, 30, 4.5, "đường nhánh"),
    PRIMARY("primary", 35, 35, 4.5, "đường chính"),
    PRIMARY_LINK("primary_link", 25, 25, 4.5, "đường nhánh"),
    SECONDARY("secondary", 30, 30, 4.5, "đường"),
    SECONDARY_LINK("secondary_link", 25, 25, 4.5, "đường nhánh"),
    TERTIARY("tertiary", 28, 25, 4.5, "đường"),
    TERTIARY_LINK("tertiary_link", 22, 20, 4.5, "đường nhánh"),
    UNCLASSIFIED("unclassified", 24, 20, 4.5, "đường không tên"),
    RESIDENTIAL("residential", 22, 18, 4.5, "hẻm"),
    LIVING_STREET("living_street", 12, 10, 4.5, "hẻm"),
    SERVICE("service", 15, 10, 4.5, "đường nội bộ"),
    ROAD("road", 20, 18, 4.5, "đường"),
    TRACK("track", 12, 10, 4.5, "đường đất"),
    PEDESTRIAN("pedestrian", 0, 0, 4.5, "phố đi bộ"),
    FOOTWAY("footway", 0, 0, 4.5, "lối đi bộ"),
    PATH("path", 0, 0, 4.5, "lối đi bộ"),
    CYCLEWAY("cycleway", 0, 0, 4.5, "lối đi bộ"),
    STEPS("steps", 0, 0, 2.5, "cầu thang");

    public final String tag;
    private final double motorbikeKmh;
    private final double carKmh;
    private final double walkKmh;
    /** Cách gọi khi đường không có tên. */
    public final String generic;

    RoadClass(String tag, double motorbikeKmh, double carKmh, double walkKmh, String generic) {
        this.tag = tag;
        this.motorbikeKmh = motorbikeKmh;
        this.carKmh = carKmh;
        this.walkKmh = walkKmh;
        this.generic = generic;
    }

    public double speedKmh(TravelMode mode) {
        return switch (mode) {
            case MOTORBIKE -> motorbikeKmh;
            case CAR -> carKmh;
            case WALK -> walkKmh;
        };
    }

    public boolean isLink() {
        return tag.endsWith("_link");
    }

    private static final Map<String, RoadClass> BY_TAG = new HashMap<>();

    static {
        for (RoadClass c : values()) BY_TAG.put(c.tag, c);
    }

    /** null nếu thẻ highway không phải đường đi được. */
    public static RoadClass of(String highway) {
        return highway == null ? null : BY_TAG.get(highway);
    }
}
