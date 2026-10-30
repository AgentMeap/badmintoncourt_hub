import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S06: Customer Home & Discovery
// Thiết kế lại theo design system "Badminton Hub" (skill ui-ux-pro-max):
// - Màu & chữ lấy từ Theme (ColorScheme / TextTheme), không hardcode
// - Icon vector thay cho emoji
// - Phân cấp rõ: Lời chào + Ví > Tìm kiếm + Bộ lọc > Lịch sắp tới > Trợ lý AI > Danh sách sân
// - Vùng chạm tối thiểu 48dp, khoảng cách theo nhịp 4/8/12/16/24
class S06CustomerHomeScreen extends StatefulWidget {
  final AppState appState;
  const S06CustomerHomeScreen({super.key, required this.appState});

  @override
  State<S06CustomerHomeScreen> createState() => _S06CustomerHomeScreenState();
}

enum _VenueSort { nearest, topRated, cheapest }

class _S06CustomerHomeScreenState extends State<S06CustomerHomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _VenueSort _sort = _VenueSort.nearest;

  AppState get _app => widget.appState;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------- Helpers ----------

  String _firstName() {
    final raw = _app.fullName.split('(').first.trim();
    final parts = raw.split(RegExp(r'\s+'));
    return parts.isEmpty ? raw : parts.last;
  }

  String _dateLabel(String raw) {
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Hôm nay';
    if (diff == 1) return 'Ngày mai';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic>? _nextBooking() {
    final list = _app.bookings.where((b) {
      final status = b['status']?.toString() ?? '';
      return b['bookingType'] == 'ONLINE' &&
          status != 'CANCELLED' &&
          status != 'COMPLETED' &&
          status != 'REFUNDED';
    }).toList();
    if (list.isEmpty) return null;
    list.sort((a, b) => '${a['playDate']} ${a['startTime']}'
        .compareTo('${b['playDate']} ${b['startTime']}'));
    return list.first;
  }

  List<Map<String, dynamic>> _visibleVenues() {
    final q = _searchQuery.trim().toLowerCase();
    final list = _app.venues.where((v) {
      if (q.isEmpty) return true;
      return v['name'].toString().toLowerCase().contains(q) ||
          v['address'].toString().toLowerCase().contains(q);
    }).toList();

    switch (_sort) {
      case _VenueSort.nearest:
        list.sort((a, b) => UiFmt.toNum(a['distanceKm'], 999).compareTo(UiFmt.toNum(b['distanceKm'], 999)));
      case _VenueSort.topRated:
        list.sort((a, b) => UiFmt.toNum(b['rating'], 0).compareTo(UiFmt.toNum(a['rating'], 0)));
      case _VenueSort.cheapest:
        list.sort((a, b) =>
            UiFmt.toNum(a['basePricePerHour'], 0).compareTo(UiFmt.toNum(b['basePricePerHour'], 0)));
    }
    return list;
  }

  void _openVenue(Map<String, dynamic> v) {
    _app.selectedVenue = v;
    _app.goTo('S08');
  }

  // ---------- Sections ----------

  Widget _buildGreeting(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Xin chào, ${_firstName()}',
                style: theme.textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                'Hôm nay đánh ở đâu?',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Material(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _app.goTo('S18'),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        size: 20, color: cs.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Ví',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: cs.onPrimaryContainer),
                        ),
                        Text(
                          UiFmt.vnd(_app.walletBalance),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(16);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Tên sân, quận/huyện...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Xóa tìm kiếm',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
              enabledBorder:
                  OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(color: cs.primary, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Tìm trên bản đồ',
          onPressed: () => _app.goTo('S07'),
          style: IconButton.styleFrom(
            minimumSize: const Size(52, 52),
            shape: RoundedRectangleBorder(borderRadius: radius),
          ),
          icon: const Icon(Icons.map_outlined),
        ),
      ],
    );
  }

  Widget _buildSortChips() {
    const options = <_VenueSort, (String, IconData)>{
      _VenueSort.nearest: ('Gần nhất', Icons.near_me_outlined),
      _VenueSort.topRated: ('Đánh giá cao', Icons.star_outline_rounded),
      _VenueSort.cheapest: ('Giá tốt', Icons.sell_outlined),
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final e in options.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(e.value.$2, size: 18),
                label: Text(e.value.$1),
                selected: _sort == e.key,
                showCheckmark: false,
                onSelected: (_) => setState(() => _sort = e.key),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text, {Widget? trailing}) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildNextBookingCard(BuildContext context, Map<String, dynamic> b) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final start = b['startTime']?.toString() ?? '--:--';
    final end = b['endTime']?.toString() ?? '--:--';
    return Material(
      color: cs.primary,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _app.selectedBooking = b;
          _app.goTo('S13');
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 68,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: cs.onPrimary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(
                      _dateLabel(b['playDate']?.toString() ?? ''),
                      style: theme.textTheme.labelSmall?.copyWith(color: cs.onPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      start,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b['venueName']?.toString() ?? 'Sân cầu lông',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${b['courtName'] ?? ''} • $start - $end',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onPrimary.withValues(alpha: 0.9)),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code_2, size: 16, color: cs.onPrimary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Xem vé check-in',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: cs.onPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onPrimary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAiCard(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.secondaryContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _app.goTo('S17'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.auto_awesome, color: cs.secondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hỏi Trợ lý AI',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tìm sân trống, gợi ý kèo hợp trình độ, chính sách hoàn hủy',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSecondaryContainer.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: cs.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVenueCard(BuildContext context, Map<String, dynamic> v) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rating = v['rating'] ?? 4.9;
    final distance = v['distanceKm'];
    final base = UiFmt.toNum(v['basePricePerHour'], 0);
    final peak = UiFmt.toNum(v['peakPricePerHour'], base);
    final open = v['openTime'] ?? '05:00';
    final close = v['closeTime'] ?? '23:00';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: InkWell(
        onTap: () => _openVenue(v),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ảnh bìa sân cầu lông thực tế kèm lớp phủ gradient thương hiệu
            SizedBox(
              height: 112,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Ảnh bìa: gradient làm placeholder, ảnh hiện dần, giải mã đúng kích thước
                  VenueCoverImage(venue: v),
                  // Lớp phủ Gradient đen mờ tăng độ tương phản cho thông tin
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.45),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: -10,
                    bottom: -20,
                    child: Icon(
                      Icons.sports_tennis,
                      size: 108,
                      color: cs.onPrimary.withValues(alpha: 0.12),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 10,
                    child: InfoPill(
                      icon: Icons.star_rounded,
                      label: '$rating',
                      iconColor: Colors.amber.shade700,
                    ),
                  ),
                  if (distance != null)
                    Positioned(
                      right: 12,
                      top: 10,
                      child: InfoPill(icon: Icons.near_me, label: '$distance km'),
                    ),
                  Positioned(
                    left: 12,
                    bottom: 10,
                    child: InfoPill(icon: Icons.schedule, label: '$open - $close'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v['name'].toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.place_outlined, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          v['address'].toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'từ ',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                  TextSpan(
                                    text: UiFmt.k(base),
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: cs.primary,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '/giờ',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${v['totalCourts'] ?? '-'} sân • Cao điểm ${UiFmt.k(peak)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _openVenue(v),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Đặt sân'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'Không tìm thấy sân phù hợp',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Thử tên quận khác hoặc tìm trực tiếp trên bản đồ.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _app.goTo('S07'),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Mở bản đồ'),
          ),
        ],
      ),
    );
  }

  Widget _buildVenueGrid(List<Map<String, dynamic>> venues) {
    // [Responsive] 1 cột Mobile, 2 cột Tablet, 3 cột Desktop
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 560
                ? 2
                : 1;
        const spacing = 12.0;
        final itemWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: venues
              .map((v) => SizedBox(width: itemWidth, child: _buildVenueCard(context, v)))
              .toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final venues = _visibleVenues();
    final next = _nextBooking();
    final pad = Responsive.screenPadding(context);

    return ResponsiveCenter(
      maxWidth: Responsive.defaultContentMaxWidth,
      child: ListView(
        padding: pad.copyWith(top: pad.top + 4, bottom: pad.bottom + 16),
        children: [
          _buildGreeting(context),
          const SizedBox(height: 16),
          _buildSearchRow(context),
          const SizedBox(height: 12),
          _buildSortChips(),
          if (next != null && _searchQuery.isEmpty) ...[
            const SizedBox(height: 24),
            _sectionTitle(context, 'Lịch sắp tới'),
            const SizedBox(height: 8),
            _buildNextBookingCard(context, next),
          ],
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 16),
            _buildAiCard(context),
          ],
          const SizedBox(height: 24),
          _sectionTitle(
            context,
            _searchQuery.isEmpty ? 'Sân gần bạn' : 'Kết quả tìm kiếm',
            trailing: TextButton.icon(
              onPressed: () => _app.goTo('S07'),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Bản đồ'),
            ),
          ),
          Text(
            '${venues.length} cơ sở đã kiểm duyệt',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (venues.isEmpty) _buildEmptyState(context) else _buildVenueGrid(venues),
        ],
      ),
    );
  }
}
