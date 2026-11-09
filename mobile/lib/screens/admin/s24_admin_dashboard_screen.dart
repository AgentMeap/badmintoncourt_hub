import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/booking_rules.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';
import 'package:badminton_v2_mobile/core/widgets/day_bar_chart.dart';

// S24: Admin Platform Overview Dashboard (Luồng 3)
// Số liệu từ GET /admin/dashboard (máy chủ tính trên toàn bộ dữ liệu): GMV online và hoa hồng,
// GMV 7 ngày, số ca hôm nay, người dùng theo vai trò, việc cần xử lý (duyệt cơ sở, giải ngân).
class S24AdminDashboardScreen extends StatefulWidget {
  final AppState appState;
  const S24AdminDashboardScreen({super.key, required this.appState});

  @override
  State<S24AdminDashboardScreen> createState() => _S24AdminDashboardScreenState();
}

class _S24AdminDashboardScreenState extends State<S24AdminDashboardScreen> {
  AppState get _app => widget.appState;

  @override
  void initState() {
    super.initState();
    _app.refreshAdminDashboard().catchError((Object e) => debugPrint('[S24] $e'));
  }

  Future<void> _refresh() async {
    try {
      await _app.refreshAdminDashboard();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Widget _taskTile(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required int count,
      required String target,
      bool urgent = true}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final highlight = urgent && count > 0;
    return SurfaceCard(
      onTap: () => _app.goTo(target),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: highlight ? WarningTone.container(cs) : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: highlight ? WarningTone.onContainer(cs) : cs.onSurfaceVariant),
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
          if (highlight)
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
    final d = _app.adminDashboard;
    final hasServer = d.isNotEmpty;

    // Mất kết nối: tạm tính từ dữ liệu trên máy như trước
    final gmv = hasServer ? UiFmt.toNum(d['totalGmv'], 0) : OwnerFinance.platformGmv(_app.bookings);
    final commission = hasServer ? UiFmt.toNum(d['platformCommission'], 0) : OwnerFinance.commissionOf(gmv);
    final pendingVenues = hasServer
        ? UiFmt.toNum(d['pendingVenuesCount'], 0).toInt()
        : _app.adminPendingVenues.where((v) => v['status'] == 'PENDING').length;
    final pendingPayouts = hasServer
        ? UiFmt.toNum(d['pendingPayoutsCount'], 0).toInt()
        : _app.payoutRequests.where((p) => p['status'] == 'PENDING').length;
    final activeVenues = hasServer ? UiFmt.toNum(d['activeVenuesCount'], 0).toInt() : _app.venues.length;
    final bookingsToday = hasServer
        ? UiFmt.toNum(d['bookingsToday'], 0).toInt()
        : OwnerFinance.sessionsOn(
                _app.bookings, OwnerFinance.idsOf(_app.venues), BookingRules.dateKey(DateTime.now()))
            .length;
    final byRole = asJson(d['usersByRole']);
    final totalUsers = UiFmt.toNum(d['totalUsers'], _app.adminUsers.length).toInt();
    final locked = UiFmt.toNum(d['lockedUsersCount'], 0).toInt();
    final gmv7 = asJsonList(d['gmvLast7Days']);
    final total7 = gmv7.fold<num>(0, (s, r) => s + UiFmt.toNum(r['amount'], 0));
    final percent = (UiFmt.toNum(d['commissionRate'], OwnerFinance.commissionRate) * 100).round();

    return ResponsiveCenter(
      maxWidth: Responsive.defaultContentMaxWidth,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: Responsive.screenPadding(context),
          children: [
            Text('Quản trị nền tảng', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            StatGrid(children: [
              StatTile(icon: Icons.payments_outlined, value: UiFmt.vnd(gmv), label: 'GMV online toàn sàn'),
              StatTile(
                icon: Icons.percent,
                value: UiFmt.vnd(commission),
                label: 'Hoa hồng ($percent%)',
                accent: cs.tertiary,
              ),
              StatTile(
                icon: Icons.storefront_outlined,
                value: '$activeVenues',
                label: 'Cơ sở đang hoạt động',
                accent: cs.secondary,
              ),
              StatTile(
                icon: Icons.event_available_outlined,
                value: '$bookingsToday',
                label: 'Ca đặt hôm nay',
                accent: cs.primary,
              ),
            ]),
            const SizedBox(height: 24),

            if (gmv7.isNotEmpty) ...[
              SectionHeader('GMV 7 ngày',
                  trailing: Text(UiFmt.vnd(total7),
                      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700))),
              SurfaceCard(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                child: DayBarChart(rows: gmv7, countLabel: 'giao dịch'),
              ),
              const SizedBox(height: 24),
            ],

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
              subtitle: pendingPayouts > 0
                  ? '$pendingPayouts yêu cầu • ${UiFmt.vnd(UiFmt.toNum(d['pendingPayoutsAmount'], 0))}'
                  : 'Không có yêu cầu chờ',
              count: pendingPayouts,
              target: 'S26',
            ),
            const SizedBox(height: 24),

            const SectionHeader('Người dùng'),
            SurfaceCard(
              child: Column(
                children: [
                  InfoRow(icon: Icons.groups_outlined, label: 'Tổng tài khoản', value: '$totalUsers', emphasize: true),
                  InfoRow(
                      icon: Icons.sports_tennis,
                      label: 'Người chơi',
                      value: '${UiFmt.toNum(byRole['CUSTOMER'], 0).toInt()}'),
                  InfoRow(
                      icon: Icons.storefront_outlined,
                      label: 'Chủ sân',
                      value: '${UiFmt.toNum(byRole['COURT_OWNER'], 0).toInt()}'),
                  InfoRow(
                      icon: Icons.admin_panel_settings_outlined,
                      label: 'Quản trị viên',
                      value: '${UiFmt.toNum(byRole['ADMIN'], 0).toInt()}'),
                  InfoRow(icon: Icons.lock_outline, label: 'Đang bị khóa', value: '$locked'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  _app.adminModerationTab = 1;
                  _app.goTo('S25');
                },
                style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.manage_accounts_outlined, size: 18),
                label: const Text('Quản lý tài khoản'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
