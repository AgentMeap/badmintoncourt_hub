import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S02: Register Screen
// Giao diện theo design system: chọn vai trò dạng thẻ icon, nhãn trình độ
// tiếng Việt, form có autofill, kiểm tra dữ liệu cơ bản trước khi gửi OTP.
class S02RegisterScreen extends StatefulWidget {
  final AppState appState;
  const S02RegisterScreen({super.key, required this.appState});

  @override
  State<S02RegisterScreen> createState() => _S02RegisterScreenState();
}

class _S02RegisterScreenState extends State<S02RegisterScreen> {
  final _nameCtrl = TextEditingController(text: 'Nguyễn Hữu Đạt');
  final _emailCtrl = TextEditingController(text: 'huudat.badminton@gmail.com');
  final _phoneCtrl = TextEditingController(text: '0909123456');
  final _passCtrl = TextEditingController(text: '123456');
  String _selectedRole = 'CUSTOMER';
  String _selectedSkill = 'TB_YEU';
  bool _obscure = true;
  bool _loading = false;

  static const _skills = {
    'NEWBIE': 'Mới chơi',
    'TB_YEU': 'Trung bình yếu',
    'TRUNG_BINH': 'Trung bình',
    'KHA': 'Khá',
  };

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_nameCtrl.text.trim().isEmpty) return 'Vui lòng nhập họ và tên.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_emailCtrl.text.trim())) {
      return 'Email chưa đúng định dạng.';
    }
    if (_passCtrl.text.length < 6) return 'Mật khẩu cần ít nhất 6 ký tự.';
    return null;
  }

  Future<void> _submitRegister() async {
    if (_loading) return;
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _loading = true);
    widget.appState.lastOtpEmail = _emailCtrl.text.trim();
    widget.appState.lastOtpPurpose = 'REGISTER';
    try {
      final res = await ApiService.post('/auth/register', {
        'fullName': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'password': _passCtrl.text,
        'role': _selectedRole,
        'skillLevel': _selectedSkill,
      });
      if (res is Map && res['demoOtp'] != null) {
        widget.appState.lastDemoOtp = res['demoOtp'].toString();
      }
    } catch (_) {
      widget.appState.lastDemoOtp = '482916';
    }
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Đã gửi mã OTP tới ${_emailCtrl.text} (mã demo: ${widget.appState.lastDemoOtp})',
        ),
      ),
    );
    widget.appState.goTo('S03');
  }

  Widget _roleCard(BuildContext context, String role, IconData icon, String title, String desc) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = _selectedRole == role;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? cs.primaryContainer : cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 1.6 : 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => setState(() => _selectedRole = role),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: selected ? cs.onPrimaryContainer : cs.primary),
                      const Spacer(),
                      Icon(
                        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 20,
                        color: selected ? cs.primary : cs.outline,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                  ),
                  Text(
                    desc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
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
        padding: Responsive.screenPadding(context).copyWith(top: 20),
        children: [
          const AuthHeader(
            icon: Icons.person_add_alt_1_outlined,
            title: 'Tạo tài khoản',
            subtitle: 'Mã xác thực OTP sẽ được gửi về email của bạn',
          ),
          const SizedBox(height: 24),
          const SectionHeader('Bạn là'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _roleCard(context, 'CUSTOMER', Icons.person_outline, 'Người chơi', 'Đặt sân, tìm kèo'),
              const SizedBox(width: 10),
              _roleCard(context, 'COURT_OWNER', Icons.storefront_outlined, 'Chủ sân',
                  'Quản lý cơ sở'),
            ],
          ),
          const SizedBox(height: 20),
          AutofillGroup(
            child: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(
                    labelText: 'Họ và tên',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    helperText: 'Dùng để nhận mã OTP',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu',
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
          if (_selectedRole == 'CUSTOMER') ...[
            const SizedBox(height: 20),
            const SectionHeader('Trình độ cầu lông'),
            Text(
              'Giúp gợi ý kèo giao lưu phù hợp với bạn.',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _skills.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _selectedSkill == e.key,
                    onSelected: (_) => setState(() => _selectedSkill = e.key),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Gửi mã OTP',
            icon: Icons.mark_email_read_outlined,
            loading: _loading,
            onPressed: _submitRegister,
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Đã có tài khoản?',
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              TextButton(
                onPressed: () => widget.appState.resetTo('S01'),
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                child: const Text('Đăng nhập'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
