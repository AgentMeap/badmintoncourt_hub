package com.badminton.v2.routing;

import java.util.ArrayList;
import java.util.List;

/**
 * Tạo chỉ dẫn từng chỗ rẽ (tiếng Việt) từ chuỗi cạnh của đường đi.
 * - Gộp các cạnh liên tiếp cùng tên đường thành một đoạn.
 * - Tách đoạn khi đổi tên đường, hoặc rẽ gắt (>= 60°) trên cùng đường / hẻm không tên.
 * - Góc rẽ tính trên khoảng ~25 m trước và sau giao lộ để không bị nhiễu bởi các nút OSM sát nhau.
 */
final class InstructionBuilder {

    private static final double BEARING_SPAN_M = 25;
    private static final double SAME_STREET_TURN_DEG = 60;
    private static final double MIN_SEGMENT_M = 20;

    private InstructionBuilder() {}

    /** [verts].length == [edges].length + 1. Trả về các bước, phần tử cuối là ARRIVE. */
    static List<RouteStep> build(RoadGraph g, int[] verts, int[] edges, TravelMode mode,
                                 double trafficFactor, String destinationName) {
        List<RouteStep> steps = new ArrayList<>();
        if (edges.length == 0) {
            int v = verts[0];
            steps.add(new RouteStep("ARRIVE", arriveText(destinationName), null, 0, 0, g.lat[v], g.lon[v]));
            return steps;
        }

        // 1. Chia đoạn
        List<int[]> segments = new ArrayList<>(); // {startEdgeIdx, endEdgeIdxExclusive}
        int start = 0;
        for (int i = 1; i < edges.length; i++) {
            boolean nameChange = g.nameIndex(edges[i]) != g.nameIndex(edges[i - 1]);
            double angle = turnAt(g, verts, i);
            if (nameChange || Math.abs(angle) >= SAME_STREET_TURN_DEG) {
                segments.add(new int[]{start, i});
                start = i;
            }
        }
        segments.add(new int[]{start, edges.length});

        // 2. Gộp đoạn quá ngắn không tên vào đoạn trước (nút nối, lối rẽ vài mét)
        List<int[]> merged = new ArrayList<>();
        for (int[] s : segments) {
            if (!merged.isEmpty() && length(g, edges, s) < MIN_SEGMENT_M && g.nameIndex(edges[s[0]]) < 0) {
                merged.get(merged.size() - 1)[1] = s[1];
            } else {
                merged.add(s);
            }
        }
        // Đoạn sau trùng tên với đoạn trước (do vừa gộp) -> nối liền nếu gần như đi thẳng
        List<int[]> segs = new ArrayList<>();
        for (int[] s : merged) {
            if (!segs.isEmpty()) {
                int[] prev = segs.get(segs.size() - 1);
                boolean sameName = g.nameIndex(edges[prev[1] - 1]) == g.nameIndex(edges[s[0]]);
                if (sameName && Math.abs(turnAt(g, verts, s[0])) < SAME_STREET_TURN_DEG) {
                    prev[1] = s[1];
                    continue;
                }
            }
            segs.add(s);
        }

        // 3. Sinh chỉ dẫn
        for (int k = 0; k < segs.size(); k++) {
            int[] s = segs.get(k);
            int e0 = edges[s[0]];
            int v0 = verts[s[0]];
            String street = g.name(e0);
            String where = street != null ? street : g.roadClass(e0).generic;
            double dist = length(g, edges, s);
            double secs = 0;
            for (int i = s[0]; i < s[1]; i++) secs += g.length[edges[i]] / g.speedMps(edges[i], mode);
            secs *= mode == TravelMode.WALK ? 1 : trafficFactor;

            String type;
            String text;
            if (k == 0) {
                type = "DEPART";
                double b = outgoingBearing(g, verts, s[0]);
                text = "Đi về hướng " + Geo.compass(b) + " trên " + where;
            } else {
                double angle = turnAt(g, verts, s[0]);
                type = maneuver(angle);
                secs += mode == TravelMode.WALK ? 0 : turnPenaltySeconds(type);
                text = switch (type) {
                    case "CONTINUE" -> "Tiếp tục vào " + where;
                    case "UTURN" -> "Quay đầu vào " + where;
                    default -> verb(type) + " vào " + where;
                };
            }
            steps.add(new RouteStep(type, text, street, dist, secs, g.lat[v0], g.lon[v0]));
        }
        int last = verts[verts.length - 1];
        steps.add(new RouteStep("ARRIVE", arriveText(destinationName), null, 0, 0, g.lat[last], g.lon[last]));
        return steps;
    }

