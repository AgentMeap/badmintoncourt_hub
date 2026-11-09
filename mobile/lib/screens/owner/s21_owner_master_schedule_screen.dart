import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/booking_rules.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S21: Owner Master Schedule & Walk-in Management (Luồng 2)
// - Lịch từng ngày tải từ GET /owner/venues/{venueId}/bookings?date= (đầy đủ mọi vé của cơ sở,
//   kèm tên khách) thay vì chỉ 15 vé gần nhất như trước.
// - Danh sách sân lấy từ máy chủ (id sân thật), không còn đánh số 1..n trên máy.
// - Kiểm tra trùng lịch trước khi thêm khách vãng lai / bảo trì; máy chủ kiểm tra lại và
//   tự tính giá vãng lai theo bảng giá cơ sở.
class S21OwnerMasterScheduleScreen extends StatefulWidget {
  final AppState appState;
  const S21OwnerMasterScheduleScreen({super.key, required this.appState});

  @override
  State<S21OwnerMasterScheduleScreen> createState() => _S21OwnerMasterScheduleScreenState();
}

class _S21OwnerMasterScheduleScreenState extends State<S21OwnerMasterScheduleScreen> {
  final _walkInNameCtrl = TextEditingController();
  Json _venue = {};
  late DateTime _date;
  List<Json> _courts = [];
  List<Json> _dayBookings = [];
  Json _summary = {};
  int _courtIndex = 0;
  String? _start;
  int _duration = 2;
  bool _busy = false;
  bool _loading = false;
  Object? _loadError;
  int _loadSeq = 0;

  AppState get _app => widget.appState;

  /// Cơ sở đang hoạt động của chủ sân (chỉ cơ sở đã duyệt mới có lịch).
  List<Json> get _myVenues {
    final own = _app.ownerVenueList.where((v) => v['status'] == 'APPROVED').toList();
    return own.isNotEmpty ? own : OwnerFinance.ownerVenues(_app.venues, _app.userId);
  }

  @override
  void initState() {
    super.initState();
    _date = BookingRules.dateOnly(DateTime.now());
    final venues = _myVenues;
    if (venues.isNotEmpty) {
      _venue = venues.first;
      _load();
    }
  }

  @override
  void dispose() {
    _walkInNameCtrl.dispose();
    super.dispose();
  }

  String get _dateKey => BookingRules.dateKey(_date);

