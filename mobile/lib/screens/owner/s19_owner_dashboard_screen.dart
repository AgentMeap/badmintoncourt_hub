import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/booking_rules.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';
import 'package:badminton_v2_mobile/core/widgets/day_bar_chart.dart';

// S19: Owner Dashboard & Revenue Analytics
// Số liệu lấy từ GET /owner/{id}/dashboard (máy chủ tính trên TOÀN BỘ vé của các cơ sở):
// doanh thu / số ca / ca chưa nhận sân / tỉ lệ lấp đầy hôm nay, doanh thu 7 ngày,
// số tiền có thể giải ngân và từng cơ sở (kể cả chờ duyệt, bị từ chối, tạm ngưng).
// Mất kết nối thì tạm tính từ dữ liệu đã tải trên máy.
class S19OwnerDashboardScreen extends StatefulWidget {
  final AppState appState;
  const S19OwnerDashboardScreen({super.key, required this.appState});

  @override
  State<S19OwnerDashboardScreen> createState() => _S19OwnerDashboardScreenState();
}

class _S19OwnerDashboardScreenState extends State<S19OwnerDashboardScreen> {
  AppState get _app => widget.appState;

  @override
  void initState() {
    super.initState();
    // Mở màn là làm mới số liệu (lỗi mạng thì giữ số cũ, không làm phiền người dùng)
    _app.refreshOwnerDashboard().catchError((Object e) => debugPrint('[S19] $e'));
  }

