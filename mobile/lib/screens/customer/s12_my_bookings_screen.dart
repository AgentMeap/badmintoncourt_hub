import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S12: My Bookings Screen
// Thiết kế lại: lọc Sắp tới / Đã qua & hủy, thẻ vé có khối ngày bên trái,
// nhãn trạng thái tiếng Việt kèm icon, trạng thái rỗng có lời gọi hành động.
class S12MyBookingsScreen extends StatefulWidget {
  final AppState appState;
  const S12MyBookingsScreen({super.key, required this.appState});

  @override
  State<S12MyBookingsScreen> createState() => _S12MyBookingsScreenState();
}

class _S12MyBookingsScreenState extends State<S12MyBookingsScreen> {
  bool _showUpcoming = true;

  AppState get appState => widget.appState;

  static bool _isUpcoming(Map<String, dynamic> b) {
    final s = b['status']?.toString();
    return s != 'CANCELLED' && s != 'REFUNDED' && s != 'COMPLETED';
  }

  Widget _bookingCard(BuildContext context, Map<String, dynamic> b) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final date = b['playDate']?.toString() ?? '';
    final upcoming = _isUpcoming(b);

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          appState.selectedBooking = b;
          appState.goTo('S13');
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Khối ngày
              Container(
                width: 60,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: upcoming ? cs.primaryContainer : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      UiDate.weekday(date),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: upcoming ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      UiDate.day(date),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        color: upcoming ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      UiDate.monthShort(date),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: upcoming ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b['venueName']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 15, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${b['startTime']} - ${b['endTime']} • ${b['courtName']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: StatusBadge(status: b['status']?.toString()),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          UiFmt.vnd(UiFmt.toNum(b['totalPrice'], 0)),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: upcoming ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 36),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.event_busy_outlined, size: 44, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            _showUpcoming ? 'Bạn chưa có lịch đặt sắp tới' : 'Chưa có lịch sử đặt sân',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (_showUpcoming) ...[
            const SizedBox(height: 4),
            Text(
              'Tìm một sân gần bạn và đặt chỉ trong vài bước.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => appState.goToTab('S06', 'S06'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              icon: const Icon(Icons.search),
              label: const Text('Tìm sân ngay'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = appState.bookings.where((b) => b['bookingType'] == 'ONLINE').toList();
    final upcoming = all.where(_isUpcoming).toList()
      ..sort((a, b) => '${a['playDate']} ${a['startTime']}'
          .compareTo('${b['playDate']} ${b['startTime']}'));
    final past = all.where((b) => !_isUpcoming(b)).toList();
    final shown = _showUpcoming ? upcoming : past;

    return ResponsiveCenter(
      maxWidth: Responsive.defaultContentMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context),
        children: [
          Text(
            'Lịch đặt của tôi',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text('Sắp tới (${upcoming.length})'),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Lịch sử (${past.length})'),
                ),
              ],
              selected: {_showUpcoming},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _showUpcoming = s.first),
            ),
          ),
          const SizedBox(height: 16),
          if (shown.isEmpty)
            _emptyState(context)
          else
            ...shown.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _bookingCard(context, b),
              ),
            ),
        ],
      ),
    );
  }
}