  Future<void> _load() async {
    final venueId = _venue['id'];
    if (venueId == null) return;
    final seq = ++_loadSeq;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final res = await Repos.owner.venueBookings(venueId, date: _dateKey);
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        final serverVenue = asJson(res['venue']);
        if (serverVenue.isNotEmpty) _venue = {..._venue, ...serverVenue};
        _courts = asJsonList(res['courts']).where((c) => c['active'] != false).toList();
        if (_courtIndex >= _courts.length) _courtIndex = 0;
        _dayBookings = asJsonList(res['bookings']);
        _summary = asJson(res['summary']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _loading = false;
        _loadError = e;
      });
    }
  }

  void _select({Json? venue, DateTime? date}) {
    setState(() {
      if (venue != null) {
        _venue = venue;
        _courts = [];
        _courtIndex = 0;
      }
      if (date != null) _date = date;
      _dayBookings = [];
      _summary = {};
      _start = null;
    });
    _load();
  }

  Json? get _court => _courtIndex < _courts.length ? _courts[_courtIndex] : null;

  int get _courtId => UiFmt.toNum(_court?['id'], -1).toInt();

  /// Giờ bắt đầu hợp lệ cho sân/ngày/số giờ đang chọn (không trùng, chưa qua, trong giờ mở cửa).
  List<String> _availableStarts() {
    if (_court == null) return const [];
    final hours = BookingRules.operatingHours(_venue);
    final occ = BookingRules.occupancy(_dayBookings, venueId: _venue['id'], courtId: _courtId, playDate: _dateKey);
    return [
      for (var i = 0; i + _duration <= hours.length; i++)
        if (!hours.sublist(i, i + _duration).any(occ.containsKey) && !BookingRules.isPast(_date, hours[i])) hours[i]
    ];
  }

  Future<void> _addEntry(String type) async {
    final court = _court;
    final start = _start;
    if (_busy || court == null) return;
    final isMaint = type == 'MAINTENANCE';
    if (start == null) {
      _toast('Vui lòng chọn giờ bắt đầu.');
      return;
    }
    final note = _walkInNameCtrl.text.trim();
    if (!isMaint && note.isEmpty) {
      _toast('Vui lòng nhập tên / SĐT khách.');
      return;
    }
    if (!_availableStarts().contains(start)) {
      setState(() => _start = null);
      _toast('Khung giờ này vừa có người đặt, vui lòng chọn lại.');
      return;
    }

    final end = BookingRules.hourLabel(BookingRules.hourOf(start) + _duration);
    final price = isMaint ? 0 : BookingRules.priceOfRange(_venue, _date, BookingRules.hoursOfRange(start, end));
    final ok = await confirmAction(
      context,
      title: isMaint ? 'Khóa sân bảo trì?' : 'Ghi nhận khách vãng lai?',
      message: '${court['name']} • $start - $end • ${UiDate.full(_dateKey)}'
          '${isMaint ? '' : '\nThu tại quầy: ${UiFmt.vnd(price)}'}',
      confirmLabel: isMaint ? 'Khóa sân' : 'Ghi nhận',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);

    // Mã vé, id và giá vãng lai do máy chủ cấp / tính
    final entry = <String, dynamic>{
      'venueId': _venue['id'],
      'courtId': court['id'],
      'customerName': isMaint
          ? (note.isEmpty ? 'Bảo trì sân' : 'Bảo trì: $note')
          : 'Khách vãng lai: $note',
      'bookingType': type,
      'playDate': _dateKey,
      'startTime': start,
      'endTime': end,
      'totalPrice': price.toDouble(),
    };

    try {
      await Repos.booking.createWalkIn(entry);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showApiError(context, e);
      _load(); // lịch có thể đã thay đổi (409): tải lại
      return;
    }
    if (!mounted) return;
    setState(() {
      _start = null;
      _busy = false;
      if (!isMaint) _walkInNameCtrl.clear();
    });
    _toast(isMaint
        ? 'Đã khóa bảo trì ${court['name']} ($start - $end)'
        : 'Đã ghi nhận khách vãng lai ${court['name']} ($start - $end)');
    _load();
    _app.refreshOwnerDashboard().catchError((Object e) => debugPrint('[S21] $e'));
  }

  Future<void> _checkIn(Json b) async {
    final ok = await confirmAction(
      context,
      title: 'Xác nhận khách nhận sân?',
      message: '${b['courtName']} • ${b['startTime']} - ${b['endTime']}\n${b['customerName'] ?? ''}',
      confirmLabel: 'Check-in',
    );
    if (!ok || !mounted) return;
    final Json res;
    try {
      res = await Repos.booking.checkIn('${b['qrCheckInToken'] ?? b['bookingCode']}');
    } catch (e) {
      if (mounted) showApiError(context, e);
      return;
    }
    if (!mounted) return;
    setState(() {
      final server = asJson(res['booking']);
      if (server.isNotEmpty) b.addAll(server);
      b['status'] = 'CHECKED_IN';
    });
    _app.refreshOwnerDashboard().catchError((Object e) => debugPrint('[S21] $e'));
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _entryTile(ThemeData theme, Json b) {
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
    final canCheckIn = !isMaint && !cancelled && status != 'CHECKED_IN' && BookingRules.isPaid(b) &&
        b['playDate'] == BookingRules.dateKey(DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Column(
              children: [
                Text('${b['startTime']}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text('${b['endTime']}', style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
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
                        '$typeLabel • #${b['bookingCode']}'
                        '${isMaint ? '' : ' • ${UiFmt.vnd(UiFmt.toNum(b['totalPrice'], 0))}'}',
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

  Widget _scheduleSection(ThemeData theme) {
    final cs = theme.colorScheme;
    if (_loading && _dayBookings.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Không tải được lịch',
        message: _loadError is ApiException ? (_loadError as ApiException).message : 'Vui lòng thử lại.',
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Thử lại'),
        ),
      );
    }
    if (_dayBookings.isEmpty) {
      return const EmptyState(icon: Icons.event_busy_outlined, title: 'Chưa có ca nào trong ngày');
    }
    final entries = [..._dayBookings]..sort((a, b) {
        final t = '${a['startTime']}'.compareTo('${b['startTime']}');
        return t != 0 ? t : '${a['courtName']}'.compareTo('${b['courtName']}');
      });
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) Divider(height: 1, color: cs.outlineVariant),
            _entryTile(theme, entries[i]),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final venues = _myVenues;

    if (venues.isEmpty || _venue['id'] == null) {
      return const EmptyState(
        icon: Icons.storefront_outlined,
        title: 'Chưa có cơ sở đang hoạt động',
        message: 'Lịch biểu sẽ có khi cơ sở của bạn được Admin phê duyệt.',
      );
    }

    final today = BookingRules.dateOnly(DateTime.now());
    final starts = _availableStarts();
    if (_start != null && !starts.contains(_start)) _start = null;
    final sessions = UiFmt.toNum(_summary['sessions'], 0).toInt();

    return ResponsiveCenter(
      maxWidth: Responsive.defaultContentMaxWidth,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: Responsive.screenPadding(context),
          children: [
            Text('Lịch biểu', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (venues.length > 1) ...[
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: '${_venue['id']}',
                items: [
                  for (final v in venues)
                    DropdownMenuItem(
                      value: '${v['id']}',
                      child: Text('${v['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) {
                  final v = venues.where((v) => '${v['id']}' == id).firstOrNull;
                  if (v != null && '${v['id']}' != '${_venue['id']}') _select(venue: v);
                },
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
                  // 2 ngày trước (xem lại) + hôm nay + 6 ngày tới
                  for (var i = -2; i < 7; i++)
                    Builder(builder: (_) {
                      final d = today.add(Duration(days: i));
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(i == 0 ? 'Hôm nay' : '${UiDate.weekday(BookingRules.dateKey(d))} ${d.day}/${d.month}'),
                          selected: d == _date,
                          showCheckmark: false,
                          onSelected: (_) {
                            if (d != _date) _select(date: d);
                          },
                        ),
                      );
                    }),
                ],
              ),
            ),
            const SizedBox(height: 16),

            SectionHeader('Lịch ${UiDate.full(_dateKey)}',
                trailing: Text(
                  _summary.isEmpty
                      ? ''
                      : '$sessions ca • ${UiFmt.vnd(UiFmt.toNum(_summary['revenue'], 0))}',
                  style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                )),
            if (_loading && _dayBookings.isNotEmpty) const LinearProgressIndicator(minHeight: 2),
            _scheduleSection(theme),
            const SizedBox(height: 24),

            // Thêm nhanh
            const SectionHeader('Thêm vãng lai / khóa bảo trì'),
            SurfaceCard(
              child: _courts.isEmpty
                  ? NoteBox(_loading ? 'Đang tải danh sách sân...' : 'Cơ sở chưa có sân nào đang hoạt động.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                key: ValueKey('court-${_venue['id']}-${_courts.length}'),
                                isExpanded: true,
                                initialValue: _courtIndex,
                                items: [
                                  for (var i = 0; i < _courts.length; i++)
                                    DropdownMenuItem(value: i, child: Text('${_courts[i]['name']}')),
                                ],
                                onChanged: (v) => setState(() {
                                  _courtIndex = v ?? 0;
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
                            label: 'Giá vãng lai (theo bảng giá)',
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
                            hintText: 'VD: Chị Lan - 0912888999',
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
      ),
    );
  }
}
