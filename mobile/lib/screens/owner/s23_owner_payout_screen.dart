import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/booking_rules.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S23: Owner Payout & Settlement Screen (Luồng 3 + Module 4 OTP)
// Giao diện theo design system + sửa logic: số tiền giải ngân trước đây gán cứng
// 15.000.000đ. Giờ được TÍNH từ các vé online đã thu hộ (PayOS / Ví) chưa nằm trong
// yêu cầu giải ngân nào; phí 5% theo OwnerFinance. Vé đã đưa vào yêu cầu sẽ được
// đánh dấu (ở S03 sau khi xác thực OTP) để không bị giải ngân 2 lần.
class S23OwnerPayoutScreen extends StatefulWidget {
  final AppState appState;
  const S23OwnerPayoutScreen({super.key, required this.appState});

  @override
  State<S23OwnerPayoutScreen> createState() => _S23OwnerPayoutScreenState();
}

class _S23OwnerPayoutScreenState extends State<S23OwnerPayoutScreen> {
  final _bankNameCtrl = TextEditingController(text: 'Vietcombank');
  final _bankNoCtrl = TextEditingController(text: '0071001234567');
  final _holderCtrl = TextEditingController(text: 'TRAN CHU SAN');

  AppState get _app => widget.appState;

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _bankNoCtrl.dispose();
    _holderCtrl.dispose();
    super.dispose();
  }

  void _requestPayoutWithOtp(List<Map<String, dynamic>> items, num gross) {
    if (items.isEmpty || gross <= 0) return;
    if (_bankNameCtrl.text.trim().isEmpty || _bankNoCtrl.text.trim().length < 6 || _holderCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập đủ thông tin tài khoản ngân hàng.')),
      );
      return;
    }
    final venueNames = {for (final b in items) '${b['venueName']}'};
    final stamp = DateTime.now().millisecondsSinceEpoch % 10000;
    _app.lastOtpEmail = _app.email;
    _app.lastOtpPurpose = 'PAYOUT';
    _app.pendingPayoutDraft = {
      'id': stamp,
      'payoutCode': 'PO-$stamp',
      'venueId': items.first['venueId'],
      'venueName': venueNames.length == 1 ? venueNames.first : '${venueNames.length} cơ sở',
      'ownerName': _app.fullName.split('(').first.trim(),
      'grossAmount': gross.toDouble(),
      'commissionFee': OwnerFinance.commissionOf(gross).toDouble(),
      'netPayoutAmount': OwnerFinance.netOf(gross).toDouble(),
      'bankName': _bankNameCtrl.text.trim(),
      'bankAccountNumber': _bankNoCtrl.text.trim(),
      'bankAccountHolder': _holderCtrl.text.trim().toUpperCase(),
      'bookingCodes': [for (final b in items) b['bookingCode']],
      'status': 'PENDING',
      'createdAt': 'Vừa xong',
    };
    _app.goTo('S03');
  }

  static (String, IconData, Color, Color) _payoutStatus(ColorScheme cs, String? s) => switch (s) {
        'APPROVED' || 'PAID' => ('Đã chuyển', Icons.check_circle_outline, cs.primaryContainer, cs.onPrimaryContainer),
        'REJECTED' => ('Từ chối', Icons.block, cs.errorContainer, cs.onErrorContainer),
        _ => ('Chờ duyệt', Icons.hourglass_top_rounded, WarningTone.container(cs), WarningTone.onContainer(cs)),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ids = OwnerFinance.idsOf(OwnerFinance.ownerVenues(_app.venues, _app.userId));
    final items = OwnerFinance.settleable(_app.bookings, ids);
    final gross = OwnerFinance.revenueOf(items);
    final fee = OwnerFinance.commissionOf(gross);
    final net = OwnerFinance.netOf(gross);
    final percent = (OwnerFinance.commissionRate * 100).round();

    return ResponsiveCenter(
      maxWidth: Responsive.defaultFormMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context),
        children: [
          Text('Đối soát & giải ngân',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),

          // Số dư có thể rút
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(24)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Thực nhận có thể giải ngân',
                    style: theme.textTheme.labelLarge?.copyWith(color: cs.onPrimary.withValues(alpha: 0.85))),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(UiFmt.vnd(net),
                      style: theme.textTheme.displaySmall?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 4),
                Text('Từ ${items.length} vé online đã thu hộ',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onPrimary.withValues(alpha: 0.85))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SurfaceCard(
            child: Column(
              children: [
                InfoRow(icon: Icons.receipt_long_outlined, label: 'Doanh thu thu hộ', value: UiFmt.vnd(gross)),
                InfoRow(icon: Icons.percent, label: 'Phí nền tảng ($percent%)', value: '-${UiFmt.vnd(fee)}'),
                Divider(height: 16, color: cs.outlineVariant),
                InfoRow(icon: Icons.account_balance_wallet_outlined, label: 'Thực nhận', value: UiFmt.vnd(net), emphasize: true),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const SectionHeader('Tài khoản nhận tiền'),
          TextField(
            controller: _bankNameCtrl,
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
            decoration: const InputDecoration(
              labelText: 'Chủ tài khoản',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const NoteBox('Chưa có doanh thu online mới để giải ngân. Vé thanh toán qua VietQR hoặc Ví sẽ được cộng vào đây.')
          else ...[
            const NoteBox('Yêu cầu cần xác thực OTP qua email trước khi gửi tới Admin.', icon: Icons.shield_outlined),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Yêu cầu giải ngân ${UiFmt.vnd(net)}',
              icon: Icons.send_outlined,
              onPressed: () => _requestPayoutWithOtp(items, gross),
            ),
          ],
          const SizedBox(height: 24),

          SectionHeader('Lịch sử yêu cầu',
              trailing: Text('${_app.payoutRequests.length}',
                  style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant))),
          if (_app.payoutRequests.isEmpty)
            const EmptyState(icon: Icons.history, title: 'Chưa có yêu cầu giải ngân')
          else
            for (final pr in _app.payoutRequests)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  padding: const EdgeInsets.all(14),
                  child: Builder(builder: (context) {
                    final (label, icon, bg, fg) = _payoutStatus(cs, pr['status']?.toString());
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('#${pr['payoutCode']} • ${UiFmt.vnd(UiFmt.toNum(pr['netPayoutAmount'], 0))}',
                                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              Text(
                                '${pr['bankName']} • ${pr['bankAccountNumber']} • ${pr['createdAt'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
                          child: Text.rich(
                            TextSpan(children: [
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(icon, size: 14, color: fg),
                                ),
                              ),
                              TextSpan(text: label),
                            ]),
                            style: theme.textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
