import 'dart:async';
import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/booking_rules.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S10: Checkout & Payment Method Screen
// Thiết kế lại theo design system "Badminton Hub" (skill ui-ux-pro-max):
// thanh tiến trình 3 bước, đồng hồ giữ chỗ đếm ngược thật, chọn phương thức
// dạng thẻ radio, nút thanh toán cố định ở đáy.
class S10CheckoutScreen extends StatefulWidget {
  final AppState appState;
  const S10CheckoutScreen({super.key, required this.appState});

  @override
  State<S10CheckoutScreen> createState() => _S10CheckoutScreenState();
}

enum _PayMethod { payos, wallet }

class _S10CheckoutScreenState extends State<S10CheckoutScreen> {
  static const int _holdSeconds = 5 * 60;
  int _remaining = _holdSeconds;
  Timer? _timer;
  _PayMethod _method = _PayMethod.payos;
  bool _processing = false;

  AppState get appState => widget.appState;

  @override
  void initState() {
    super.initState();
    // Đếm ngược theo mốc hết hạn lưu trong booking (tạo ở S09)
    final b = appState.selectedBooking ?? appState.bookings.first;
    final expiresAt = b['holdExpiresAt'];
    if (expiresAt is int) {
      final left = (expiresAt - DateTime.now().millisecondsSinceEpoch) ~/ 1000;
      _remaining = left.clamp(0, _holdSeconds).toInt();
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _remaining = _remaining > 0 ? _remaining - 1 : 0;
      });
      if (_remaining == 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _countdown {
    final m = (_remaining ~/ 60).toString().padLeft(2, '0');
    final s = (_remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _startPayosQr() async {
    final b = appState.selectedBooking ?? appState.bookings.first;
    final orderCode = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    Map<String, dynamic> payment = {
      'payosOrderCode': orderCode,
      'amount': b['totalPrice'],
      'qrCodeData': 'PAYOS-VIETQR-${b['bookingCode']}-$orderCode',
      'status': 'PENDING',
    };

    try {
      final res = await ApiService.post('/payments/create-payos', {
        'bookingId': b['id'],
      });
      if (res is Map && res['payment'] is Map) {
        payment = Map<String, dynamic>.from(res['payment']);
      }
    } catch (_) {}

    appState.activePayosPayment = payment;
    appState.goTo('S11');
  }

  Future<void> _payWithWallet(BuildContext context) async {
    final b = appState.selectedBooking ?? appState.bookings.first;
    final price = (b['totalPrice'] as num).toDouble();
    if (appState.walletBalance < price) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Số dư Ví không đủ. Vui lòng chọn thanh toán VietQR.')),
      );
      return;
    }

    appState.walletBalance -= price;
    b['status'] = 'CONFIRMED';
    b['paymentMethod'] = 'WALLET';
    appState.bookings.removeWhere((item) => item['bookingCode'] == b['bookingCode']);
    appState.bookings.insert(0, b);
    appState.walletTransactions.insert(0, {
      'title': 'Thanh toán đặt sân ${b['bookingCode']}',
      'amount': -price,
      'type': 'BOOKING_PAYMENT',
      'createdAt': 'Vừa xong',
    });

    appState.pushNotification(
      title: 'Thanh toán bằng Ví Cầu Lông thành công',
      body: 'Vé ${b['bookingCode']} (${b['courtName']}, ${b['startTime']}-${b['endTime']}) đã xác nhận.',
      type: 'PAYMENT',
      targetScreen: 'S13',
      context: context,
    );
    // Kết thúc luồng đặt sân: Back từ vé không quay lại màn thanh toán
    appState.justPaidBookingCode = b['bookingCode']?.toString();
    appState.completeFlow('S13');
  }

  Future<void> _pay(BuildContext context) async {
    if (_processing || _remaining == 0) return;
    setState(() => _processing = true);
    if (_method == _PayMethod.payos) {
      await _startPayosQr();
    } else {
      await _payWithWallet(context);
    }
    if (mounted) setState(() => _processing = false);
  }

  Widget _holdBanner(ThemeData theme) {
    final cs = theme.colorScheme;
    final expired = _remaining == 0;
    final urgent = _remaining <= 60;
    final bg = expired
        ? cs.errorContainer
        : urgent
            ? WarningTone.container(cs)
            : cs.secondaryContainer;
    final fg = expired
        ? cs.onErrorContainer
        : urgent
            ? WarningTone.onContainer(cs)
            : cs.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(expired ? Icons.timer_off_outlined : Icons.timer_outlined, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              expired
                  ? 'Hết thời gian giữ chỗ. Vui lòng chọn lại khung giờ.'
                  : 'Sân đang được giữ cho bạn',
              style: theme.textTheme.bodyMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          if (expired)
            TextButton(
              onPressed: () => appState.goTo('S09'),
              style: TextButton.styleFrom(foregroundColor: fg),
              child: const Text('Chọn lại'),
            )
          else
            Text(
              _countdown,
              style: theme.textTheme.titleMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }

  Widget _methodCard(
    ThemeData theme, {
    required _PayMethod value,
    required IconData icon,
    required String title,
    required String subtitle,
    String? badge,
    bool enabled = true,
  }) {
    final cs = theme.colorScheme;
    final selected = _method == value;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: selected ? cs.primaryContainer.withValues(alpha: 0.45) : cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => setState(() => _method = value) : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(title,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          if (badge != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.tertiaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                badge,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onTertiaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: enabled ? cs.onSurfaceVariant : cs.error,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? cs.primary : cs.outline,
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
    final b = appState.selectedBooking ?? appState.bookings.first;
    final total = UiFmt.toNum(b['totalPrice'], 0);
    final start = b['startTime']?.toString() ?? '';
    final end = b['endTime']?.toString() ?? '';
    final hours = UiDate.hoursBetween(start, end);
    // Chi tiết tiền sân theo mức giá (giờ thường / giờ vàng), tính lại từ giá của cơ sở
    final venue = appState.venues.cast<Map<String, dynamic>?>().firstWhere(
          (v) => '${v?['id']}' == '${b['venueId']}',
          orElse: () => appState.selectedVenue,
        );
    final playDay = DateTime.tryParse(b['playDate']?.toString() ?? '');
    final breakdown = (venue != null && playDay != null)
        ? BookingRules.priceBreakdown(venue, playDay, BookingRules.hoursOfRange(start, end))
        : const <(String, int, num)>[];
    final walletEnough = appState.walletBalance >= total;
    if (!walletEnough && _method == _PayMethod.wallet) _method = _PayMethod.payos;
    final expired = _remaining == 0;

    return Column(
      children: [
        Expanded(
          child: ResponsiveCenter(
            maxWidth: Responsive.defaultFormMaxWidth,
            child: ListView(
              padding: Responsive.screenPadding(context),
              children: [
                const BookingSteps(current: 1),
                const SizedBox(height: 16),
                _holdBanner(theme),
                const SizedBox(height: 16),

                // Tóm tắt đơn
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              b['venueName']?.toString() ?? '',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '#${b['bookingCode']}',
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      InfoRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'Ngày',
                          value: UiDate.full(b['playDate']?.toString() ?? '')),
                      InfoRow(icon: Icons.schedule, label: 'Giờ', value: '$start - $end'),
                      InfoRow(
                          icon: Icons.grid_view_rounded,
                          label: 'Sân',
                          value: b['courtName']?.toString() ?? '-'),
                      Divider(height: 20, color: cs.outlineVariant),
                      if (breakdown.isNotEmpty)
                        ...[
                          for (final (label, count, unit) in breakdown)
                            InfoRow(
                              icon: Icons.receipt_long_outlined,
                              label: label,
                              value: '${UiFmt.vnd(unit)} × $count giờ',
                            ),
                        ]
                      else if (hours > 0)
                        InfoRow(
                          icon: Icons.receipt_long_outlined,
                          label: 'Tiền sân',
                          value: '${UiFmt.vnd(total / hours)} × $hours giờ',
                        ),
                      InfoRow(
                        icon: Icons.payments_outlined,
                        label: 'Tổng cộng',
                        value: UiFmt.vnd(total),
                        emphasize: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                Text('Phương thức thanh toán',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _methodCard(
                  theme,
                  value: _PayMethod.payos,
                  icon: Icons.qr_code_2,
                  title: 'Chuyển khoản VietQR',
                  subtitle: 'Quét mã bằng app ngân hàng, xác nhận tự động qua PayOS',
                  badge: 'Khuyên dùng',
                ),
                const SizedBox(height: 8),
                _methodCard(
                  theme,
                  value: _PayMethod.wallet,
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Ví Cầu Lông',
                  subtitle: walletEnough
                      ? 'Số dư: ${UiFmt.vnd(appState.walletBalance)}'
                      : 'Không đủ số dư (${UiFmt.vnd(appState.walletBalance)})',
                  enabled: walletEnough,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Giao dịch được mã hóa và xác nhận tự động.',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        BottomActionBar(
          summary: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tổng thanh toán',
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              Text(
                UiFmt.vnd(total),
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800, color: cs.primary),
              ),
            ],
          ),
          action: FilledButton(
            onPressed: (expired || _processing) ? null : () => _pay(context),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _processing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.onPrimary),
                  )
                : Text(_method == _PayMethod.payos ? 'Tạo mã QR' : 'Thanh toán'),
          ),
        ),
      ],
    );
  }
}
