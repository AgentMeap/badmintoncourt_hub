import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/booking_rules.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S09: Court Time-Slot Selection Grid Screen (Luồng 1)
// - Lưới lấy từ dữ liệu thật: số sân = totalCourts, cột giờ = giờ mở cửa của cơ sở
// - Ô đã đặt / bảo trì suy ra từ appState.bookings (chống đặt trùng)
// - Giá tính theo từng giờ (giờ thường / giờ vàng / cuối tuần) qua BookingRules
// - Chọn ngày trong 7 ngày tới, khung giờ đã qua bị khóa
// - Mỗi trạng thái có màu + icon, ô cao 48dp, tóm tắt & nút cố định ở đáy
class S09TimeSlotGridScreen extends StatefulWidget {
  final AppState appState;
  const S09TimeSlotGridScreen({super.key, required this.appState});

  @override
  State<S09TimeSlotGridScreen> createState() => _S09TimeSlotGridScreenState();
}

enum _SlotState { available, selected, booked, maintenance, past }

class _S09TimeSlotGridScreenState extends State<S09TimeSlotGridScreen> {
  static const double _cellWidth = 56;
  static const int _daysAhead = 7;

  late DateTime _date;
  int _selectedCourtIndex = 0;
  final Set<String> _selectedSlots = {};
  bool _submitting = false;
  final ScrollController _hScroll = ScrollController();

  AppState get _app => widget.appState;
  Map<String, dynamic> get _venue => _app.selectedVenue ?? _app.venues.first;
  List<String> get _hours => BookingRules.operatingHours(_venue);
  String get _playDate => BookingRules.dateKey(_date);

  @override
  void initState() {
    super.initState();
    _date = BookingRules.dateOnly(DateTime.now());
    // Cuộn lưới tới khung giờ còn đặt được đầu tiên
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFirstOpenHour());
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  void _scrollToFirstOpenHour() {
    if (!_hScroll.hasClients) return;
    final idx = _hours.indexWhere((h) => !BookingRules.isPast(_date, h));
    final target = (idx < 0 ? 0 : idx) * (_cellWidth + 6.0);
    _hScroll.jumpTo(target.clamp(0.0, _hScroll.position.maxScrollExtent));
  }

  // ---------------------------------------------------------------- Dữ liệu

  Map<String, String> _occupancyOf(int courtIdx) => BookingRules.occupancy(
        _app.bookings,
        venueId: _venue['id'],
        courtId: courtIdx + 1,
        playDate: _playDate,
      );

  _SlotState _stateOf(int courtIdx, String h, Map<String, String> occ) {
    final o = occ[h];
    if (o == 'MAINTENANCE') return _SlotState.maintenance;
    if (o == 'BOOKED') return _SlotState.booked;
    if (BookingRules.isPast(_date, h)) return _SlotState.past;
    if (_selectedCourtIndex == courtIdx && _selectedSlots.contains(h)) {
      return _SlotState.selected;
    }
    return _SlotState.available;
  }

  bool _isBlocked(int courtIdx, String h) {
    final st = _stateOf(courtIdx, h, _occupancyOf(courtIdx));
    return st == _SlotState.booked || st == _SlotState.maintenance || st == _SlotState.past;
  }

  List<String> get _sortedSelection =>
      _selectedSlots.toList()..sort((a, b) => _hours.indexOf(a).compareTo(_hours.indexOf(b)));

  String _endOf(List<String> sorted) =>
      BookingRules.hourLabel(BookingRules.hourOf(sorted.last) + 1);

