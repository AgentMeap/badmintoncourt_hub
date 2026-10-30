import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/responsive.dart';

/// Một mục trên thanh điều hướng.
class NavItem {
  final IconData icon;
  final String label;
  const NavItem(this.icon, this.label);
}

/// Cấu hình thanh điều hướng của vai trò hiện tại: các tab, mã màn của từng tab, tab đang chọn.
/// Dùng chung cho NavigationBar (điện thoại) và NavigationRail (tablet / desktop).
class NavSpec {
  final int selectedIndex;
  final List<String> targets;
  final List<NavItem> items;
  const NavSpec({required this.selectedIndex, required this.targets, required this.items});

  /// Tab chính của vai trò (Back từ tab khác sẽ về đây).
  String get home => targets.first;

  /// Màn gốc = một trong các tab (ở màn gốc hiện nút menu thay vì nút Back).
  bool isRoot(String code) => targets.contains(code);

  /// Trả về cấu hình theo vai trò & màn hiện tại; null ở các màn xác thực (không có thanh tab).
  static NavSpec? resolve(AppState appState) {
    final code = appState.currentScreen;
    if (['S01', 'S02', 'S03', 'S04'].contains(code)) return null;

    if (appState.role == 'COURT_OWNER' || ['S19', 'S20', 'S21', 'S22', 'S23'].contains(code)) {
      int idx = 0;
      if (code == 'S21' || code == 'S22') idx = 1;
      if (code == 'S20') idx = 2;
      if (code == 'S23') idx = 3;
      return NavSpec(
        selectedIndex: idx,
        targets: const ['S19', 'S21', 'S20', 'S23'],
        items: const [
          NavItem(Icons.dashboard_outlined, 'Tổng quan'),
          NavItem(Icons.calendar_month_outlined, 'Lịch biểu'),
          NavItem(Icons.stadium_outlined, 'Cơ sở'),
          NavItem(Icons.payments_outlined, 'Đối soát'),
        ],
      );
    }

    if (appState.role == 'ADMIN' || ['S24', 'S25', 'S26'].contains(code)) {
      int idx = 0;
      if (code == 'S25') idx = 1;
      if (code == 'S26') idx = 2;
      return NavSpec(
        selectedIndex: idx,
        targets: const ['S24', 'S25', 'S26'],
        items: const [
          NavItem(Icons.shield_outlined, 'Dashboard'),
          NavItem(Icons.fact_check_outlined, 'Kiểm duyệt'),
          NavItem(Icons.account_balance_outlined, 'Payout'),
        ],
      );
    }

    int idx = 0;
    if (code == 'S07') idx = 1;
    if (code == 'S15' || code == 'S16') idx = 2;
    if (code == 'S12' || code == 'S13' || code == 'S14' || code == 'S28') idx = 3;
    if (code == 'S18' || code == 'S27' || code == 'S29') idx = 4;

    return NavSpec(
      selectedIndex: idx,
      targets: const ['S06', 'S07', 'S15', 'S12', 'S18'],
      items: const [
        NavItem(Icons.home_outlined, 'Tìm sân'),
        NavItem(Icons.map_outlined, 'Bản đồ'),
        NavItem(Icons.groups_outlined, 'Tìm kèo'),
        NavItem(Icons.confirmation_number_outlined, 'Lịch đặt'),
        NavItem(Icons.account_balance_wallet_outlined, 'Ví & Tôi'),
      ],
    );
  }
}

/// Chọn tab: chạm lại đúng tab đang mở thì cuộn về đầu thay vì mở lại.
void _select(AppState appState, NavSpec spec, int i, VoidCallback? onReselect) {
  if (i == spec.selectedIndex && appState.currentScreen == spec.targets[i] && onReselect != null) {
    onReselect();
    return;
  }
  appState.goToTab(spec.targets[i], spec.home);
}

/// Thanh tab dưới cùng (điện thoại, < 600px).
class AppBottomNav extends StatelessWidget {
  final AppState appState;
  final NavSpec spec;

  /// Gọi khi chạm lại tab đang mở (quy ước mobile: cuộn về đầu trang).
  final VoidCallback? onReselect;
  const AppBottomNav({super.key, required this.appState, required this.spec, this.onReselect});

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: spec.selectedIndex,
      onDestinationSelected: (i) => _select(appState, spec, i, onReselect),
      destinations: spec.items
          .map((item) => NavigationDestination(icon: Icon(item.icon), label: item.label))
          .toList(),
    );
  }
}

/// Thanh điều hướng bên trái (tablet / desktop, >= 600px).
class AppNavRail extends StatelessWidget {
  final AppState appState;
  final NavSpec spec;
  final VoidCallback? onReselect;
  const AppNavRail({super.key, required this.appState, required this.spec, this.onReselect});

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    return LayoutBuilder(
      builder: (context, railConstraints) {
        final isShortHeight = railConstraints.maxHeight < 420;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: railConstraints.maxHeight),
            child: IntrinsicHeight(
              child: NavigationRail(
                extended: isDesktop && !isShortHeight,
                selectedIndex: spec.selectedIndex,
                onDestinationSelected: (i) => _select(appState, spec, i, onReselect),
                labelType: isDesktop
                    ? NavigationRailLabelType.none
                    : isShortHeight
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
                destinations: spec.items
                    .map((item) => NavigationRailDestination(icon: Icon(item.icon), label: Text(item.label)))
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}
