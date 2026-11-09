package com.badminton.v2.routing;

import java.util.List;

/**
 * Kết quả tìm đường. [geometry]: các điểm {lat, lng} để vẽ (đã rút gọn).
 * [approximate] = true khi thời gian chỉ là ước tính theo tốc độ trung bình (luôn đúng với dữ liệu OSM).
 */
public record RouteResult(TravelMode mode, double distanceMeters, double durationSeconds,
                          List<double[]> geometry, List<RouteStep> steps, int visitedNodes) {}
