import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:badminton_v2_mobile/core/route_plan.dart';

void main() {
  final json = <String, dynamic>{
    'mode': 'MOTORBIKE',
    'distanceMeters': 17234,
    'durationSeconds': 2210,
    'geometry': [
      [10.8501, 106.7601],
      [10.8601, 106.7701],
      ['x', 1], // điểm hỏng bị bỏ qua
      [10.8753, 106.8],
    ],
    'steps': [
      {'type': 'DEPART', 'instruction': 'Đi về hướng Đông Bắc trên Võ Văn Ngân', 'distanceMeters': 500, 'lat': 10.85, 'lng': 106.76},
      {'type': 'TURN_LEFT', 'instruction': 'Rẽ trái vào Hẻm 12', 'streetName': 'Hẻm 12', 'distanceMeters': 120, 'lat': 10.86, 'lng': 106.77},
      {'type': 'ARRIVE', 'instruction': 'Đến nơi: Sân A', 'distanceMeters': 0, 'lat': 10.8753, 'lng': 106.8},
    ],
  };

  test('Đọc tuyến từ máy chủ', () {
    final plan = RoutePlan.fromJson(json)!;
    expect(plan.points.length, 3);
    expect(plan.steps.length, 3);
    expect(plan.turnCount, 1);
    expect(plan.distanceLabel, '17 km');
    expect(plan.durationLabel, '37 phút');
    expect(plan.steps[1].icon, Icons.turn_left);
    expect(plan.steps[1].streetName, 'Hẻm 12');
    expect(plan.steps.last.icon, Icons.sports_tennis);
  });

  test('Không đủ điểm để vẽ thì trả null', () {
    expect(RoutePlan.fromJson({'geometry': [[10.8, 106.7]]}), isNull);
    expect(RoutePlan.fromJson({}), isNull);
  });

  test('Định dạng quãng đường / thời gian', () {
    expect(RoutePlan.formatDistance(850), '850 m');
    expect(RoutePlan.formatDistance(4321), '4,3 km');
    expect(RoutePlan.formatDuration(59), '1 phút');
    expect(RoutePlan.formatDuration(3600), '1 giờ');
    expect(RoutePlan.formatDuration(4500), '1 giờ 15 phút');
  });
}
