import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S04: Forgot & Reset Password Screen (Module 4)
// Giao diện theo design system: tiêu đề rõ, form có autofill, kiểm tra email
// trước khi gửi OTP, nút có trạng thái đang tải.
class S04ForgotPasswordScreen extends StatefulWidget {
  final AppState appState;
  const S04ForgotPasswordScreen({super.key, required this.appState});

  @override
  State<S04ForgotPasswordScreen> createState() => _S04ForgotPasswordScreenState();
}

class _S04ForgotPasswordScreenState extends State<S04ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController(text: 'customer@badminton.vn');
  final _newPassCtrl = TextEditingController(text: '123456');
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _newPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendResetOtp() async {
    if (_loading) return;
    final email = _emailCtrl.text.trim();
    String? error;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      error = 'Email chưa đúng định dạng.';
    } else if (_newPassCtrl.text.length < 6) {
      error = 'Mật khẩu mới cần ít nhất 6 ký tự.';
    }
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    setState(() => _loading = true);
    widget.appState.lastOtpEmail = email;
    widget.appState.lastOtpPurpose = 'RESET_PASSWORD';
    try {
      final res = await ApiService.post('/auth/send-otp', {
        'email': email,
        'purpose': 'RESET_PASSWORD',
      });
      if (res is Map && res['demoOtp'] != null) {
        widget.appState.lastDemoOtp = res['demoOtp'].toString();
      }
    } catch (_) {
      widget.appState.lastDemoOtp = '123456';
    }
    if (!mounted) return;
    setState(() => _loading = false);
    widget.appState.goTo('S03');
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(
      maxWidth: Responsive.defaultFormMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context).copyWith(top: 24),
        children: [
          const AuthHeader(
            icon: Icons.lock_reset,
            title: 'Quên mật khẩu',
            subtitle: 'Nhập email đã đăng ký. Chúng tôi sẽ gửi mã OTP để xác minh trước khi đặt mật khẩu mới.',
          ),
          const SizedBox(height: 28),
          AutofillGroup(
            child: Column(
              children: [
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email tài khoản',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _newPassCtrl,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onSubmitted: (_) => _sendResetOtp(),
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu mới',
                    helperText: 'Ít nhất 6 ký tự',
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
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Gửi mã OTP',
            icon: Icons.send_outlined,
            loading: _loading,
            onPressed: _sendResetOtp,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () => widget.appState.resetTo('S01'),
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Quay lại đăng nhập'),
            ),
          ),
        ],
      ),
    );
  }
}
