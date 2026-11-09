package com.badminton.v2.routing;

/** Phương tiện tìm đường. [flag] là bit trong cờ cho phép của mỗi cạnh đồ thị. */
public enum TravelMode {
    CAR(1, "Ô tô"),
    MOTORBIKE(2, "Xe máy"),
    WALK(4, "Đi bộ");

    public final int flag;
    public final String label;

    TravelMode(int flag, String label) {
        this.flag = flag;
        this.label = label;
    }

    /** Tốc độ lớn nhất (m/s) trên mọi loại đường: dùng cho hàm ước lượng A* (không đánh giá quá). */
    public double maxSpeedMps() {
        double max = 0;
        for (RoadClass c : RoadClass.values()) max = Math.max(max, c.speedKmh(this));
        return max / 3.6;
    }

    /** "motorbike" | "car" | "walk" (mặc định xe máy). */
    public static TravelMode parse(String raw) {
        if (raw == null) return MOTORBIKE;
        return switch (raw.trim().toLowerCase()) {
            case "car", "driving", "oto" -> CAR;
            case "walk", "walking", "foot" -> WALK;
            default -> MOTORBIKE;
        };
    }
}
