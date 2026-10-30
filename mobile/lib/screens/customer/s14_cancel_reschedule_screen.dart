import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/booking_rules.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S14: Cancel & Reschedule Screen (Luồng 4)
// Thực thi đúng nghiệp vụ qua BookingRules:
// - Hủy: hoàn 100% (>= 24h), 50% (6h - 24h), 0% (< 6h); vé chưa thanh toán không hoàn;
//   vé đã hủy / đã dùng / đã tới giờ thì không hủy được (chống hoàn tiền 2 lần).
// - Đổi lịch: tối đa 1 lần, trước giờ chơi >= 6h, giữ nguyên số giờ và sân,
//   chỉ hiện khung còn trống, tính lại giá và bù / hoàn chênh lệch qua Ví.
// - Mọi thao tác tiền đều có hộp thoại xác nhận.
class S14CancelRescheduleScreen extends StatefulWidget {
  final AppState appState;
  const S14CancelRescheduleScreen({super.key, required this.appState});

  @override
  State<S14CancelRescheduleScreen> createState() => _S14CancelRescheduleScreenState();
}

class _S14CancelRescheduleScreenState extends State<S14CancelRescheduleScreen> {
  final _reasonCtrl = TextEditingController();
  late DateTime _newDate;
  String? _newStart;
  bool _busy = false;

  AppState get _app => widget.appState;
  Map<String, dynamic> get _b => _app.selectedBooking ?? _app.bookings.first;

  Map<String, dynamic>? get _venue => _app.venues.cast<Map<String, dynamic>?>().firstWhere(
        (v) => '${v?['id']}' == '${_b['venueId']}',
        orElse: () => _app.selectedVenue,
      );

