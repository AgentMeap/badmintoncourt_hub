import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/booking_rules.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S21: Owner Master Schedule & Walk-in Management (Luồng 2)
// Giao diện theo design system + sửa logic:
// - Chọn cơ sở / ngày / sân / giờ bắt đầu / số giờ (trước đây luôn ghi vào "Sân 3"
//   của cơ sở cũ, ngày cố định)
// - KIỂM TRA TRÙNG LỊCH qua BookingRules trước khi thêm khách vãng lai / bảo trì
// - Giá vãng lai tính theo bảng giá cơ sở (trước đây cố định 240.000đ)
// - Lịch biểu lọc theo cơ sở + ngày, sắp theo giờ; chỉ check-in vé hợp lệ
class S21OwnerMasterScheduleScreen extends StatefulWidget {
  final AppState appState;
  const S21OwnerMasterScheduleScreen({super.key, required this.appState});

  @override
  State<S21OwnerMasterScheduleScreen> createState() => _S21OwnerMasterScheduleScreenState();
}

class _S21OwnerMasterScheduleScreenState extends State<S21OwnerMasterScheduleScreen> {
  final _walkInNameCtrl = TextEditingController(text: 'Chị Lan - 0912888999');
  late Map<String, dynamic> _venue;
  late DateTime _date;
  int _court = 1;
  String? _start;
  int _duration = 2;
  bool _busy = false;

  AppState get _app => widget.appState;
  List<Map<String, dynamic>> get _myVenues => OwnerFinance.ownerVenues(_app.venues, _app.userId);

  @override
  void initState() {
    super.initState();
    _venue = _myVenues.isNotEmpty ? _myVenues.first : <String, dynamic>{};
    _date = BookingRules.dateOnly(DateTime.now());
  }

  @override
  void dispose() {
    _walkInNameCtrl.dispose();
    super.dispose();
  }

  String get _dateKey => BookingRules.dateKey(_date);

  /// Giờ bắt đầu hợp lệ cho sân/ngày/số giờ đang chọn (không trùng, chưa qua, trong giờ mở cửa).
  List<String> _availableStarts() {
    final hours = BookingRules.operatingHours(_venue);
    final occ = BookingRules.occupancy(_app.bookings,
        venueId: _venue['id'], courtId: _court, playDate: _dateKey);
    return [
      for (var i = 0; i + _duration <= hours.length; i++)
        if (!hours.sublist(i, i + _duration).any(occ.containsKey) &&
            !BookingRules.isPast(_date, hours[i]))
          hours[i]
    ];
  }

