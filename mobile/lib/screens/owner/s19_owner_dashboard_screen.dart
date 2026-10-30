import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/booking_rules.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S19: Owner Dashboard & Revenue Analytics
// Giao diện theo design system + sửa logic: các chỉ số (doanh thu hôm nay, số ca,
// tiền chờ giải ngân, khách chưa nhận sân) được TÍNH từ dữ liệu đặt sân thật
// thay vì số gán cứng. Danh sách ca hôm nay để chủ sân nắm nhanh.
class S19OwnerDashboardScreen extends StatelessWidget {
  final AppState appState;
  const S19OwnerDashboardScreen({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final myVenues = OwnerFinance.ownerVenues(appState.venues, appState.userId);
    final pending = OwnerFinance.ownerVenues(appState.adminPendingVenues, appState.userId)
        .where((v) => v['status'] == 'PENDING')
        .toList();
    final ids = OwnerFinance.idsOf(myVenues);
    final today = BookingRules.dateKey(DateTime.now());
    final sessions = OwnerFinance.sessionsOn(appState.bookings, ids, today)
      ..sort((a, b) => '${a['startTime']}'.compareTo('${b['startTime']}'));
    final revenue = OwnerFinance.revenueOf(sessions);
    final settleGross = OwnerFinance.revenueOf(OwnerFinance.settleable(appState.bookings, ids));
    final waitingCheckIn = sessions.where((b) => b['status'] != 'CHECKED_IN').length;
    final name = appState.fullName.split('(').first.trim();

    return ResponsiveCenter(
      maxWidth: Responsive.defaultContentMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context),
        children: [
          Text('Xin chào, $name',
              style: theme.textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
          Text('Tổng quan hôm nay',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          StatGrid(children: [
            StatTile(icon: Icons.trending_up, value: UiFmt.vnd(revenue), label: 'Doanh thu hôm nay'),
            StatTile(
              icon: Icons.event_available_outlined,
              value: '${sessions.length}',
              label: 'Ca đặt hôm nay (online + vãng lai)',
              accent: cs.tertiary,
            ),
            StatTile(
              icon: Icons.how_to_reg_outlined,
              value: '$waitingCheckIn',
              label: 'Ca chưa nhận sân',
              accent: cs.secondary,
            ),
            StatTile(
              icon: Icons.account_balance_wallet_outlined,
              value: UiFmt.vnd(OwnerFinance.netOf(settleGross)),
              label: 'Có thể giải ngân (sau phí)',
              accent: cs.primary,
            ),
          ]),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => appState.goTo('S22'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Quét check-in', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => appState.goTo('S21'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Lịch biểu', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          SectionHeader('Ca hôm nay',
              trailing: TextButton(
                onPressed: () => appState.goTo('S21'),
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
                      subtitle: Text(
                        '${sessions[i]['venueName']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: StatusBadge(status: sessions[i]['status']?.toString()),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 24),

          SectionHeader('Cơ sở của tôi',
              trailing: TextButton.icon(
                onPressed: () => appState.goTo('S20'),
                style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: const Text('Thêm cơ sở'),
              )),
          for (final v in [...pending, ...myVenues])
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
                          Text(v['name'].toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          Text(
                            '${v['totalCourts'] ?? '-'} sân • ${v['address']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _venueStatus(theme, v['status']?.toString()),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _venueStatus(ThemeData theme, String? status) {
    final cs = theme.colorScheme;
    final (label, icon, bg, fg) = switch (status) {
      'PENDING' => ('Chờ duyệt', Icons.hourglass_top_rounded, WarningTone.container(cs), WarningTone.onContainer(cs)),
      'REJECTED' => ('Bị từ chối', Icons.block, cs.errorContainer, cs.onErrorContainer),
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
}
