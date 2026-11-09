import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:badminton_v2_mobile/core/api/json.dart';

/// Tuyến đường theo đường phố do máy chủ tính (xem RouteRepository).
class RoutePlan {
  const RoutePlan({
    required this.mode,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.points,
    required this.steps,
  });

  final String mode;
  final double distanceMeters;
  final double durationSeconds;
  final List<LatLng> points;
  final List<RouteStepInfo> steps;

  /// null nếu dữ liệu không đủ để vẽ.
  static RoutePlan? fromJson(Json j) {
    final points = <LatLng>[];
    final geometry = j['geometry'];
    if (geometry is List) {
      for (final p in geometry) {
        if (p is List && p.length >= 2) {
          final la = asNum(p[0]), lo = asNum(p[1]);
          if (la != null && lo != null) points.add(LatLng(la.toDouble(), lo.toDouble()));
        }
      }
    }
    if (points.length < 2) return null;
    return RoutePlan(
      mode: '${j['mode'] ?? ''}',
      distanceMeters: (asNum(j['distanceMeters']) ?? 0).toDouble(),
      durationSeconds: (asNum(j['durationSeconds']) ?? 0).toDouble(),
      points: points,
      steps: [for (final s in asJsonList(j['steps'])) RouteStepInfo.fromJson(s)],
    );
  }

  String get distanceLabel => formatDistance(distanceMeters);

  String get durationLabel => formatDuration(durationSeconds);

  /// Số chỗ cần rẽ (không tính bước xuất phát / đến nơi).
  int get turnCount => steps.where((s) => s.type != 'DEPART' && s.type != 'ARRIVE').length;

  static String formatDistance(double meters) {
    if (meters < 1000) return '${(meters / 10).round() * 10} m';
    final km = meters / 1000;
    return '${km < 10 ? km.toStringAsFixed(1).replaceAll('.', ',') : km.round()} km';
  }

  static String formatDuration(double seconds) {
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return '$minutes phút';
    final h = minutes ~/ 60, m = minutes % 60;
    return m == 0 ? '$h giờ' : '$h giờ $m phút';
  }
}

class RouteStepInfo {
  const RouteStepInfo({
    required this.type,
    required this.instruction,
    required this.distanceMeters,
    required this.point,
    this.streetName,
  });

  final String type;
  final String instruction;
  final String? streetName;
  final double distanceMeters;
  final LatLng? point;

  factory RouteStepInfo.fromJson(Json j) {
    final la = asNum(j['lat']), lo = asNum(j['lng']);
    return RouteStepInfo(
      type: '${j['type'] ?? ''}',
      instruction: '${j['instruction'] ?? ''}',
      streetName: j['streetName']?.toString(),
      distanceMeters: (asNum(j['distanceMeters']) ?? 0).toDouble(),
      point: la != null && lo != null ? LatLng(la.toDouble(), lo.toDouble()) : null,
    );
  }

  IconData get icon => switch (type) {
        'DEPART' => Icons.trip_origin,
        'ARRIVE' => Icons.sports_tennis,
        'TURN_LEFT' => Icons.turn_left,
        'TURN_RIGHT' => Icons.turn_right,
        'SLIGHT_LEFT' => Icons.turn_slight_left,
        'SLIGHT_RIGHT' => Icons.turn_slight_right,
        'SHARP_LEFT' => Icons.turn_sharp_left,
        'SHARP_RIGHT' => Icons.turn_sharp_right,
        'UTURN' => Icons.u_turn_left,
        _ => Icons.straight,
      };
}