  // ---------------------------------------------------------------- Hành động

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  void _changeDate(DateTime d) {
    setState(() {
      _date = d;
      _selectedSlots.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFirstOpenHour());
  }

  /// Chọn khung giờ, luôn đảm bảo các giờ đã chọn LIỀN NHAU trên cùng một sân.
  void _toggle(int courtIdx, String h) {
    final idx = _hours.indexOf(h);
    String? message;
    setState(() {
      if (_selectedCourtIndex != courtIdx || _selectedSlots.isEmpty) {
        _selectedCourtIndex = courtIdx;
        _selectedSlots
          ..clear()
          ..add(h);
        return;
      }

      final selectedIdx = _selectedSlots.map(_hours.indexOf).toList()..sort();
      final first = selectedIdx.first;
      final last = selectedIdx.last;

      if (_selectedSlots.contains(h)) {
        if (idx == first) {
          _selectedSlots.remove(h);
        } else {
          _selectedSlots.removeWhere((s) => _hours.indexOf(s) >= idx);
        }
        return;
      }

      final from = idx < first ? idx : last + 1;
      final to = idx < first ? first - 1 : idx;
      final between = [for (var i = from; i <= to; i++) _hours[i]];
      if (between.any((x) => _isBlocked(courtIdx, x))) {
        _selectedSlots
          ..clear()
          ..add(h);
        message = 'Có khung giờ không trống ở giữa, đã chọn lại từ $h';
      } else {
        _selectedSlots.addAll(between);
      }
    });
    if (message != null) _showMessage(message!);
  }

  Future<void> _holdAndProceed() async {
    if (_selectedSlots.isEmpty || _submitting) return;
    final sorted = _sortedSelection;

    // Kiểm tra lại ngay trước khi giữ chỗ (có thể vừa có người đặt / giờ vừa trôi qua)
    if (sorted.any((h) => _isBlocked(_selectedCourtIndex, h))) {
      setState(() => _selectedSlots.clear());
      _showMessage('Khung giờ vừa chọn không còn trống, vui lòng chọn lại.');
      return;
    }

    setState(() => _submitting = true);
    final venue = _venue;
    final start = sorted.first;
    final end = _endOf(sorted);
    final total = BookingRules.priceOfRange(venue, _date, sorted).toDouble();
    assert(BookingRules.hoursOfRange(start, end).length == sorted.length);
    final courtId = _selectedCourtIndex + 1;
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;

    Map<String, dynamic> heldBooking = {
      'id': stamp,
      'bookingCode': 'BK-$stamp',
      'venueId': venue['id'],
      'venueName': venue['name'],
      'courtId': courtId,
      'courtName': 'Sân $courtId',
      'customerId': _app.userId,
      'customerName': _app.fullName,
      'customerPhone': _app.phone,
      'bookingType': 'ONLINE',
      'playDate': _playDate,
      'startTime': start,
      'endTime': end,
      'totalPrice': total,
      'status': 'HELD',
      'rescheduledCount': 0,
      'qrCheckInToken': 'QR-BK-$stamp',
      'paymentMethod': 'PENDING',
    };

    try {
      final res = await ApiService.post('/bookings/hold', {
        'venueId': venue['id'],
        'courtId': courtId,
        'customerId': _app.userId,
        'playDate': _playDate,
        'startTime': start,
        'endTime': end,
        'totalPrice': total,
      });
      if (res is Map) {
        heldBooking = Map<String, dynamic>.from(res);
      }
    } catch (_) {}

    // Mốc hết hạn giữ chỗ để S10 đếm ngược đúng, không reset khi quay lại
    heldBooking['holdExpiresAt'] ??= DateTime.now()
        .add(const Duration(minutes: BookingRules.holdMinutes))
        .millisecondsSinceEpoch;

    if (!mounted) return;
    setState(() => _submitting = false);
    _app.selectedBooking = heldBooking;
    _app.goTo('S10');
  }

  // ---------------------------------------------------------------- Giao diện

  (Color, Color, IconData, String) _styleOf(ColorScheme cs, _SlotState s) {
    switch (s) {
      case _SlotState.available:
        return (cs.surface, cs.onSurfaceVariant.withValues(alpha: 0.6), Icons.add, 'Trống');
      case _SlotState.selected:
        return (cs.primary, cs.onPrimary, Icons.check_rounded, 'Đang chọn');
      case _SlotState.booked:
        return (cs.errorContainer, cs.onErrorContainer, Icons.lock_outline, 'Đã đặt');
      case _SlotState.maintenance:
        return (WarningTone.container(cs), WarningTone.onContainer(cs), Icons.build_outlined, 'Bảo trì');
      case _SlotState.past:
        return (
          cs.surfaceContainerHighest,
          cs.onSurfaceVariant.withValues(alpha: 0.5),
          Icons.remove,
          'Đã qua'
        );
    }
  }

  Widget _legendItem(ColorScheme cs, TextTheme tt, _SlotState s) {
    final (bg, fg, icon, label) = _styleOf(cs, s);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: s == _SlotState.available ? cs.outlineVariant : Colors.transparent,
            ),
          ),
          child: Icon(icon, size: 14, color: fg),
        ),
        const SizedBox(width: 6),
        Text(label, style: tt.bodySmall),
      ],
    );
  }

  Widget _slotCell(ColorScheme cs, int courtIdx, String h, Map<String, String> occ) {
    final s = _stateOf(courtIdx, h, occ);
    final (bg, fg, icon, label) = _styleOf(cs, s);
    final enabled = s == _SlotState.available || s == _SlotState.selected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Semantics(
        button: enabled,
        selected: s == _SlotState.selected,
        label: 'Sân ${courtIdx + 1}, $h, $label',
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: s == _SlotState.available ? cs.outlineVariant : Colors.transparent,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? () => _toggle(courtIdx, h) : null,
            child: SizedBox(
              width: _cellWidth,
              height: 48,
              child: Center(child: Icon(icon, size: 20, color: fg)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateSelector(ThemeData theme) {
    final cs = theme.colorScheme;
    final today = BookingRules.dateOnly(DateTime.now());
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _daysAhead,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final d = today.add(Duration(days: i));
          final selected = d == _date;
          final top = i == 0
              ? 'Hôm nay'
              : i == 1
                  ? 'Ngày mai'
                  : UiDate.weekday(BookingRules.dateKey(d));
          return Semantics(
            selected: selected,
            button: true,
            label: '$top, ngày ${d.day} tháng ${d.month}',
            child: Material(
              color: selected ? cs.primary : cs.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: selected ? cs.primary : cs.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _changeDate(d),
                child: SizedBox(
                  width: 72,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        top,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: selected ? cs.onPrimary : cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final venue = _venue;
    final hours = _hours;
    final courts = BookingRules.courtCount(venue);
    final occByCourt = [for (var c = 0; c < courts; c++) _occupancyOf(c)];
    final sorted = _sortedSelection;
    final total = BookingRules.priceOfRange(venue, _date, sorted);
    final hasOpenSlot = hours.any((h) => !BookingRules.isPast(_date, h));

    return Column(
      children: [
        Expanded(
          child: ResponsiveCenter(
            maxWidth: Responsive.defaultContentMaxWidth,
            child: ListView(
              padding: Responsive.screenPadding(context),
              children: [
                Text(
                  venue['name'].toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _meta(cs, tt, Icons.schedule,
                        '${venue['openTime'] ?? '05:00'} - ${venue['closeTime'] ?? '23:00'}'),
                    _meta(cs, tt, Icons.payments_outlined,
                        '${UiFmt.k(UiFmt.toNum(venue['basePricePerHour'], 0))} - ${UiFmt.k(UiFmt.toNum(venue['peakPricePerHour'], 0))}/giờ'),
                  ],
                ),
                const SizedBox(height: 16),
                _dateSelector(theme),
                const SizedBox(height: 16),

                // Chú thích trạng thái (màu + icon)
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: _SlotState.values.map((s) => _legendItem(cs, tt, s)).toList(),
                ),
                const SizedBox(height: 12),

                if (!hasOpenSlot)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.nights_stay_outlined, color: cs.onSecondaryContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Hôm nay đã hết khung giờ. Hãy chọn ngày khác.',
                            style: tt.bodySmall?.copyWith(color: cs.onSecondaryContainer),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Lưới: cột tên sân cố định + các cột giờ cuộn ngang
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 52,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 36),
                            for (var c = 0; c < courts; c++)
                              SizedBox(
                                height: 56,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Sân ${c + 1}',
                                    maxLines: 1,
                                    style: tt.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: (_selectedCourtIndex == c && sorted.isNotEmpty)
                                          ? cs.primary
                                          : cs.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _hScroll,
                          scrollDirection: Axis.horizontal,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Hàng tiêu đề: giờ + giá
                              SizedBox(
                                height: 36,
                                child: Row(
                                  children: [
                                    for (final h in hours)
                                      SizedBox(
                                        width: _cellWidth + 6,
                                        child: Column(
                                          children: [
                                            Text(
                                              h,
                                              style: tt.labelSmall?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                            Text(
                                              UiFmt.k(BookingRules.priceOf(venue, _date, h)),
                                              style: tt.labelSmall?.copyWith(
                                                color: BookingRules.isPeak(_date, h)
                                                    ? cs.primary
                                                    : cs.onSurfaceVariant,
                                                fontWeight: BookingRules.isPeak(_date, h)
                                                    ? FontWeight.w700
                                                    : FontWeight.w400,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              for (var c = 0; c < courts; c++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      for (final h in hours) _slotCell(cs, c, h, occByCourt[c]),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.swipe_outlined, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Vuốt ngang để xem thêm giờ. Chọn các giờ liền nhau trên một sân; sân được giữ ${BookingRules.holdMinutes} phút để thanh toán.',
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
          summary: sorted.isEmpty
              ? Text(
                  'Chọn ít nhất 1 khung giờ',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Sân ${_selectedCourtIndex + 1} • ${sorted.first} - ${_endOf(sorted)} (${sorted.length} giờ)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        UiFmt.vnd(total),
                        style: tt.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ],
                ),
          action: FilledButton(
            onPressed: (sorted.isEmpty || _submitting) ? null : _holdAndProceed,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _submitting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.onPrimary),
                  )
                : const Text('Giữ chỗ & thanh toán'),
          ),
        ),
      ],
    );
  }

  Widget _meta(ColorScheme cs, TextTheme tt, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(text, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }
}
