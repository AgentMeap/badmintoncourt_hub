import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:badminton_v2_mobile/core/api/json.dart';
import 'package:badminton_v2_mobile/core/match_deposit.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';
import 'package:badminton_v2_mobile/screens/customer/host_reputation.dart';

/// Các thẻ tương tác trong câu trả lời của Trợ lý AI (S17).
/// Thẻ được máy chủ dựng từ dữ liệu thật (kết quả hàm tra cứu), app chỉ hiển thị:
/// VENUE, VENUE_SLOT (nút Giữ chỗ), MATCH, MINI_MAP, POLICY, BOOKING.
class AiCardList extends StatelessWidget {
  const AiCardList({
    super.key,
    required this.cards,
    required this.onOpenVenue,
    required this.onHoldSlot,
    required this.onOpenMatch,
    required this.onOpenBooking,
    this.busySlotKey,
  });

  final List<Json> cards;
  final void Function(Json venue) onOpenVenue;
  final void Function(Json slot) onHoldSlot;
  final void Function(Object matchId) onOpenMatch;
  final void Function(Object bookingId) onOpenBooking;

  /// Khóa của khung giờ đang gửi yêu cầu giữ chỗ (hiện vòng xoay trên nút).
  final String? busySlotKey;

  static String slotKey(Json slot) =>
      '${slot['courtId']}|${slot['playDate']}|${slot['startTime']}|${slot['endTime']}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final card in cards)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildCard(context, card),
          ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, Json card) {
    switch (card['type']) {
      case 'VENUE':
        return _VenueCard(venue: asJson(card['venue']), onTap: onOpenVenue);
      case 'VENUE_SLOT':
        final slot = asJson(card['slot']);
        return _SlotCard(slot: slot, busy: busySlotKey == slotKey(slot), onHold: onHoldSlot);
      case 'MATCH':
        return _MatchCard(match: asJson(card['match']), onOpen: onOpenMatch);
      case 'MINI_MAP':
        return _MiniMapCard(markers: asJsonList(card['markers']), onOpenVenue: onOpenVenue);
      case 'POLICY':
        return _PolicyCard(
          title: card['title']?.toString() ?? 'Chính sách',
          lines: [for (final l in (card['lines'] as List? ?? const [])) '$l'],
        );
      case 'BOOKING':
        return _BookingCard(booking: asJson(card['booking']), onOpen: onOpenBooking);
      default:
        return const SizedBox.shrink();
    }
  }
}

