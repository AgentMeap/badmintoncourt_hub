import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/responsive.dart';
import 'app_navigation.dart';
import 'scroll_to_top.dart';
import 'screen_registry.dart';

/// "Master page" của app: khung cố định bao quanh mọi màn hình.
/// - AppBar: nút Back (màn con), tiêu đề, Trợ lý AI, Thông báo, menu tài khoản (giao diện sáng/tối, đăng xuất)
/// - Điều hướng thích ứng: thanh tab dưới (< 600px) hoặc rail bên trái (>= 600px)
/// - PopScope: phím Back Android đi lùi theo lịch sử, chỉ thoát app ở màn đầu tiên
/// - Thông báo mới: hỏi máy chủ 30 giây/lần khi app đang mở, hiện banner kèm nút "Xem"
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
        // Màn đăng nhập / đăng ký / OTP / quên mật khẩu: chưa đăng nhập -> ẩn thông báo, menu tài khoản
        final isAuthScreen = const {'S01', 'S02', 'S03', 'S04'}.contains(code);

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
                // Trợ lý AI chỉ dành cho người chơi
                if (appState.role == 'CUSTOMER' && !isAuthScreen)
                  IconButton(
                    tooltip: 'Trợ lý AI',
                    onPressed: () => appState.goTo('S17'),
                    icon: const Icon(Icons.smart_toy_outlined),
                  ),
                if (!isAuthScreen)
                  IconButton(
                    tooltip: 'Thông báo',
                    onPressed: () => appState.goTo('S05'),
                    icon: Badge(
                      isLabelVisible: appState.unreadNotificationCount > 0,
                      label: Text('${appState.unreadNotificationCount}'),
                      child: const Icon(Icons.notifications_outlined),
                    ),
                  ),
                if (!isAuthScreen) AccountMenuButton(appState: appState),
              ],
            ),
            // SafeArea: không bị tai thỏ / Dynamic Island / cạnh ngang che nội dung
            body: NotificationWatcher(
              appState: appState,
              child: SafeArea(
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

/// Hỏi thông báo mới định kỳ khi app ở tiền cảnh (dừng khi app chạy nền) và hiện banner
/// "Tin nhắn mới · Kèo X" / "Minh xin rời kèo"... với nút Xem mở đúng màn hình.
class NotificationWatcher extends StatefulWidget {
  final AppState appState;
  final Widget child;
  const NotificationWatcher({super.key, required this.appState, required this.child});

  @override
  State<NotificationWatcher> createState() => _NotificationWatcherState();
}

class _NotificationWatcherState extends State<NotificationWatcher> with WidgetsBindingObserver {
  Object? _shownId;

  AppState get _app => widget.appState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _app.addListener(_onAppChanged);
    _app.startNotificationPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _app.removeListener(_onAppChanged);
    _app.stopNotificationPolling();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _app.startNotificationPolling(); // quay lại app: hỏi ngay
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _app.stopNotificationPolling();
    }
  }

  void _onAppChanged() {
    final n = _app.incomingNotification;
    if (n == null || n['id'] == _shownId) return;
    _shownId = n['id'];
    _app.incomingNotification = null;
    if (_app.currentScreen == 'S05') return; // đang xem danh sách thông báo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final theme = Theme.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${n['title'] ?? 'Thông báo mới'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onInverseSurface, fontWeight: FontWeight.w700)),
              if ((n['body'] ?? '').toString().isNotEmpty)
                Text('${n['body']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onInverseSurface)),
            ],
          ),
          action: SnackBarAction(label: 'Xem', onPressed: () => _app.openNotification(n)),
        ));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Menu tài khoản trên AppBar (thay cho menu bên cũ): tên + vai trò, chọn giao diện sáng / tối, đăng xuất.
class AccountMenuButton extends StatelessWidget {
  final AppState appState;
  const AccountMenuButton({super.key, required this.appState});

  static const _roleLabels = {
    'CUSTOMER': 'Người chơi',
    'COURT_OWNER': 'Chủ sân',
    'ADMIN': 'Quản trị viên',
  };

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text('Bạn sẽ quay về màn hình đăng nhập.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Quay lại')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Đăng xuất')),
        ],
      ),
    );
    if (ok == true) appState.logout();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Tài khoản',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (v) {
        switch (v) {
          case 'system':
            appState.setThemeMode(ThemeMode.system);
          case 'light':
            appState.setThemeMode(ThemeMode.light);
          case 'dark':
            appState.setThemeMode(ThemeMode.dark);
          case 'logout':
            _logout(context);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(appState.fullName.split('(').first.trim(),
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface)),
              Text(_roleLabels[appState.role] ?? appState.role,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem<String>(
          value: 'system',
          checked: appState.themeMode == ThemeMode.system,
          child: const Text('Giao diện theo hệ thống'),
        ),
        CheckedPopupMenuItem<String>(
          value: 'light',
          checked: appState.themeMode == ThemeMode.light,
          child: const Text('Giao diện sáng'),
        ),
        CheckedPopupMenuItem<String>(
          value: 'dark',
          checked: appState.themeMode == ThemeMode.dark,
          child: const Text('Giao diện tối'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'logout',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Đăng xuất'),
          ),
        ),
      ],
    );
  }
}

