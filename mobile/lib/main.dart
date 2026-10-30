import 'package:flutter/material.dart';
import 'app/app_shell.dart';
import 'app/app_theme.dart';
import 'core/app_state.dart';

void main() {
  runApp(const BadmintonV2App());
}

/// Gốc ứng dụng: tạo AppState, áp Theme sáng/tối, gắn khung chung (AppShell).
/// Khung, điều hướng, menu và danh sách màn hình nằm trong thư mục lib/app/.
class BadmintonV2App extends StatefulWidget {
  final AppState? appState;
  const BadmintonV2App({super.key, this.appState});

  @override
  State<BadmintonV2App> createState() => _BadmintonV2AppState();
}

class _BadmintonV2AppState extends State<BadmintonV2App> {
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = widget.appState ?? AppState();
    _appState.syncFromBackend();
  }

  @override
  Widget build(BuildContext context) {
    // Chỉ dựng lại MaterialApp khi đổi chế độ sáng/tối; phần còn lại do AppShell tự lắng nghe.
    return ListenableBuilder(
      listenable: _appState,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Badminton Court Hub V2',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: _appState.themeMode,
        home: AppShell(appState: _appState),
      ),
    );
  }
}
