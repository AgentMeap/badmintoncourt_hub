import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/api/json.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

/// Biểu đồ cột 7 ngày (một chuỗi số liệu) cho dashboard chủ sân / Admin.
///
/// [rows]: `[{date: 'yyyy-MM-dd', amount, count}]` theo thứ tự cũ -> mới (máy chủ trả về).
/// - Một màu (primary), cột mảnh bo 4px ở đầu cột, nền lưới mờ.
/// - Chỉ ghi số trên cột cao nhất; chạm / di chuột vào cột để xem chi tiết ngày đó.
/// - Có [Semantics] tóm tắt cho trình đọc màn hình.
class DayBarChart extends StatelessWidget {
  const DayBarChart({
    super.key,
    required this.rows,
    this.height = 150,
    this.countLabel = 'ca',
  });

  final List<Json> rows;
  final double height;

  /// Đơn vị của `count` trong chú thích (VD "ca", "giao dịch").
  final String countLabel;

  static String _compact(num v) {
    if (v >= 1000000) {
      final m = v / 1000000;
      return '${m >= 10 ? m.round() : m.toStringAsFixed(1).replaceAll('.0', '')}tr';
    }
    if (v >= 1000) return '${(v / 1000).round()}k';
    return '${v.round()}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (rows.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('Chưa có dữ liệu', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
      );
    }

    final values = [for (final r in rows) UiFmt.toNum(r['amount'], 0)];
    final maxValue = values.fold<num>(0, (m, v) => v > m ? v : m);
    final maxIndex = values.indexOf(maxValue);
    final total = values.fold<num>(0, (s, v) => s + v);
    final today = DateTime.now();
    final todayKey = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    return Semantics(
      label: 'Biểu đồ 7 ngày, tổng ${UiFmt.vnd(total)}, cao nhất ${UiFmt.vnd(maxValue)}',
      child: SizedBox(
        height: height,
        child: LayoutBuilder(builder: (context, c) {
          const labelH = 34.0; // nhãn ngày bên dưới
          const valueH = 18.0; // nhãn số trên cột cao nhất
          final plotH = c.maxHeight - labelH - valueH;
          final slot = c.maxWidth / rows.length;
          final barW = (slot * 0.5).clamp(10.0, 28.0);

          return Stack(
            children: [
              // Lưới ngang mờ (đáy, giữa, đỉnh)
              for (final f in const [0.0, 0.5, 1.0])
                Positioned(
                  left: 0,
                  right: 0,
                  top: valueH + plotH * (1 - f),
                  child: Container(height: 1, color: cs.outlineVariant.withValues(alpha: f == 0 ? 0.9 : 0.4)),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < rows.length; i++)
                    SizedBox(
                      width: slot,
                      child: Tooltip(
                        triggerMode: TooltipTriggerMode.tap,
                        waitDuration: Duration.zero,
                        message: '${UiDate.full('${rows[i]['date']}')}\n'
                            '${UiFmt.vnd(values[i])} • ${UiFmt.toNum(rows[i]['count'], 0).toInt()} $countLabel',
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SizedBox(
                              height: valueH,
                              child: i == maxIndex && maxValue > 0
                                  ? Text(_compact(maxValue),
                                      style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700))
                                  : null,
                            ),
                            SizedBox(
                              height: plotH,
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  width: barW,
                                  height: maxValue <= 0
                                      ? 0
                                      : (plotH * values[i] / maxValue).clamp(values[i] > 0 ? 3.0 : 0.0, plotH),
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              height: labelH,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '${rows[i]['date']}' == todayKey
                                      ? 'Hôm nay'
                                      : '${UiDate.weekday('${rows[i]['date']}')}\n${UiDate.day('${rows[i]['date']}')}',
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    height: 1.1,
                                    fontWeight: '${rows[i]['date']}' == todayKey ? FontWeight.w700 : null,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }
}
