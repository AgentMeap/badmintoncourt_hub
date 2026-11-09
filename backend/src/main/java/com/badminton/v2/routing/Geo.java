package com.badminton.v2.routing;

import java.util.ArrayList;
import java.util.List;

/** Hàm hình học trên mặt cầu (đủ chính xác cho phạm vi một thành phố). */
public final class Geo {
    private Geo() {}

    public static final double EARTH_RADIUS_M = 6_371_008.8;

    /** Khoảng cách Haversine (mét). */
    public static double distanceM(double lat1, double lon1, double lat2, double lon2) {
        double p1 = Math.toRadians(lat1), p2 = Math.toRadians(lat2);
        double dp = p2 - p1, dl = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dp / 2) * Math.sin(dp / 2) + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) * Math.sin(dl / 2);
        return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(a)));
    }

    /** Hướng đi (độ, 0 = Bắc, 90 = Đông). */
    public static double bearingDeg(double lat1, double lon1, double lat2, double lon2) {
        double p1 = Math.toRadians(lat1), p2 = Math.toRadians(lat2), dl = Math.toRadians(lon2 - lon1);
        double y = Math.sin(dl) * Math.cos(p2);
        double x = Math.cos(p1) * Math.sin(p2) - Math.sin(p1) * Math.cos(p2) * Math.cos(dl);
        return (Math.toDegrees(Math.atan2(y, x)) + 360) % 360;
    }

    /** Góc rẽ từ hướng [in] sang hướng [out]: -180..180, dương = rẽ phải. */
    public static double turnAngle(double in, double out) {
        double d = (out - in) % 360;
        if (d > 180) d -= 360;
        if (d < -180) d += 360;
        return d;
    }

    private static final String[] COMPASS = {"Bắc", "Đông Bắc", "Đông", "Đông Nam", "Nam", "Tây Nam", "Tây", "Tây Bắc"};

    public static String compass(double bearing) {
        return COMPASS[(int) Math.round(((bearing % 360) + 360) % 360 / 45.0) % 8];
    }

    /** Rút gọn đường gấp khúc (Douglas-Peucker), [toleranceM] mét. Mỗi điểm là {lat, lng}. */
    public static List<double[]> simplify(List<double[]> pts, double toleranceM) {
        if (pts.size() < 3) return new ArrayList<>(pts);
        boolean[] keep = new boolean[pts.size()];
        keep[0] = keep[pts.size() - 1] = true;
        double refLat = Math.toRadians(pts.get(0)[0]);
        double mPerDegLat = Math.PI * EARTH_RADIUS_M / 180;
        double mPerDegLon = mPerDegLat * Math.cos(refLat);
        java.util.ArrayDeque<int[]> stack = new java.util.ArrayDeque<>();
        stack.push(new int[]{0, pts.size() - 1});
        while (!stack.isEmpty()) {
            int[] r = stack.pop();
            int a = r[0], b = r[1];
            if (b - a < 2) continue;
            double ax = pts.get(a)[1] * mPerDegLon, ay = pts.get(a)[0] * mPerDegLat;
            double bx = pts.get(b)[1] * mPerDegLon, by = pts.get(b)[0] * mPerDegLat;
            double dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy;
            int idx = -1;
            double max = -1;
            for (int i = a + 1; i < b; i++) {
                double px = pts.get(i)[1] * mPerDegLon, py = pts.get(i)[0] * mPerDegLat;
                double d;
                if (len2 == 0) {
                    d = Math.hypot(px - ax, py - ay);
                } else {
                    double t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2));
                    d = Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
                }
                if (d > max) {
                    max = d;
                    idx = i;
                }
            }
            if (max > toleranceM) {
                keep[idx] = true;
                stack.push(new int[]{a, idx});
                stack.push(new int[]{idx, b});
            }
        }
        List<double[]> out = new ArrayList<>();
        for (int i = 0; i < pts.size(); i++) if (keep[i]) out.add(pts.get(i));
        return out;
    }
}
