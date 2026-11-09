import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/booking_rules.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S23: Owner Payout & Settlement Screen (Luồng 3 + Module 4 OTP)
// Số tiền có thể giải ngân do MÁY CHỦ tính (availablePayoutGross trong dashboard chủ sân):
// doanh thu online (PayOS / Ví) của mọi cơ sở trừ phần đã gửi yêu cầu (trừ yêu cầu bị từ chối).
// Phí nền tảng 5%. Gửi yêu cầu cần OTP email (S03); xong thì tải lại dashboard.
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
  bool _sendingOtp = false;

  AppState get _app => widget.appState;

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _bankNoCtrl.dispose();
    _holderCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _app.refreshOwnerDashboard().catchError((Object e) => debugPrint('[S23] $e'));
  }

  Future<void> _refresh() async {
    try {
      await _app.refreshOwnerDashboard();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _requestPayoutWithOtp(num gross) async {
    if (gross <= 0 || _sendingOtp) return;
    if (_bankNameCtrl.text.trim().isEmpty || _bankNoCtrl.text.trim().length < 6 || _holderCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập đủ thông tin tài khoản ngân hàng.')),
      );
      return;
    }
    final venues = _app.ownerVenueList.isNotEmpty
        ? _app.ownerVenueList
        : OwnerFinance.ownerVenues(_app.venues, _app.userId);
    final draft = <String, dynamic>{
      if (venues.isNotEmpty) 'venueId': venues.last['id'],
      'ownerName': _app.fullName.split('(').first.trim(),
      'grossAmount': gross.toDouble(),
      'commissionFee': OwnerFinance.commissionOf(gross).toDouble(),
      'netPayoutAmount': OwnerFinance.netOf(gross).toDouble(),
      'bankName': _bankNameCtrl.text.trim(),
      'bankAccountNumber': _bankNoCtrl.text.trim(),
      'bankAccountHolder': _holderCtrl.text.trim().toUpperCase(),
      'status': 'PENDING',
    };
    // Máy chủ gửi OTP tới email của tài khoản chủ sân; S03 gửi yêu cầu kèm mã
    setState(() => _sendingOtp = true);
    try {
      await _app.requestAccountOtp('PAYOUT');
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingOtp = false);
      showApiError(context, e);
      return;
    }
    if (!mounted) return;
    setState(() => _sendingOtp = false);
    _app.pendingPayoutDraft = draft;
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
    final d = _app.ownerDashboard;
    final List<Map<String, dynamic>> items;
    final num gross;
    if (d.isNotEmpty) {
      items = const [];
      gross = UiFmt.toNum(d['availablePayoutGross'], 0);
    } else {
      // Chưa tải được dashboard: tạm tính trên các vé đã có trên máy
      items = OwnerFinance.settleable(
          _app.bookings, OwnerFinance.idsOf(OwnerFinance.ownerVenues(_app.venues, _app.userId)));
      gross = OwnerFinance.revenueOf(items);
    }
    final fee = OwnerFinance.commissionOf(gross);
    final net = OwnerFinance.netOf(gross);
    final percent = (OwnerFinance.commissionRate * 100).round();

    return ResponsiveCenter(
      maxWidth: Responsive.defaultFormMaxWidth,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                Text(d.isNotEmpty
                        ? 'Doanh thu online (VietQR / Ví) chưa giải ngân'
                        : 'Tạm tính từ ${items.length} vé online trên máy',
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
          if (gross <= 0)
            const NoteBox('Chưa có doanh thu online mới để giải ngân. Vé thanh toán qua VietQR hoặc Ví sẽ được cộng vào đây.')
          else ...[
            const NoteBox('Yêu cầu cần xác thực OTP qua email trước khi gửi tới Admin.', icon: Icons.shield_outlined),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Yêu cầu giải ngân ${UiFmt.vnd(net)}',
              icon: Icons.send_outlined,
              loading: _sendingOtp,
              onPressed: _sendingOtp ? null : () => _requestPayoutWithOtp(gross),
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
      ),
    );
  }
}
