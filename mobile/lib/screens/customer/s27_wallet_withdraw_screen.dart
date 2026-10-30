import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S27: Rút tiền từ Ví Cầu Lông về ngân hàng
// Sửa lỗi luồng: trước đây nút "Rút tiền" ở S18 nhảy thẳng vào OTP mà không hỏi
// rút bao nhiêu, về tài khoản nào. Giờ: nhập số tiền + tài khoản -> kiểm tra hợp lệ
// -> xác thực OTP (S03) -> S03 trừ ví, ghi lịch sử giao dịch.
class S27WalletWithdrawScreen extends StatefulWidget {
  final AppState appState;
  const S27WalletWithdrawScreen({super.key, required this.appState});

  /// Số tiền rút tối thiểu mỗi lần.
  static const int minAmount = 50000;

  @override
  State<S27WalletWithdrawScreen> createState() => _S27WalletWithdrawScreenState();
}

class _S27WalletWithdrawScreenState extends State<S27WalletWithdrawScreen> {
  final _amountCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController(text: 'Vietcombank');
  final _bankNoCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();

  AppState get _app => widget.appState;

  @override
  void initState() {
    super.initState();
    // Gợi ý tên chủ tài khoản từ họ tên (không dấu, in hoa) để người dùng đỡ gõ
    _holderCtrl.text = _removeDiacritics(_app.fullName.split('(').first.trim()).toUpperCase();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankNoCtrl.dispose();
    _holderCtrl.dispose();
    super.dispose();
  }

  int get _amount => int.tryParse(_amountCtrl.text) ?? 0;
  int get _balance => _app.walletBalance.floor();

  String? get _amountError {
    if (_amountCtrl.text.isEmpty) return null;
    if (_amount < S27WalletWithdrawScreen.minAmount) {
      return 'Tối thiểu ${UiFmt.vnd(S27WalletWithdrawScreen.minAmount)}';
    }
    if (_amount > _balance) return 'Vượt quá số dư (${UiFmt.vnd(_balance)})';
    return null;
  }

  bool get _valid =>
      _amountCtrl.text.isNotEmpty &&
      _amountError == null &&
      _bankNameCtrl.text.trim().isNotEmpty &&
      _bankNoCtrl.text.trim().length >= 6 &&
      _holderCtrl.text.trim().isNotEmpty;

  void _setAmount(int v) {
    _amountCtrl.text = '$v';
    _amountCtrl.selection = TextSelection.collapsed(offset: _amountCtrl.text.length);
    setState(() {});
  }

  void _continueToOtp() {
    if (!_valid) return;
    _app.pendingWithdrawDraft = {
      'code': 'WD-${DateTime.now().millisecondsSinceEpoch % 100000}',
      'amount': _amount.toDouble(),
      'bankName': _bankNameCtrl.text.trim(),
      'bankAccountNumber': _bankNoCtrl.text.trim(),
      'bankAccountHolder': _holderCtrl.text.trim().toUpperCase(),
    };
    _app.lastOtpEmail = _app.email;
    _app.lastOtpPurpose = 'WITHDRAW_WALLET';
    _app.goTo('S03');
  }

  static String _removeDiacritics(String s) {
    const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ'
        'ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ';
    const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd'
        'AAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';
    final buf = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      buf.write(i >= 0 ? to[i] : ch);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final after = (_balance - _amount).clamp(0, _balance);
    final quick = <int>[100000, 200000, 500000].where((v) => v <= _balance).toList();
    final canWithdraw = _balance >= S27WalletWithdrawScreen.minAmount;

    return Column(
      children: [
        Expanded(
          child: ResponsiveCenter(
            maxWidth: Responsive.defaultFormMaxWidth,
            child: ListView(
              padding: Responsive.screenPadding(context),
              children: [
                Text('Rút tiền về ngân hàng',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),

                // Số dư hiện tại
                SurfaceCard(
                  color: cs.primaryContainer.withValues(alpha: 0.4),
                  borderColor: cs.primary.withValues(alpha: 0.3),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Số dư khả dụng',
                            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                      Text(UiFmt.vnd(_balance),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                if (!canWithdraw)
                  NoteBox(
                    'Số dư chưa đủ để rút (tối thiểu ${UiFmt.vnd(S27WalletWithdrawScreen.minAmount)}).',
                    tone: NoteTone.warning,
                  )
                else ...[
                  const SectionHeader('Số tiền muốn rút'),
                  TextField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      hintText: '0',
                      suffixText: 'đ',
                      errorText: _amountError,
                      helperText: _amountCtrl.text.isEmpty || _amountError != null
                          ? 'Tối thiểu ${UiFmt.vnd(S27WalletWithdrawScreen.minAmount)}'
                          : '${UiFmt.vnd(_amount)} • Còn lại ${UiFmt.vnd(after)}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final v in quick)
                        ActionChip(label: Text(UiFmt.k(v)), onPressed: () => _setAmount(v)),
                      ActionChip(
                        avatar: const Icon(Icons.select_all, size: 18),
                        label: const Text('Rút hết'),
                        onPressed: () => _setAmount(_balance),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  const SectionHeader('Tài khoản nhận'),
                  TextField(
                    controller: _bankNameCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Ngân hàng',
                      prefixIcon: Icon(Icons.account_balance_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bankNoCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Số tài khoản',
                      prefixIcon: Icon(Icons.numbers),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _holderCtrl,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Chủ tài khoản',
                      helperText: 'Viết hoa, không dấu, đúng như trên thẻ ngân hàng',
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const NoteBox(
                    'Bạn sẽ nhận mã OTP qua email để xác nhận. Tiền thường về tài khoản trong 1 - 2 ngày làm việc.',
                    icon: Icons.shield_outlined,
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        if (canWithdraw)
          BottomActionBar(
            summary: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Số tiền rút',
                    style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    UiFmt.vnd(_amountError == null ? _amount : 0),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800, color: cs.primary),
                  ),
                ),
              ],
            ),
            action: FilledButton.icon(
              onPressed: _valid ? _continueToOtp : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Xác thực OTP'),
            ),
          ),
      ],
    );
  }
}
