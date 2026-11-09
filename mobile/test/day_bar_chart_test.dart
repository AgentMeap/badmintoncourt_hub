import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:badminton_v2_mobile/core/booking_rules.dart';
import 'package:badminton_v2_mobile/core/widgets/day_bar_chart.dart';

void main() {
  List<Map<String, dynamic>> sevenDays() {
    final today = BookingRules.dateOnly(DateTime.now());
    return [
      for (var i = 6; i >= 0; i--)
        {
          'date': BookingRules.dateKey(today.subtract(Duration(days: i))),
          'amount': i == 2 ? 1200000 : 300000 * (i % 3),
          'count': i,
        }
    ];
  }

  Widget host(Widget child, {double width = 360}) => MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: width, child: child))),
      );

  testWidgets('Vẽ 7 cột, nhãn "Hôm nay" và chỉ ghi số trên cột cao nhất', (tester) async {
    await tester.pumpWidget(host(DayBarChart(rows: sevenDays())));
    expect(find.byType(Tooltip), findsNWidgets(7));
    expect(find.text('Hôm nay'), findsOneWidget);
    expect(find.text('1.2tr'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Không tràn ở màn hình rất hẹp', (tester) async {
    await tester.pumpWidget(host(DayBarChart(rows: sevenDays()), width: 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Không có dữ liệu thì hiện thông báo', (tester) async {
    await tester.pumpWidget(host(const DayBarChart(rows: [])));
    expect(find.text('Chưa có dữ liệu'), findsOneWidget);
  });
}
