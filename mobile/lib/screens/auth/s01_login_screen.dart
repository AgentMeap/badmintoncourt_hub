import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S01: Login Screen
// Giao diện theo design system (skill ui-ux-pro-max): logo vector thay emoji,
// form hỗ trợ trình quản lý mật khẩu (autofill), hiện/ẩn mật khẩu,
// khối chuyển nhanh 3 vai trò demo dạng ô icon + nhãn.
class S01LoginScreen extends StatefulWidget {
  final AppState appState;
  const S01LoginScreen({super.key, required this.appState});

  @override
  State<S01LoginScreen> createState() => _S01LoginScreenState();
}

class _S01LoginScreenState extends State<S01LoginScreen> {
  final _emailCtrl = TextEditingController(text: 'customer@badminton.vn');
  final _passCtrl = TextEditingController(text: '123456');
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_loading) return;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || _passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập email và mật khẩu.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await Repos.auth.login(email, _passCtrl.text);
      await widget.appState.applyAuthResponse(res);
    } catch (e) {
      // Sai mật khẩu, tài khoản bị khóa hoặc không kết nối được máy chủ: ở lại màn đăng nhập
      if (mounted) {
        setState(() => _loading = false);
        showApiError(context, e);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    widget.appState.resetTo(widget.appState.homeScreen);
    widget.appState.syncFromBackend();
  }

  /// Đăng nhập nhanh tài khoản demo theo vai trò.
  Future<void> _demoLogin(String role) async {
    if (_loading) return;
    setState(() => _loading = true);
    // Thành công thì AppState đã chuyển sang màn chính (màn này bị gỡ khỏi cây widget)
    final error = await widget.appState.switchDemoRole(role);
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Widget _roleTile(BuildContext context, IconData icon, String label, String role) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Expanded(
      child: Material(
        color: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cs.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _loading ? null : () => _demoLogin(role),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Column(
              children: [
                Icon(icon, color: cs.primary),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ResponsiveCenter(
      maxWidth: Responsive.defaultFormMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context).copyWith(top: 24),
        children: [
          const AuthHeader(
            title: 'Badminton Court Hub',
            subtitle: 'Đặt sân, tìm kèo giao lưu và quản lý cơ sở cầu lông',
          ),
          const SizedBox(height: 28),
          AutofillGroup(
            child: Column(
              children: [
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email, AutofillHints.username],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _handleLogin(),
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => widget.appState.goTo('S04'),
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              child: const Text('Quên mật khẩu?'),
            ),
          ),
          const SizedBox(height: 4),
          PrimaryButton(
            label: 'Đăng nhập',
            icon: Icons.login,
            loading: _loading,
            onPressed: _handleLogin,
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Chưa có tài khoản?',
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              TextButton(
                onPressed: () => widget.appState.goTo('S02'),
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                child: const Text('Đăng ký ngay'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Chuyển nhanh vai trò (phục vụ thuyết trình)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.science_outlined, size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Demo: vào nhanh theo vai trò',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _roleTile(context, Icons.person_outline, 'Người chơi', 'CUSTOMER'),
                    const SizedBox(width: 8),
                    _roleTile(context, Icons.storefront_outlined, 'Chủ sân', 'COURT_OWNER'),
                    const SizedBox(width: 8),
                    _roleTile(context, Icons.admin_panel_settings_outlined, 'Quản trị', 'ADMIN'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
