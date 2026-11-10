import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/auth/google_auth_service.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S01: Login Screen
// Giao diện theo design system (skill ui-ux-pro-max): logo vector thay emoji,
// form hỗ trợ trình quản lý mật khẩu (autofill), hiện/ẩn mật khẩu.
// Đăng nhập Google (Android): Google -> Firebase Auth -> Firebase ID token -> POST /auth/google
// -> máy chủ kiểm tra token, tạo / tìm tài khoản và cấp JWT của app.
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
  bool _googleLoading = false;
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
    widget.appState.enterAfterLogin();
  }

  Future<void> _handleGoogleLogin() async {
    if (_loading || _googleLoading) return;
    setState(() => _googleLoading = true);
    try {
      final idToken = await GoogleAuthService.signInAndGetIdToken();
      if (idToken == null) {
        // Người dùng đóng hộp chọn tài khoản
        if (mounted) setState(() => _googleLoading = false);
        return;
      }
      final res = await Repos.auth.loginWithGoogle(idToken);
      await widget.appState.applyAuthResponse(res);
      if (!mounted) return;
      setState(() => _googleLoading = false);
      if (res['newUser'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tạo tài khoản thành công, Ví được tặng 200.000đ.')),
        );
      }
      widget.appState.enterAfterLogin();
    } catch (e) {
      // Đăng nhập Google thành công nhưng máy chủ từ chối: thoát Google để lần sau chọn lại tài khoản
      GoogleAuthService.signOut();
      if (!mounted) return;
      setState(() => _googleLoading = false);
      final message = e is GoogleAuthException ? e.message : ApiException.messageOf(e);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
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
            onPressed: _googleLoading ? null : _handleLogin,
          ),
          if (GoogleAuthService.isSupportedPlatform) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('hoặc',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: (_loading || _googleLoading) ? null : _handleGoogleLogin,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: _googleLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.account_circle_outlined),
                label: const Text('Tiếp tục với Google'),
              ),
            ),
          ],
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
        ],
      ),
    );
  }
}
