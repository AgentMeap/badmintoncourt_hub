import 'package:flutter/material.dart';
import '../core/app_state.dart';
import 'screen_registry.dart';

/// Menu bên (Drawer) phục vụ demo PRM393: chọn giao diện sáng/tối và mở nhanh 26 màn hình.
class AppDrawer extends StatelessWidget {
  final AppState appState;
  const AppDrawer({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final code = appState.currentScreen;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: cs.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Danh mục 26 màn hình (PRM393)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Vai trò hiện tại: ${appState.role}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onPrimary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            // Chọn giao diện sáng / tối (phục vụ demo dark mode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined),
                      tooltip: 'Theo hệ thống',
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      tooltip: 'Giao diện sáng',
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      tooltip: 'Giao diện tối',
                    ),
                  ],
                  selected: {appState.themeMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => appState.setThemeMode(s.first),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: ScreenRegistry.all.map((e) {
                  final active = e.code == code;
                  return ListTile(
                    selected: active,
                    leading: Icon(
                      active ? Icons.radio_button_checked : Icons.circle_outlined,
                      size: 16,
                    ),
                    title: Text(e.fullTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      Navigator.pop(context);
                      appState.goTo(e.code);
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