  @override
  void initState() {
    super.initState();
    _newDate = DateTime.tryParse(_b['playDate']?.toString() ?? '') ??
        BookingRules.dateOnly(DateTime.now());
    final today = BookingRules.dateOnly(DateTime.now());
    if (_newDate.isBefore(today)) _newDate = today;
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  int get _duration => BookingRules.hoursOfRange(
        _b['startTime']?.toString() ?? '00:00',
        _b['endTime']?.toString() ?? '00:00',
      ).length;

  /// Các giờ bắt đầu còn trống trên CÙNG sân, cùng số giờ, trong ngày [_newDate].
  List<String> _availableStarts() {
    final venue = _venue;
    if (venue == null || _duration == 0) return const [];
    final hours = BookingRules.operatingHours(venue);
    final occ = BookingRules.occupancy(
      _app.bookings,
      venueId: _b['venueId'],
      courtId: UiFmt.toNum(_b['courtId'], 1).toInt(),
      playDate: BookingRules.dateKey(_newDate),
      excludeBookingCode: _b['bookingCode']?.toString(),
    );
    final sameDay = BookingRules.dateKey(_newDate) == _b['playDate'];
    final result = <String>[];
    for (var i = 0; i + _duration <= hours.length; i++) {
      final range = hours.sublist(i, i + _duration);
      if (range.any((h) => occ.containsKey(h))) continue;
      if (BookingRules.isPast(_newDate, range.first)) continue;
      // Khung mới cũng phải cách giờ chơi >= ngưỡng đổi lịch
      final until = BookingRules.startOf(BookingRules.dateKey(_newDate), range.first)
          .difference(DateTime.now());
      if (until < const Duration(hours: BookingRules.rescheduleCutoffHours)) continue;
      if (sameDay && range.first == _b['startTime']) continue; // trùng giờ cũ
      result.add(range.first);
    }
    return result;
  }

  String _endFor(String start) =>
      BookingRules.hourLabel(BookingRules.hourOf(start) + _duration);

  num _priceFor(String start) {
    final venue = _venue;
    if (venue == null) return UiFmt.toNum(_b['totalPrice'], 0);
    return BookingRules.priceOfRange(
        venue, _newDate, BookingRules.hoursOfRange(start, _endFor(start)));
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Quay lại')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  // ---------------------------------------------------------------- Đổi lịch

  Future<void> _handleReschedule() async {
    final b = _b;
    final start = _newStart;
    if (start == null || _busy) return;
    final block = BookingRules.rescheduleBlockReason(b);
    if (block != null) {
      _toast(block);
      return;
    }
    if (!_availableStarts().contains(start)) {
      setState(() => _newStart = null);
      _toast('Khung giờ vừa chọn không còn trống, vui lòng chọn lại.');
      return;
    }

    final end = _endFor(start);
    final oldTotal = UiFmt.toNum(b['totalPrice'], 0);
    final newTotal = _priceFor(start);
    final diff = newTotal - oldTotal;
    if (diff > 0 && _app.walletBalance < diff) {
      _toast('Số dư Ví không đủ để bù chênh lệch ${UiFmt.vnd(diff)}.');
      return;
    }

    final diffText = diff > 0
        ? '\nBù thêm ${UiFmt.vnd(diff)} (trừ vào Ví).'
        : diff < 0
            ? '\nHoàn lại ${UiFmt.vnd(-diff)} vào Ví.'
            : '\nKhông phát sinh chênh lệch.';
    final ok = await _confirm(
      title: 'Xác nhận đổi lịch',
      message: 'Đổi sang ${UiDate.full(BookingRules.dateKey(_newDate))}, '
          '$start - $end (${b['courtName']}).$diffText\n\n'
          'Mỗi vé chỉ được đổi lịch ${BookingRules.maxReschedules} lần.',
      confirmLabel: 'Đổi lịch',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);

    final newDateKey = BookingRules.dateKey(_newDate);
    try {
      await ApiService.post('/bookings/${b['id']}/reschedule', {
        'playDate': newDateKey,
        'startTime': start,
        'endTime': end,
      });
    } catch (_) {}

    b['playDate'] = newDateKey;
    b['startTime'] = start;
    b['endTime'] = end;
    b['totalPrice'] = newTotal.toDouble();
    b['rescheduledCount'] = UiFmt.toNum(b['rescheduledCount'], 0).toInt() + 1;
    if (diff != 0) {
      _app.walletBalance -= diff.toDouble();
      _app.walletTransactions.insert(0, {
        'title': diff > 0
            ? 'Bù chênh lệch đổi lịch #${b['bookingCode']}'
            : 'Hoàn chênh lệch đổi lịch #${b['bookingCode']}',
        'amount': -diff.toDouble(),
        'type': diff > 0 ? 'BOOKING_PAYMENT' : 'REFUND',
        'createdAt': 'Vừa xong',
      });
    }

    if (!mounted) return;
    setState(() => _busy = false);
    _app.pushNotification(
      title: 'Đổi lịch thành công (#${b['bookingCode']})',
      body: 'Lịch mới: ${b['courtName']}, $start - $end, ${UiDate.full(newDateKey)}.',
      type: 'BOOKING',
      targetScreen: 'S13',
      context: context,
    );
    // Đổi lịch xong: quay về vé, bỏ màn S14 khỏi lịch sử
    _app.completeFlow('S13', flowStart: 'S14');
  }

  // ---------------------------------------------------------------- Hủy vé

  Future<void> _handleCancel() async {
    final b = _b;
    if (_busy) return;
    final block = BookingRules.cancelBlockReason(b);
    if (block != null) {
      _toast(block);
      return;
    }

    final paid = BookingRules.isPaid(b);
    final percent = BookingRules.refundPercent(b);
    final refund = BookingRules.refundAmount(b);
    final ok = await _confirm(
      title: paid ? 'Hủy vé #${b['bookingCode']}?' : 'Hủy giữ chỗ?',
      message: !paid
          ? 'Vé chưa thanh toán nên không phát sinh hoàn tiền.'
          : refund > 0
              ? 'Bạn sẽ được hoàn ${UiFmt.vnd(refund)} ($percent%) vào Ví Cầu Lông. Thao tác này không thể hoàn tác.'
              : 'Vé đã sát giờ chơi (dưới ${BookingRules.halfRefundHours} tiếng) nên KHÔNG được hoàn tiền. Thao tác này không thể hoàn tác.',
      confirmLabel: 'Hủy vé',
      destructive: true,
    );
    if (!ok || !mounted) return;
    // Kiểm tra lại sau hộp thoại (tránh bấm 2 lần / trạng thái vừa đổi)
    if (BookingRules.cancelBlockReason(b) != null) return;
    setState(() => _busy = true);

    try {
      await ApiService.post('/bookings/${b['id']}/cancel', {
        'reason': _reasonCtrl.text.trim(),
        'refundPercent': percent,
      });
    } catch (_) {}

    b['status'] = 'CANCELLED';
    if (refund > 0) {
      _app.walletBalance += refund.toDouble();
      _app.walletTransactions.insert(0, {
        'title': 'Hoàn tiền $percent% hủy vé #${b['bookingCode']}',
        'amount': refund.toDouble(),
        'type': 'REFUND',
        'createdAt': 'Vừa xong',
      });
    }

    if (!mounted) return;
    setState(() => _busy = false);
    _app.pushNotification(
      title: refund > 0
          ? 'Đã hoàn ${UiFmt.vnd(refund)} vào Ví Cầu Lông'
          : 'Đã hủy vé #${b['bookingCode']}',
      body: refund > 0
          ? 'Hủy vé #${b['bookingCode']}: hoàn $percent% giá trị vé.'
          : 'Vé #${b['bookingCode']} đã được hủy, không phát sinh hoàn tiền.',
      type: refund > 0 ? 'PAYMENT' : 'BOOKING',
      targetScreen: refund > 0 ? 'S18' : 'S12',
      context: context,
    );
    _app.completeFlow(refund > 0 ? 'S18' : 'S12', flowStart: 'S14');
  }

  // ---------------------------------------------------------------- Giao diện

  Widget _sectionCard(ThemeData theme, {required Widget child, Color? borderColor}) {
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor ?? cs.outlineVariant),
      ),
      child: child,
    );
  }

  Widget _blockedNote(ThemeData theme, String text) {
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _policyRow(ThemeData theme, String when, String result, bool active) {
    final cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active ? cs.primaryContainer : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? cs.primary : Colors.transparent),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 18,
            color: active ? cs.primary : cs.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              when,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            result,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateChips(ThemeData theme) {
    final today = BookingRules.dateOnly(DateTime.now());
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Builder(builder: (_) {
                final d = today.add(Duration(days: i));
                final label = i == 0
                    ? 'Hôm nay'
                    : i == 1
                        ? 'Ngày mai'
                        : '${UiDate.weekday(BookingRules.dateKey(d))} ${d.day}/${d.month}';
                return ChoiceChip(
                  label: Text(label),
                  selected: d == _newDate,
                  showCheckmark: false,
                  onSelected: (_) => setState(() {
                    _newDate = d;
                    _newStart = null;
                  }),
                );
              }),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final b = _b;
    final total = UiFmt.toNum(b['totalPrice'], 0);
    final cancelBlock = BookingRules.cancelBlockReason(b);
    final rescheduleBlock = BookingRules.rescheduleBlockReason(b);
    final paid = BookingRules.isPaid(b);
    final percent = BookingRules.refundPercent(b);
    final refund = BookingRules.refundAmount(b);
    final left = BookingRules.timeUntilStart(b);
    final starts = rescheduleBlock == null ? _availableStarts() : const <String>[];
    if (_newStart != null && !starts.contains(_newStart)) _newStart = null;
    final newPrice = _newStart == null ? null : _priceFor(_newStart!);
    final diff = newPrice == null ? 0 : newPrice - total;

    String leftText() {
      if (left.isNegative) return 'Đã qua giờ chơi';
      final h = left.inHours;
      final m = left.inMinutes % 60;
      if (h >= 24) return 'Còn ${left.inDays} ngày ${h % 24} giờ';
      return 'Còn $h giờ $m phút';
    }

    return ResponsiveCenter(
      maxWidth: Responsive.defaultFormMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context),
        children: [
          // ----- Vé hiện tại
          _sectionCard(
            theme,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        b['venueName']?.toString() ?? '',
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge(status: b['status']?.toString()),
                  ],
                ),
                const SizedBox(height: 6),
                InfoRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Ngày',
                    value: UiDate.full(b['playDate']?.toString() ?? '')),
                InfoRow(
                    icon: Icons.schedule,
                    label: 'Giờ',
                    value: '${b['startTime']} - ${b['endTime']} • ${b['courtName']}'),
                InfoRow(icon: Icons.hourglass_bottom, label: 'Đến giờ chơi', value: leftText()),
                InfoRow(
                    icon: Icons.payments_outlined,
                    label: 'Đã thanh toán',
                    value: paid ? UiFmt.vnd(total) : 'Chưa thanh toán',
                    emphasize: paid),
              ],
            ),
          ),

          // ----- Đổi lịch
          const SizedBox(height: 24),
          Text('Đổi lịch', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _sectionCard(
            theme,
            child: rescheduleBlock != null
                ? _blockedNote(theme, rescheduleBlock)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Giữ nguyên ${b['courtName']} và $_duration giờ chơi. Chọn ngày và giờ bắt đầu mới:',
                        style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      _dateChips(theme),
                      const SizedBox(height: 12),
                      if (starts.isEmpty)
                        _blockedNote(theme, 'Ngày này không còn khung trống phù hợp.')
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final s in starts)
                              ChoiceChip(
                                label: Text('$s - ${_endFor(s)}'),
                                selected: _newStart == s,
                                showCheckmark: false,
                                onSelected: (_) => setState(() => _newStart = s),
                              ),
                          ],
                        ),
                      if (newPrice != null) ...[
                        const SizedBox(height: 12),
                        InfoRow(
                          icon: Icons.receipt_long_outlined,
                          label: 'Giá khung mới',
                          value: UiFmt.vnd(newPrice),
                        ),
                        InfoRow(
                          icon: diff > 0 ? Icons.add_circle_outline : Icons.remove_circle_outline,
                          label: diff > 0 ? 'Bù thêm (từ Ví)' : 'Hoàn lại (vào Ví)',
                          value: UiFmt.vnd(diff.abs()),
                          emphasize: diff != 0,
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: (_newStart == null || _busy) ? null : _handleReschedule,
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                          icon: const Icon(Icons.edit_calendar_outlined),
                          label: const Text('Đổi sang khung giờ này'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Mỗi vé được đổi ${BookingRules.maxReschedules} lần, trước giờ chơi ít nhất ${BookingRules.rescheduleCutoffHours} tiếng.',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
          ),

          // ----- Hủy vé
          const SizedBox(height: 24),
          Text('Hủy vé', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _sectionCard(
            theme,
            borderColor: cancelBlock == null ? cs.error.withValues(alpha: 0.4) : null,
            child: cancelBlock != null
                ? _blockedNote(theme, cancelBlock)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (paid) ...[
                        Text('Chính sách hoàn tiền',
                            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        _policyRow(theme, 'Trước giờ chơi ≥ ${BookingRules.fullRefundHours} tiếng',
                            'Hoàn 100%', percent == 100),
                        _policyRow(
                            theme,
                            'Trước ${BookingRules.halfRefundHours} - ${BookingRules.fullRefundHours} tiếng',
                            'Hoàn 50%',
                            percent == 50),
                        _policyRow(theme, 'Dưới ${BookingRules.halfRefundHours} tiếng',
                            'Không hoàn', percent == 0),
                        const SizedBox(height: 8),
                        InfoRow(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'Bạn sẽ nhận',
                          value: '${UiFmt.vnd(refund)} ($percent%)',
                          emphasize: true,
                        ),
                      ] else
                        _blockedNote(theme, 'Vé chưa thanh toán: hủy để nhả sân, không phát sinh hoàn tiền.'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _reasonCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Lý do hủy (không bắt buộc)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _handleCancel,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            foregroundColor: cs.error,
                            side: BorderSide(color: cs.error),
                          ),
                          icon: const Icon(Icons.cancel_outlined),
                          label: Text(paid ? 'Hủy vé' : 'Hủy giữ chỗ'),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
