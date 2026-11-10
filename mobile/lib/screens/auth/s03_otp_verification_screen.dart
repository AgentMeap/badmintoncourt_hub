import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
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
    final app = widget.appState;
    try {
      final withdraw = app.pendingWithdrawDraft;
      final payout = app.pendingPayoutDraft;
      if (app.lastOtpPurpose == 'WITHDRAW_WALLET' && withdraw != null) {
        await _withdraw(code, withdraw);
      } else if (app.lastOtpPurpose == 'PAYOUT' && payout != null) {
        await _requestPayout(code, payout);
      } else if (app.lastOtpPurpose == 'RESET_PASSWORD') {
        await _resetPassword(code);
      } else {
        await _verifyAccount(code);
      }
    } catch (e) {
      // Sai / hết hạn OTP, số dư không đủ, mất kết nối...: ở lại màn OTP để thử lại
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Rút tiền Ví (từ S27): máy chủ kiểm tra OTP, số dư, trừ ví và ghi giao dịch trong một bước.
  Future<void> _withdraw(String code, Map<String, dynamic> w) async {
    final app = widget.appState;
    final amount = asNum(w['amount']) ?? 0;
    final res = await Repos.wallet.withdraw(
      userId: app.userId,
      otpCode: code,
      amount: amount,
      bankName: '${w['bankName']}',
      bankAccountNumber: '${w['bankAccountNumber']}',
      bankAccountHolder: '${w['bankAccountHolder']}',
    );
    final balance = asNum(res['walletBalance']);
    if (balance != null) app.walletBalance = balance.toDouble();
    app.pendingWithdrawDraft = null;
    app.refreshWallet();
    if (!mounted) return;
    app.pushNotification(
      title: 'Đã gửi yêu cầu rút ${UiFmt.vnd(amount)}',
      body: 'Tiền sẽ về ${w['bankName']} • ${w['bankAccountNumber']} trong 1 - 2 ngày làm việc.',
      type: 'PAYMENT',
      targetScreen: 'S18',
      context: context,
    );
    // Quay về Ví, bỏ S27 và màn OTP khỏi lịch sử
    app.completeFlow('S18', flowStart: 'S27');
  }

  /// Giải ngân cho chủ sân (từ S23): máy chủ tự xác thực OTP trong cùng yêu cầu.
  Future<void> _requestPayout(String code, Map<String, dynamic> draft) async {
    final app = widget.appState;
    final saved = await Repos.owner.createPayoutRequest(
      ownerId: app.userId,
      venueId: draft['venueId'] ?? 1,
      grossAmount: asNum(draft['grossAmount']) ?? 0,
      bankName: '${draft['bankName']}',
      bankAccountNumber: '${draft['bankAccountNumber']}',
      bankAccountHolder: '${draft['bankAccountHolder']}',
      otpCode: code,
    );
    final request = {...draft, ...saved};
    app.payoutRequests.insert(0, request);
    app.pendingPayoutDraft = null;
    // Máy chủ đã trừ số tiền này khỏi phần có thể giải ngân: tải lại số liệu
    app.refreshOwnerDashboard().catchError((Object e) => debugPrint('[payout] $e'));
    if (!mounted) return;
    app.pushNotification(
      title: 'Đã xác thực OTP & gửi yêu cầu giải ngân #${request['payoutCode']}',
      body: 'Số tiền thực nhận ${UiFmt.vnd(asNum(request['netPayoutAmount']) ?? 0)} '
          'đang chờ Admin duyệt chuyển khoản.',
      type: 'PAYMENT',
      targetScreen: 'S23',
      context: context,
    );
    app.goTo('S23');
  }

  /// Quên mật khẩu (từ S04): đặt mật khẩu mới bằng OTP rồi quay về đăng nhập.
  Future<void> _resetPassword(String code) async {
    final app = widget.appState;
    final newPassword = app.pendingResetPassword;
    if (newPassword == null || newPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thiếu mật khẩu mới, vui lòng nhập lại ở bước trước.')),
      );
      return;
    }
    await Repos.auth.resetPassword(
      email: app.lastOtpEmail,
      otpCode: code,
      newPassword: newPassword,
    );
    app.pendingResetPassword = null;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đặt lại mật khẩu thành công. Vui lòng đăng nhập bằng mật khẩu mới.')),
    );
    app.resetTo('S01');
  }

  /// Xác thực email sau đăng ký: máy chủ trả về phiên đăng nhập của tài khoản mới.
  Future<void> _verifyAccount(String code) async {
    final app = widget.appState;
    final res = await Repos.auth.verifyRegistrationOtp(app.lastOtpEmail, code);
    if (res['id'] != null) await app.applyAuthResponse(res);
    if (!mounted) return;
    app.pushNotification(
      title: 'Xác thực OTP thành công',
      body: 'Tài khoản ${app.lastOtpEmail} đã được xác thực qua Email OTP.',
      type: 'SYSTEM',
      targetScreen: app.homeScreen,
      context: context,
    );
    // Xác thực xong: bắt đầu phiên mới, Back không quay lại màn OTP / đăng ký
    app.enterAfterLogin();
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
            'Mã có hiệu lực trong 5 phút, sai quá 5 lần cần gửi mã mới. '
            'Bạn có thể dán mã trực tiếp vào ô trên.'
            // Máy chủ chỉ trả mã demo khi bật chế độ demo (APP_DEMO_MODE)
            '${widget.appState.lastDemoOtp.isEmpty ? '' : ' (Mã demo: ${widget.appState.lastDemoOtp})'}',
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
