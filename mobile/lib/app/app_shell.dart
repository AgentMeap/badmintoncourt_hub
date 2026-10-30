import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/responsive.dart';
import 'app_drawer.dart';
import 'app_navigation.dart';
import 'scroll_to_top.dart';
import 'screen_registry.dart';

/// "Master page" của app: khung cố định bao quanh mọi màn hình.
/// - AppBar: nút Back (màn con) hoặc menu (màn gốc), tiêu đề, Trợ lý AI, Thông báo
/// - Drawer: menu demo 26 màn + chọn sáng/tối
/// - Điều hướng thích ứng: thanh tab dưới (< 600px) hoặc rail bên trái (>= 600px)
/// - PopScope: phím Back Android đi lùi theo lịch sử, chỉ thoát app ở màn đầu tiên
class AppShell extends StatelessWidget {
  final AppState appState;
  const AppShell({super.key, required this.appState});

  /// Khóa tới nút "Lên đầu trang" để thanh tab gọi cuộn về đầu khi chạm lại tab đang mở.
  static final GlobalKey<ScrollToTopHostState> _scrollHostKey = GlobalKey<ScrollToTopHostState>();

  /// Màn không dùng nút "Lên đầu trang": Trợ lý AI (khung chat neo ở dưới cùng).
  static const _noScrollToTop = {'S17'};

  void _scrollToTop() => _scrollHostKey.currentState?.scrollToTop();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final code = appState.currentScreen;
        final navSpec = NavSpec.resolve(appState);
        // Màn gốc: các tab + màn đăng nhập -> hiện nút menu; màn con -> nút Back bên trái.
        final isRootScreen = code == 'S01' || (navSpec?.isRoot(code) ?? false);
        final showBack = appState.canGoBack && !isRootScreen;
        final isMobile = Responsive.isMobile(context);

        return PopScope(
          canPop: !appState.canGoBack,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) appState.goBack();
          },
          child: Scaffold(
            appBar: AppBar(
              leading: showBack
                  ? IconButton(
                      tooltip: 'Quay lại',
                      onPressed: appState.goBack,
                      icon: const Icon(Icons.arrow_back),
                    )
                  : null,
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              // Giới hạn 1 dòng + "…" để không tràn trên màn hình 360px
              title: Text(
                ScreenRegistry.titleOf(code),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onPrimary,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Trợ lý AI',
                  onPressed: () => appState.goTo('S17'),
                  icon: const Icon(Icons.smart_toy_outlined),
                ),
                IconButton(
                  tooltip: 'Thông báo',
                  onPressed: () => appState.goTo('S05'),
                  icon: Badge(
                    isLabelVisible: appState.unreadNotificationCount > 0,
                    label: Text('${appState.unreadNotificationCount}'),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                ),
              ],
            ),
            drawer: AppDrawer(appState: appState),
            // SafeArea: không bị tai thỏ / Dynamic Island / cạnh ngang che nội dung
            body: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!isMobile && navSpec != null) ...[
                    AppNavRail(appState: appState, spec: navSpec, onReselect: _scrollToTop),
                    const VerticalDivider(width: 1, thickness: 1),
                  ],
                  Expanded(
                    child: ScrollToTopHost(
                      key: _scrollHostKey,
                      screenKey: code,
                      enabled: !_noScrollToTop.contains(code),
                      child: ScreenRegistry.of(code).builder(appState),
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar:
                (isMobile && navSpec != null)
                ? AppBottomNav(appState: appState, spec: navSpec, onReselect: _scrollToTop)
                : null,
          ),
        );
      },
    );
  }
}