  Future<void> _addEntry(String type) async {
    if (_busy) return;
    final start = _start;
    final isMaint = type == 'MAINTENANCE';
    if (start == null) {
      _toast('Vui lòng chọn giờ bắt đầu.');
      return;
    }
    if (!isMaint && _walkInNameCtrl.text.trim().isEmpty) {
      _toast('Vui lòng nhập tên / SĐT khách.');
      return;
    }
    // Kiểm tra trùng lịch lần cuối
    if (!_availableStarts().contains(start)) {
      setState(() => _start = null);
      _toast('Khung giờ này vừa có người đặt, vui lòng chọn lại.');
      return;
    }

    final end = BookingRules.hourLabel(BookingRules.hourOf(start) + _duration);
    final hours = BookingRules.hoursOfRange(start, end);
    final price = isMaint ? 0 : BookingRules.priceOfRange(_venue, _date, hours);
    final ok = await confirmAction(
      context,
      title: isMaint ? 'Khóa sân bảo trì?' : 'Ghi nhận khách vãng lai?',
      message: 'Sân $_court • $start - $end • ${UiDate.full(_dateKey)}'
          '${isMaint ? '' : '\nThu tại quầy: ${UiFmt.vnd(price)}'}',
      confirmLabel: isMaint ? 'Khóa sân' : 'Ghi nhận',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);

    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    final entry = <String, dynamic>{
      'id': stamp,
      'bookingCode': '${isMaint ? "MT" : "WI"}-$stamp',
      'venueId': _venue['id'],
      'venueName': _venue['name'],
      'courtId': _court,
      'courtName': 'Sân $_court',
      'customerName': isMaint
          ? (_walkInNameCtrl.text.trim().isEmpty ? 'Bảo trì sân' : 'Bảo trì: ${_walkInNameCtrl.text.trim()}')
          : 'Khách vãng lai: ${_walkInNameCtrl.text.trim()}',
      'bookingType': type,
      'playDate': _dateKey,
      'startTime': start,
      'endTime': end,
      'totalPrice': price.toDouble(),
      'status': 'CONFIRMED',
      'qrCheckInToken': 'QR-${isMaint ? "MT" : "WI"}-$stamp',
      'paymentMethod': isMaint ? 'NONE' : 'CASH',
    };

    try {
      await ApiService.post('/owner/bookings/walk-in', entry);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _app.bookings.insert(0, entry);
      _start = null;
      _busy = false;
    });
    _toast(isMaint ? 'Đã khóa bảo trì Sân $_court ($start - $end)' : 'Đã ghi nhận khách vãng lai Sân $_court ($start - $end)');
  }

  Future<void> _checkIn(Map<String, dynamic> b) async {
    final ok = await confirmAction(
      context,
      title: 'Xác nhận khách nhận sân?',
      message: '${b['courtName']} • ${b['startTime']} - ${b['endTime']}\n${b['customerName'] ?? ''}',
      confirmLabel: 'Check-in',
    );
    if (!ok || !mounted) return;
    try {
      await ApiService.post('/owner/bookings/check-in', {'code': b['qrCheckInToken'] ?? b['bookingCode']});
    } catch (_) {}
    if (!mounted) return;
    setState(() => b['status'] = 'CHECKED_IN');
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _entryTile(ThemeData theme, Map<String, dynamic> b) {
    final cs = theme.colorScheme;
    final type = b['bookingType'];
    final isMaint = type == 'MAINTENANCE';
    final status = b['status']?.toString();
    final cancelled = status == 'CANCELLED' || status == 'REFUNDED';
    final (icon, typeLabel, accent) = switch (type) {
      'MAINTENANCE' => (Icons.build_outlined, 'Bảo trì', WarningTone.onContainer(cs)),
      'WALK_IN' => (Icons.directions_walk, 'Vãng lai', cs.tertiary),
      _ => (Icons.phone_iphone, 'Online', cs.primary),
    };
    final canCheckIn = !isMaint && !cancelled && status != 'CHECKED_IN' && BookingRules.isPaid(b);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Column(
              children: [
                Text('${b['startTime']}',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text('${b['endTime']}',
                    style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Container(width: 3, height: 40, color: accent, margin: const EdgeInsets.only(right: 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${b['courtName']} • ${b['customerName'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: cancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(icon, size: 14, color: accent),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '$typeLabel • #${b['bookingCode']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (canCheckIn)
            FilledButton.tonal(
              onPressed: () => _checkIn(b),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              child: const Text('Check-in'),
            )
          else if (!isMaint)
            StatusBadge(status: status),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final today = BookingRules.dateOnly(DateTime.now());
    final courts = BookingRules.courtCount(_venue);
    if (_court > courts) _court = 1;
    final starts = _availableStarts();
    if (_start != null && !starts.contains(_start)) _start = null;
    final entries = _app.bookings
        .where((b) => '${b['venueId']}' == '${_venue['id']}' && b['playDate'] == _dateKey)
        .toList()
      ..sort((a, b) {
        final t = '${a['startTime']}'.compareTo('${b['startTime']}');
        return t != 0 ? t : '${a['courtName']}'.compareTo('${b['courtName']}');
      });

    return ResponsiveCenter(
      maxWidth: Responsive.defaultContentMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context),
        children: [
          Text('Lịch biểu',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (_myVenues.length > 1) ...[
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: '${_venue['id']}',
              items: [
                for (final v in _myVenues)
                  DropdownMenuItem(
                    value: '${v['id']}',
                    child: Text(v['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (id) => setState(() {
                _venue = _myVenues.firstWhere((v) => '${v['id']}' == id, orElse: () => _venue);
                _start = null;
              }),
              decoration: const InputDecoration(
                labelText: 'Cơ sở',
                prefixIcon: Icon(Icons.storefront_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Builder(builder: (_) {
                    final d = today.add(Duration(days: i));
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(i == 0
                            ? 'Hôm nay'
                            : '${UiDate.weekday(BookingRules.dateKey(d))} ${d.day}/${d.month}'),
                        selected: d == _date,
                        showCheckmark: false,
                        onSelected: (_) => setState(() {
                          _date = d;
                          _start = null;
                        }),
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 16),

          SectionHeader('Lịch ${UiDate.full(_dateKey)}',
              trailing: Text('${entries.length} ca',
                  style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant))),
          if (entries.isEmpty)
            const EmptyState(icon: Icons.event_busy_outlined, title: 'Chưa có ca nào trong ngày')
          else
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: cs.outlineVariant),
                    _entryTile(theme, entries[i]),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 24),

          // Thêm nhanh
          const SectionHeader('Thêm vãng lai / khóa bảo trì'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('court-${_venue['id']}'),
                        isExpanded: true,
                        initialValue: _court,
                        items: [
                          for (var c = 1; c <= courts; c++) DropdownMenuItem(value: c, child: Text('Sân $c')),
                        ],
                        onChanged: (v) => setState(() {
                          _court = v ?? 1;
                          _start = null;
                        }),
                        decoration: const InputDecoration(labelText: 'Sân', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        isExpanded: true,
                        initialValue: _duration,
                        items: [
                          for (var h = 1; h <= 4; h++) DropdownMenuItem(value: h, child: Text('$h giờ')),
                        ],
                        onChanged: (v) => setState(() {
                          _duration = v ?? 2;
                          _start = null;
                        }),
                        decoration: const InputDecoration(labelText: 'Thời lượng', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Giờ bắt đầu còn trống',
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (starts.isEmpty)
                  const NoteBox('Không còn khung trống phù hợp cho sân và ngày này.')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in starts)
                        ChoiceChip(
                          label: Text(s),
                          selected: _start == s,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _start = s),
                        ),
                    ],
                  ),
                if (_start != null) ...[
                  const SizedBox(height: 12),
                  InfoRow(
                    icon: Icons.payments_outlined,
                    label: 'Giá vãng lai',
                    value: UiFmt.vnd(BookingRules.priceOfRange(
                      _venue,
                      _date,
                      BookingRules.hoursOfRange(
                          _start!, BookingRules.hourLabel(BookingRules.hourOf(_start!) + _duration)),
                    )),
                    emphasize: true,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _walkInNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên & SĐT khách (hoặc ghi chú bảo trì)',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: (_start == null || _busy) ? null : () => _addEntry('WALK_IN'),
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                        icon: const Icon(Icons.person_add_alt_1, size: 18),
                        label: const Text('Vãng lai', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (_start == null || _busy) ? null : () => _addEntry('MAINTENANCE'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                        icon: const Icon(Icons.build_outlined, size: 18),
                        label: const Text('Bảo trì', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
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
