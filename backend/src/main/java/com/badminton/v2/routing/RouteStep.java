package com.badminton.v2.routing;

/**
 * Một chỉ dẫn: thao tác tại điểm ([lat],[lng]) rồi đi tiếp [distanceMeters] mét trên [streetName].
 * [type]: DEPART, CONTINUE, SLIGHT_LEFT, SLIGHT_RIGHT, TURN_LEFT, TURN_RIGHT, SHARP_LEFT, SHARP_RIGHT, UTURN, ARRIVE.
 */
public record RouteStep(String type, String instruction, String streetName,
                        double distanceMeters, double durationSeconds, double lat, double lng) {}
