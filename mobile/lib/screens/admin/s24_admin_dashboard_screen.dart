import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/booking_rules.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S24: Admin Platform Overview Dashboard (Luồng 3)
// Giao diện theo design system + sửa logic: GMV và hoa hồng toàn sàn trước đây gán
// cứng 84.500.000đ; giờ TÍNH từ các vé online đã thanh toán (OwnerFinance.platformGmv).
class S24AdminDashboardScreen extends StatelessWidget {
  final AppState appState;
  const S24AdminDashboardScreen({super.key, required this.appState});

  Widget _taskTile(BuildContext context,
      {required IconData icon, required String title, required String subtitle, required int count, required String target}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SurfaceCard(
      onTap: () => appState.goTo(target),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: count > 0 ? WarningTone.container(cs) : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: count > 0 ? WarningTone.onContainer(cs) : cs.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: cs.error, borderRadius: BorderRadius.circular(999)),
              child: Text('$count',
                  style: theme.textTheme.labelLarge?.copyWith(color: cs.onError, fontWeight: FontWeight.w800)),
            ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pendingVenues = appState.adminPendingVenues.where((v) => v['status'] == 'PENDING').length;
    final pendingPayouts = appState.payoutRequests.where((p) => p['status'] == 'PENDING').length;
    final gmv = OwnerFinance.platformGmv(appState.bookings);
    final commission = OwnerFinance.commissionOf(gmv);
    final today = BookingRules.dateKey(DateTime.now());
    final allIds = OwnerFinance.idsOf(appState.venues);
    final todaySessions = OwnerFinance.sessionsOn(appState.bookings, allIds, today).length;

    return ResponsiveCenter(
      maxWidth: Responsive.defaultContentMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context),
        children: [
          Text('Quản trị nền tảng',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          StatGrid(children: [
            StatTile(icon: Icons.payments_outlined, value: UiFmt.vnd(gmv), label: 'GMV online toàn sàn'),
            StatTile(
              icon: Icons.percent,
              value: UiFmt.vnd(commission),
              label: 'Hoa hồng (${(OwnerFinance.commissionRate * 100).round()}%)',
              accent: cs.tertiary,
            ),
            StatTile(
              icon: Icons.storefront_outlined,
              value: '${appState.venues.length}',
              label: 'Cơ sở đang hoạt động',
              accent: cs.secondary,
            ),
            StatTile(
              icon: Icons.event_available_outlined,
              value: '$todaySessions',
              label: 'Ca đặt hôm nay',
              accent: cs.primary,
            ),
          ]),
          const SizedBox(height: 24),
          const SectionHeader('Việc cần xử lý'),
          _taskTile(
            context,
            icon: Icons.fact_check_outlined,
            title: 'Kiểm duyệt cơ sở',
            subtitle: pendingVenues > 0 ? '$pendingVenues hồ sơ đang chờ duyệt' : 'Không có hồ sơ chờ',
            count: pendingVenues,
            target: 'S25',
          ),
          const SizedBox(height: 8),
          _taskTile(
            context,
            icon: Icons.account_balance_outlined,
            title: 'Duyệt giải ngân',
            subtitle: pendingPayouts > 0 ? '$pendingPayouts yêu cầu từ chủ sân' : 'Không có yêu cầu chờ',
            count: pendingPayouts,
            target: 'S26',
          ),
        ],
      ),
    );
  }
}