    private static String arriveText(String destinationName) {
        return destinationName == null || destinationName.isBlank() ? "Đến nơi" : "Đến nơi: " + destinationName;
    }

    static String maneuver(double angle) {
        double a = Math.abs(angle);
        String side = angle > 0 ? "RIGHT" : "LEFT";
        if (a < 25) return "CONTINUE";
        if (a < 60) return "SLIGHT_" + side;
        if (a < 135) return "TURN_" + side;
        if (a < 165) return "SHARP_" + side;
        return "UTURN";
    }

    private static String verb(String type) {
        return switch (type) {
            case "SLIGHT_LEFT" -> "Chếch trái";
            case "SLIGHT_RIGHT" -> "Chếch phải";
            case "TURN_LEFT" -> "Rẽ trái";
            case "TURN_RIGHT" -> "Rẽ phải";
            case "SHARP_LEFT" -> "Rẽ gắt trái";
            case "SHARP_RIGHT" -> "Rẽ gắt phải";
            default -> "Đi tiếp";
        };
    }

    private static double turnPenaltySeconds(String type) {
        return switch (type) {
            case "CONTINUE" -> 2;
            case "SLIGHT_LEFT", "SLIGHT_RIGHT" -> 4;
            case "UTURN" -> 30;
            default -> 10;
        };
    }

    private static double length(RoadGraph g, int[] edges, int[] seg) {
        double d = 0;
        for (int i = seg[0]; i < seg[1]; i++) d += g.length[edges[i]];
        return d;
    }

    /** Góc rẽ tại đỉnh verts[i] (giữa cạnh i-1 và cạnh i). */
    static double turnAt(RoadGraph g, int[] verts, int i) {
        return Geo.turnAngle(incomingBearing(g, verts, i), outgoingBearing(g, verts, i));
    }

    /** Hướng đi tới đỉnh verts[i], đo từ điểm cách ~25 m phía trước. */
    private static double incomingBearing(RoadGraph g, int[] verts, int i) {
        int j = verts[i];
        int k = i - 1;
        double acc = 0;
        while (k > 0) {
            acc += Geo.distanceM(g.lat[verts[k]], g.lon[verts[k]], g.lat[verts[k + 1]], g.lon[verts[k + 1]]);
            if (acc >= BEARING_SPAN_M) break;
            k--;
        }
        return Geo.bearingDeg(g.lat[verts[k]], g.lon[verts[k]], g.lat[j], g.lon[j]);
    }

    /** Hướng đi ra từ đỉnh verts[i], đo tới điểm cách ~25 m phía sau. */
    private static double outgoingBearing(RoadGraph g, int[] verts, int i) {
        int j = verts[i];
        int k = i + 1;
        double acc = 0;
        while (k < verts.length - 1) {
            acc += Geo.distanceM(g.lat[verts[k - 1]], g.lon[verts[k - 1]], g.lat[verts[k]], g.lon[verts[k]]);
            if (acc >= BEARING_SPAN_M) break;
            k++;
        }
        return Geo.bearingDeg(g.lat[j], g.lon[j], g.lat[verts[k]], g.lon[verts[k]]);
    }
}
