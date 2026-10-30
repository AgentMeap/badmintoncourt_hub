import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S03: OTP Verification Screen (Module 4)
// Giao diện theo design system. Theo quy tắc "Accessible Authentication" của skill:
// một ô nhập OTP duy nhất, cho phép DÁN mã và tự điền mã từ SMS/email
// (AutofillHints.oneTimeCode), chỉ nhận chữ số.
class S03OtpVerificationScreen extends StatefulWidget {
  final AppState appState;
  const S03OtpVerificationScreen({super.key, required this.appState});

  @override
  State<S03OtpVerificationScreen> createState() => _S03OtpVerificationScreenState();
}

class _S03OtpVerificationScreenState extends State<S03OtpVerificationScreen> {
  late final TextEditingController _otpCtrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _otpCtrl = TextEditingController(text: widget.appState.lastDemoOtp);
  }

  @override
  void dispose() {
    _otpCtrl.dispose();
    super.dispose();
  }

  String get _purposeLabel {
    switch (widget.appState.lastOtpPurpose) {
      case 'REGISTER':
        return 'Xác thực tài khoản mới';
      case 'RESET_PASSWORD':
        return 'Đặt lại mật khẩu';
      case 'PAYOUT':
        return 'Xác nhận yêu cầu giải ngân';
      case 'WITHDRAW_WALLET':
        return 'Xác nhận rút tiền từ Ví';
      default:
        return widget.appState.lastOtpPurpose;
    }
  }

  Future<void> _verifyOtp() async {
    if (_loading) return;
    final code = _otpCtrl.text.trim();
    if (code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập đủ 6 chữ số OTP.')),
      );
      return;
    }
    setState(() => _loading = true);

    try {
      await ApiService.post('/auth/verify-otp', {
        'email': widget.appState.lastOtpEmail,
        'otpCode': code,
      });
    } catch (_) {}

    if (!mounted) return;
    setState(() => _loading = false);

    if (widget.appState.lastOtpPurpose == 'PAYOUT' && widget.appState.pendingPayoutDraft != null) {
      final draft = widget.appState.pendingPayoutDraft!;
      widget.appState.payoutRequests.insert(0, draft);
      widget.appState.pendingPayoutDraft = null;
      // Đánh dấu các vé đã đưa vào yêu cầu giải ngân để không bị tính 2 lần
      final codes = (draft['bookingCodes'] as List?)?.map((e) => '$e').toSet() ?? const <String>{};
      for (final b in widget.appState.bookings) {
        if (codes.contains('${b['bookingCode']}')) b['payoutCode'] = draft['payoutCode'];
      }
      widget.appState.pushNotification(
        title: 'Đã xác thực OTP & gửi yêu cầu giải ngân #${draft['payoutCode']}',
        body: 'Số tiền thực nhận ${draft['netPayoutAmount']}đ đang chờ Admin duyệt chuyển khoản.',
        type: 'PAYMENT',
        targetScreen: 'S23',
        context: context,
      );
      widget.appState.goTo('S23');
      return;
    }

    widget.appState.pushNotification(
      title: 'Xác thực OTP thành công',
      body: 'Tài khoản ${widget.appState.lastOtpEmail} đã được xác thực qua Email OTP.',
      type: 'SYSTEM',
      targetScreen: 'S06',
      context: context,
    );
    // Xác thực xong: bắt đầu phiên mới, Back không quay lại màn OTP / đăng ký
    widget.appState.resetTo(widget.appState.role == 'COURT_OWNER' ? 'S19' : 'S06');
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
          AuthHeader(
            icon: Icons.mark_email_unread_outlined,
            title: 'Nhập mã xác thực',
            subtitle: 'Mã 6 chữ số đã được gửi tới\n${widget.appState.lastOtpEmail}',
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _purposeLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _otpCtrl,
            autofocus: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) {
              setState(() {});
              if (v.length == 6) FocusScope.of(context).unfocus();
            },
            onSubmitted: (_) => _verifyOtp(),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 14,
            ),
            decoration: InputDecoration(
              hintText: '••••••',
              counterText: '${_otpCtrl.text.length}/6',
              filled: true,
              fillColor: cs.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: cs.primary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 8),
          NoteBox(
            'Mã có hiệu lực trong 5 phút. Bạn có thể dán mã trực tiếp vào ô trên. '
            '(Mã demo: ${widget.appState.lastDemoOtp})',
            icon: Icons.timer_outlined,
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Xác nhận',
            icon: Icons.check_circle_outline,
            loading: _loading,
            onPressed: _otpCtrl.text.length == 6 ? _verifyOtp : null,
          ),
        ],
      ),
    );
  }
}
