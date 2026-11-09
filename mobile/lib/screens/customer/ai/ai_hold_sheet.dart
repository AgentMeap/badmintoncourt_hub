import 'dart:async';

import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/booking_rules.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

enum _PayChoice { wallet, vietQr }

/// Bấm "Giữ chỗ" trên thẻ khung giờ của Trợ lý AI:
/// giữ chỗ trên máy chủ (5 phút) -> Bottom Sheet xác nhận + chọn Ví / VietQR ngay trong S17.
/// Đóng sheet mà không thanh toán thì trả lại chỗ cho người khác.
/// Trả về true nếu đã chuyển sang màn khác (vé S13 hoặc QR S11).
Future<bool> holdSlotFromAi(BuildContext context, AppState app, Json slot) async {
  final Json booking;
  try {
    booking = await Repos.booking.hold(
      venueId: slot['venueId'],
      courtId: slot['courtId'],
      customerId: app.userId,
      playDate: '${slot['playDate']}',
      startTime: '${slot['startTime']}',
      endTime: '${slot['endTime']}',
      totalPrice: asNum(slot['totalPrice']) ?? 0,
    );
  } catch (e) {
    if (context.mounted) showApiError(context, e);
    return false;
  }

  booking['holdExpiresAt'] = BookingRules.holdExpiryMs(booking['holdExpiresAt']) ??
      DateTime.now().add(const Duration(minutes: BookingRules.holdMinutes)).millisecondsSinceEpoch;
  app.upsertBooking(booking);
  app.selectedBooking = booking;
  for (final v in app.venues) {
    if ('${v['id']}' == '${booking['venueId']}') app.selectedVenue = v;
  }
  if (!context.mounted) return false;

  final choice = await showModalBottomSheet<_PayChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _HoldSheet(booking: booking, walletBalance: app.walletBalance),
  );

  if (choice == null) {
    // Không thanh toán: trả chỗ ngay
    booking['status'] = 'CANCELLED';
    app.upsertBooking(booking);
    Repos.booking.release(booking['id'], customerId: app.userId).catchError((Object e) {
      debugPrint('[AI hold] $e');
      return <String, dynamic>{};
    });
    return false;
  }
  if (!context.mounted) return false;

  if (choice == _PayChoice.wallet) {
    final Json res;
    try {
      res = await Repos.booking.payWithWallet(bookingId: booking['id'], userId: app.userId);
    } catch (e) {
      if (context.mounted) showApiError(context, e);
      return false;
    }
    final paid = {...booking, ...asJson(res['booking'])};
    final balance = asNum(res['walletBalance']);
    if (balance != null) app.walletBalance = balance.toDouble();
    app.upsertBooking(paid);
    app.selectedBooking = paid;
    app.refreshWallet();
    if (!context.mounted) return false;
    app.pushNotification(
      title: 'Thanh toán bằng Ví Cầu Lông thành công',
      body: 'Vé ${paid['bookingCode']} (${paid['courtName']}, ${paid['startTime']}-${paid['endTime']}) đã xác nhận.',
      type: 'PAYMENT',
      targetScreen: 'S13',
      context: context,
    );
    app.justPaidBookingCode = paid['bookingCode']?.toString();
    app.goTo('S13');
    return true;
  }

  try {
    final res = await Repos.booking.createPayos(booking['id']);
    final payment = asJson(res['payment']);
    if (payment['payosOrderCode'] == null) throw ApiException.invalidResponse();
    app.activePayosPayment = payment;
  } catch (e) {
    if (context.mounted) showApiError(context, e);
    return false;
  }
  app.goTo('S11');
  return true;
}

class _HoldSheet extends StatefulWidget {
  const _HoldSheet({required this.booking, required this.walletBalance});
  final Json booking;
  final double walletBalance;

  @override
  State<_HoldSheet> createState() => _HoldSheetState();
}

class _HoldSheetState extends State<_HoldSheet> {
  Timer? _timer;
  int _remaining = BookingRules.holdMinutes * 60;

  @override
  void initState() {
    super.initState();
    final exp = BookingRules.holdExpiryMs(widget.booking['holdExpiresAt']);
    if (exp != null) {
      _remaining = ((exp - DateTime.now().millisecondsSinceEpoch) ~/ 1000)
          .clamp(0, BookingRules.holdMinutes * 60)
          .toInt();
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining = _remaining > 0 ? _remaining - 1 : 0);
      if (_remaining == 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final b = widget.booking;
    final total = UiFmt.toNum(b['totalPrice'], 0);
    final expired = _remaining == 0;
    final enoughWallet = widget.walletBalance >= total;
    final mm = (_remaining ~/ 60).toString().padLeft(2, '0');
    final ss = (_remaining % 60).toString().padLeft(2, '0');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(expired ? Icons.timer_off_outlined : Icons.timer_outlined,
                    color: expired ? cs.error : cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    expired ? 'Đã hết thời gian giữ chỗ' : 'Đã giữ chỗ • còn $mm:$ss để thanh toán',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: expired ? cs.error : cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SurfaceCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${b['venueName']}',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${b['courtName']} • ${UiDate.full('${b['playDate']}')} • ${b['startTime']} - ${b['endTime']}',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    UiFmt.vnd(total),
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: cs.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: (expired || !enoughWallet) ? null : () => Navigator.pop(context, _PayChoice.wallet),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text(enoughWallet
                  ? 'Trả bằng Ví (số dư ${UiFmt.vnd(widget.walletBalance)})'
                  : 'Ví không đủ (${UiFmt.vnd(widget.walletBalance)})'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: expired ? null : () => Navigator.pop(context, _PayChoice.vietQr),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Quét mã VietQR (PayOS)'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(expired ? 'Đóng' : 'Hủy giữ chỗ'),
            ),
          ],
        ),
      ),
    );
  }
}