class _VenueCard extends StatelessWidget {
  const _VenueCard({required this.venue, required this.onTap});
  final Json venue;
  final void Function(Json venue) onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final image = VenueCoverImage.resolveUrl(venue['imageUrl']) ?? '';
    return SurfaceCard(
      padding: const EdgeInsets.all(10),
      onTap: () => onTap(venue),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 56,
              height: 56,
              child: image.isEmpty
                  ? ColoredBox(color: cs.primaryContainer, child: Icon(Icons.sports_tennis, color: cs.primary))
                  : Image.network(
                      image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          ColoredBox(color: cs.primaryContainer, child: Icon(Icons.sports_tennis, color: cs.primary)),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  venue['name']?.toString() ?? 'Sân cầu lông',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  venue['address']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  '${UiFmt.toNum(venue['distanceKm'], 0)} km • ${UiFmt.toNum(venue['rating'], 0)}★ • '
                  '${UiFmt.k(UiFmt.toNum(venue['basePricePerHour'], 0))}-${UiFmt.k(UiFmt.toNum(venue['peakPricePerHour'], 0))}/giờ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.slot, required this.busy, required this.onHold});
  final Json slot;
  final bool busy;
  final void Function(Json slot) onHold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final date = slot['playDate']?.toString() ?? '';
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      borderColor: cs.primary.withValues(alpha: 0.4),
      child: Row(
        children: [
          Icon(Icons.event_available_outlined, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot['venueName']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${slot['courtName']} • ${UiDate.full(date)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(
                  '${slot['startTime']} - ${slot['endTime']} • ${UiFmt.vnd(UiFmt.toNum(slot['totalPrice'], 0))}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: cs.primary, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: busy ? null : () => onHold(slot),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Giữ chỗ'),
          ),
        ],
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.onOpen});
  final Json match;
  final void Function(Object matchId) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final id = match['id'];
    final deposit = MatchDeposit.label(match);
    final role = match['role'];
    // Kèo của tôi: tôi tổ chức (số đơn chờ duyệt) hoặc tôi đã xin (trạng thái đơn)
    final String? mine = role == 'HOST'
        ? (UiFmt.toNum(match['pendingCount'], 0) > 0
            ? 'Bạn tổ chức • ${UiFmt.toNum(match['pendingCount'], 0).toInt()} đơn chờ duyệt'
            : 'Bạn tổ chức • chưa có đơn mới')
        : role == 'MEMBER'
            ? switch (match['myStatus']) {
                'APPROVED' => 'Bạn đã được duyệt',
                'REJECTED' => 'Chủ kèo chưa nhận bạn',
                'REMOVED' => 'Bạn đã bị mời ra',
                _ => 'Đơn của bạn đang chờ duyệt',
              }
            : null;
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      onTap: id == null ? null : () => onOpen(id),
      child: Row(
        children: [
          Icon(Icons.groups_outlined, color: cs.tertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match['title']?.toString() ?? 'Kèo giao lưu',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${match['venueName']} • ${UiDate.full(match['playDate']?.toString() ?? '')} '
                  '${match['startTime']}-${match['endTime']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(
                  '${SkillLevel.label(match['requiredSkill']?.toString())} • còn ${match['slotsLeft']} chỗ • '
                  '${MatchFee.text(match)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.tertiary, fontWeight: FontWeight.w700),
                ),
                if (deposit != null)
                  Text(deposit,
                      style: theme.textTheme.labelMedium?.copyWith(color: cs.secondary, fontWeight: FontWeight.w700)),
                if (mine != null)
                  Text(mine,
                      style: theme.textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700))
                else if (match['host'] is Map)
                  HostReputation.summaryRow(theme, match['host'] as Map),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _MiniMapCard extends StatelessWidget {
  const _MiniMapCard({required this.markers, required this.onOpenVenue});
  final List<Json> markers;
  final void Function(Json venue) onOpenVenue;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final points = [
      for (final m in markers)
        LatLng(UiFmt.toNum(m['latitude'], 10.8753).toDouble(), UiFmt.toNum(m['longitude'], 106.8).toDouble()),
    ];
    if (points.isEmpty) return const SizedBox.shrink();
    final center = LatLng(
      points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length,
      points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 170,
        child: FlutterMap(
          // Bản đồ nhỏ chỉ để nhìn vị trí; chạm vào ghim để mở sân
          options: MapOptions(
            initialCenter: center,
            initialZoom: 13,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.badminton.badminton_v2_mobile',
            ),
            MarkerLayer(
              markers: [
                for (var i = 0; i < points.length; i++)
                  Marker(
                    point: points[i],
                    width: 40,
                    height: 40,
                    child: Semantics(
                      button: true,
                      label: markers[i]['name']?.toString() ?? 'Sân',
                      child: GestureDetector(
                        onTap: () => onOpenVenue({
                          'id': markers[i]['venueId'],
                          'name': markers[i]['name'],
                          'latitude': markers[i]['latitude'],
                          'longitude': markers[i]['longitude'],
                        }),
                        child: Icon(Icons.location_on, size: 36, color: cs.error),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.title, required this.lines});
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.policy_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Icon(Icons.circle, size: 6, color: cs.onSurfaceVariant),
                  ),
                  Expanded(child: Text(l, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, required this.onOpen});
  final Json booking;
  final void Function(Object bookingId) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final id = booking['id'];
    final status = switch (booking['status']?.toString()) {
      'CONFIRMED' => 'Đã thanh toán',
      'CHECKED_IN' => 'Đã nhận sân',
      'HELD' => 'Đang giữ chỗ',
      final s => s ?? '',
    };
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      onTap: id == null ? null : () => onOpen(id),
      child: Row(
        children: [
          Icon(Icons.confirmation_number_outlined, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${booking['venueName']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${booking['courtName']} • ${UiDate.full(booking['playDate']?.toString() ?? '')} '
                  '${booking['startTime']}-${booking['endTime']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(
                  '#${booking['bookingCode']} • $status',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}
