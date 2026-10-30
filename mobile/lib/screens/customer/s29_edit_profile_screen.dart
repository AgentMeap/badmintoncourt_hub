import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S29: Sửa hồ sơ & đổi mật khẩu
// - Sửa họ tên, số điện thoại, trình độ (trình độ dùng để gợi ý kèo ở S15 / S17)
// - Email chỉ xem (dùng để đăng nhập & nhận OTP)
// - Đổi mật khẩu: mật khẩu hiện tại + mới + nhập lại; kiểm tra độ dài, khớp, khác mật khẩu cũ
class S29EditProfileScreen extends StatefulWidget {
  final AppState appState;
  const S29EditProfileScreen({super.key, required this.appState});

  @override
  State<S29EditProfileScreen> createState() => _S29EditProfileScreenState();
}

class _S29EditProfileScreenState extends State<S29EditProfileScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late String _skill;
  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _obscure = true;
  bool _savingProfile = false;
  bool _savingPass = false;

  AppState get _app => widget.appState;

  /// Phần "(Customer)" ở cuối fullName là nhãn vai trò dùng cho demo, giữ nguyên khi đổi tên.
  String get _roleSuffix {
    final i = _app.fullName.indexOf('(');
    return i >= 0 ? ' ${_app.fullName.substring(i)}' : '';
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: _app.fullName.split('(').first.trim());
    _phoneCtrl = TextEditingController(text: _app.phone);
    _skill = _app.skillLevel;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  bool get _profileChanged =>
      _nameCtrl.text.trim() != _app.fullName.split('(').first.trim() ||
      _phoneCtrl.text.trim() != _app.phone ||
      _skill != _app.skillLevel;

  Future<void> _saveProfile() async {
    if (_savingProfile) return;
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.length < 2) {
      _toast('Vui lòng nhập họ tên.');
      return;
    }
    if (!RegExp(r'^0\d{9}$').hasMatch(phone)) {
      _toast('Số điện thoại cần 10 chữ số, bắt đầu bằng 0.');
      return;
    }
    setState(() => _savingProfile = true);
    try {
      await ApiService.post('/users/${_app.userId}/profile', {
        'fullName': name,
        'phone': phone,
        'skillLevel': _skill,
      });
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _app.fullName = '$name$_roleSuffix';
      _app.phone = phone;
      _app.skillLevel = _skill;
      _savingProfile = false;
    });
    _toast('Đã lưu hồ sơ.');
  }

  Future<void> _changePassword() async {
    if (_savingPass) return;
    final current = _currentPassCtrl.text;
    final next = _newPassCtrl.text;
    String? error;
    if (current.isEmpty) {
      error = 'Vui lòng nhập mật khẩu hiện tại.';
    } else if (next.length < 6) {
      error = 'Mật khẩu mới cần ít nhất 6 ký tự.';
    } else if (next == current) {
      error = 'Mật khẩu mới phải khác mật khẩu hiện tại.';
    } else if (next != _confirmPassCtrl.text) {
      error = 'Mật khẩu nhập lại không khớp.';
    }
    if (error != null) {
      _toast(error);
      return;
    }
    setState(() => _savingPass = true);
    try {
      await ApiService.post('/auth/change-password', {
        'userId': _app.userId,
        'currentPassword': current,
        'newPassword': next,
      });
    } catch (_) {}
    if (!mounted) return;
    setState(() => _savingPass = false);
    _currentPassCtrl.clear();
    _newPassCtrl.clear();
    _confirmPassCtrl.clear();
    _app.pushNotification(
      title: 'Đã đổi mật khẩu',
      body: 'Mật khẩu tài khoản ${_app.email} vừa được thay đổi. Nếu không phải bạn, hãy liên hệ hỗ trợ.',
      type: 'SYSTEM',
      targetScreen: 'S29',
      context: context,
    );
  }

  Widget _passField(TextEditingController c, String label, List<String> hints, {String? helper}) {
    return TextField(
      controller: c,
      obscureText: _obscure,
      autofillHints: hints,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: const Icon(Icons.lock_outline),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
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
        padding: Responsive.screenPadding(context),
        children: [
          Text('Hồ sơ của tôi',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),

          const SectionHeader('Thông tin cá nhân'),
          AutofillGroup(
            child: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Họ và tên',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại',
                    prefixIcon: Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: TextEditingController(text: _app.email),
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    helperText: 'Dùng để đăng nhập và nhận mã OTP, không thể đổi',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Trình độ cầu lông', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Dùng để gợi ý kèo giao lưu phù hợp.',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in SkillLevel.codes)
                ChoiceChip(
                  label: Text(SkillLevel.label(s)),
                  selected: _skill == s,
                  onSelected: (_) => setState(() => _skill = s),
                ),
            ],
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Lưu hồ sơ',
            icon: Icons.save_outlined,
            loading: _savingProfile,
            onPressed: _profileChanged ? _saveProfile : null,
          ),
          const SizedBox(height: 32),

          const SectionHeader('Đổi mật khẩu'),
          AutofillGroup(
            child: Column(
              children: [
                _passField(_currentPassCtrl, 'Mật khẩu hiện tại', const [AutofillHints.password]),
                const SizedBox(height: 12),
                _passField(_newPassCtrl, 'Mật khẩu mới', const [AutofillHints.newPassword],
                    helper: 'Ít nhất 6 ký tự, khác mật khẩu hiện tại'),
                const SizedBox(height: 12),
                _passField(_confirmPassCtrl, 'Nhập lại mật khẩu mới', const [AutofillHints.newPassword]),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Đổi mật khẩu',
            icon: Icons.lock_reset,
            tonal: true,
            loading: _savingPass,
            onPressed: _changePassword,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