  Future<void> _refresh() async {
    try {
      await _app.refreshOwnerDashboard();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  /// Số liệu hôm nay: từ máy chủ, hoặc tạm tính trên máy khi chưa tải được.
  (Json, List<Json>) _today() {
    final d = _app.ownerDashboard;
    if (d.isNotEmpty) return (asJson(d['today']), asJsonList(d['todaySessions']));
    final ids = OwnerFinance.idsOf(OwnerFinance.ownerVenues(_app.venues, _app.userId));
    final sessions = OwnerFinance.sessionsOn(_app.bookings, ids, BookingRules.dateKey(DateTime.now()))
      ..sort((a, b) => '${a['startTime']}'.compareTo('${b['startTime']}'));
    return (
      {
        'revenue': OwnerFinance.revenueOf(sessions),
        'sessions': sessions.length,
        'waitingCheckIn': sessions.where((b) => b['status'] == 'CONFIRMED').length,
      },
      sessions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final d = _app.ownerDashboard;
    final (today, sessions) = _today();
    final occupancy = today['occupancyPercent'];
    final venues = _app.ownerVenueList.isNotEmpty
        ? _app.ownerVenueList
        : [..._app.adminPendingVenues, ...OwnerFinance.ownerVenues(_app.venues, _app.userId)];
    final statsById = {for (final s in asJsonList(d['venueStats'])) '${s['venueId']}': s};
    final last7 = asJsonList(d['last7Days']);
    final total7 = last7.fold<num>(0, (s, r) => s + UiFmt.toNum(r['amount'], 0));
    final availableNet = d.isNotEmpty
        ? UiFmt.toNum(d['availableNetPayout'], 0)
        : OwnerFinance.netOf(OwnerFinance.revenueOf(
            OwnerFinance.settleable(_app.bookings, OwnerFinance.idsOf(venues))));
    final pendingNet = UiFmt.toNum(d['pendingPayoutNet'], 0);
    final name = _app.fullName.split('(').first.trim();

    return ResponsiveCenter(
      maxWidth: Responsive.defaultContentMaxWidth,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: Responsive.screenPadding(context),
          children: [
            Text('Xin chào, $name', style: theme.textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
            Text('Tổng quan hôm nay', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            StatGrid(children: [
              StatTile(
                icon: Icons.trending_up,
                value: UiFmt.vnd(UiFmt.toNum(today['revenue'], 0)),
                label: 'Doanh thu hôm nay',
              ),
              StatTile(
                icon: Icons.event_available_outlined,
                value: '${UiFmt.toNum(today['sessions'], 0).toInt()}',
                label: 'Ca đặt hôm nay (online + vãng lai)',
                accent: cs.tertiary,
              ),
              StatTile(
                icon: Icons.how_to_reg_outlined,
                value: '${UiFmt.toNum(today['waitingCheckIn'], 0).toInt()}',
                label: 'Ca chưa nhận sân',
                accent: cs.secondary,
              ),
              StatTile(
                icon: Icons.donut_large_outlined,
                value: occupancy == null ? '-' : '${UiFmt.toNum(occupancy, 0).toInt()}%',
                label: 'Tỉ lệ lấp đầy sân hôm nay',
                accent: cs.primary,
              ),
            ]),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _app.goTo('S22'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Quét check-in', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _app.goTo('S21'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: const Text('Lịch biểu', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            if (last7.isNotEmpty) ...[
              SectionHeader('Doanh thu 7 ngày',
                  trailing: Text(UiFmt.vnd(total7),
                      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700))),
              SurfaceCard(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                child: DayBarChart(rows: last7, countLabel: 'ca'),
              ),
              const SizedBox(height: 24),
            ],

            // Giải ngân
            SurfaceCard(
              onTap: () => _app.goTo('S23'),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.account_balance_wallet_outlined, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Có thể giải ngân (sau phí 5%)',
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        Text(UiFmt.vnd(availableNet),
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        if (pendingNet > 0)
                          Text('Đang chờ Admin chuyển: ${UiFmt.vnd(pendingNet)}',
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ],
              ),
            ),
            const SizedBox(height: 24),

            SectionHeader('Ca hôm nay',
                trailing: TextButton(
                  onPressed: () => _app.goTo('S21'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                  child: const Text('Xem tất cả'),
                )),
            if (sessions.isEmpty)
              const EmptyState(icon: Icons.event_busy_outlined, title: 'Hôm nay chưa có ca đặt')
            else
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < sessions.length && i < 5; i++) ...[
                      if (i > 0) Divider(height: 1, color: cs.outlineVariant),
                      ListTile(
                        leading: Container(
                          width: 52,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${sessions[i]['startTime']}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        title: Text(
                          '${sessions[i]['courtName']} • ${sessions[i]['customerName'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text('${sessions[i]['venueName']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: StatusBadge(status: sessions[i]['status']?.toString()),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 24),

            SectionHeader('Cơ sở của tôi',
                trailing: TextButton.icon(
                  onPressed: () => _app.goTo('S20'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                  icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                  label: const Text('Thêm cơ sở'),
                )),
            if (venues.isEmpty)
              const EmptyState(
                icon: Icons.storefront_outlined,
                title: 'Chưa có cơ sở nào',
                message: 'Bấm "Thêm cơ sở" để gửi hồ sơ cho Admin duyệt.',
              ),
            for (final v in venues)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: venueCoverColors(cs, v)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.sports_tennis, color: cs.onPrimary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${v['name']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            Text(
                              _venueLine(v, statsById['${v['id']}']),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      venueStatusChip(theme, v['status']?.toString()),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _venueLine(Json v, Json? stat) {
    if (stat != null && v['status'] == 'APPROVED') {
      return 'Hôm nay: ${UiFmt.toNum(stat['sessionsToday'], 0).toInt()} ca • '
          '${UiFmt.vnd(UiFmt.toNum(stat['revenueToday'], 0))}';
    }
    return '${v['totalCourts'] ?? '-'} sân • ${v['address'] ?? ''}';
  }
}

/// Nhãn trạng thái cơ sở (dùng chung cho S19 và S25).
Widget venueStatusChip(ThemeData theme, String? status) {
  final cs = theme.colorScheme;
  final (label, icon, bg, fg) = switch (status) {
    'PENDING' => ('Chờ duyệt', Icons.hourglass_top_rounded, WarningTone.container(cs), WarningTone.onContainer(cs)),
    'REJECTED' => ('Bị từ chối', Icons.block, cs.errorContainer, cs.onErrorContainer),
    'SUSPENDED' => ('Tạm ngưng', Icons.pause_circle_outline, cs.surfaceContainerHighest, cs.onSurfaceVariant),
    _ => ('Đang hoạt động', Icons.check_circle_outline, cs.primaryContainer, cs.onPrimaryContainer),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: fg),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
