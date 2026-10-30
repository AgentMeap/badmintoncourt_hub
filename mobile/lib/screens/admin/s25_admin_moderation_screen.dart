import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S25: Admin Venue & User Moderation Screen (Luồng 3)
// Giao diện theo design system: thẻ hồ sơ rõ ràng, thông tin có icon (không emoji),
// phê duyệt / từ chối đều có hộp thoại xác nhận (từ chối là thao tác không hoàn tác).
class S25AdminModerationScreen extends StatefulWidget {
  final AppState appState;
  const S25AdminModerationScreen({super.key, required this.appState});

  @override
  State<S25AdminModerationScreen> createState() => _S25AdminModerationScreenState();
}

class _S25AdminModerationScreenState extends State<S25AdminModerationScreen> {
  final Set<Object?> _busy = {};

  Future<void> _moderateVenue(Map<String, dynamic> v, String decision) async {
    final approve = decision == 'APPROVED';
    final ok = await confirmAction(
      context,
      title: approve ? 'Phê duyệt cơ sở?' : 'Từ chối cơ sở?',
      message: approve
          ? '"${v['name']}" sẽ hiển thị trên Trang chủ và Bản đồ cho người chơi.'
          : '"${v['name']}" sẽ bị từ chối và chủ sân được thông báo. Thao tác này không thể hoàn tác.',
      confirmLabel: approve ? 'Phê duyệt' : 'Từ chối',
      destructive: !approve,
    );
    if (!ok || !mounted || _busy.contains(v['id'])) return;

    setState(() {
      _busy.add(v['id']);
      v['status'] = decision;
      if (approve) widget.appState.venues.insert(0, v);
      widget.appState.adminPendingVenues.remove(v);
    });

    try {
      await ApiService.patch('/admin/venues/${v['id']}/status', {'status': decision});
    } catch (_) {}

    if (!mounted) return;
    setState(() => _busy.remove(v['id']));
    widget.appState.pushNotification(
      title: approve ? 'Đã duyệt cơ sở "${v['name']}"' : 'Đã từ chối cơ sở "${v['name']}"',
      body: approve
          ? 'Cơ sở đã hiển thị trên Bản đồ (S07) và Trang chủ (S06).'
          : 'Đã gửi phản hồi từ chối cho chủ sân.',
      type: 'SYSTEM',
      targetScreen: approve ? 'S06' : 'S25',
      context: context,
    );
  }

  Widget _line(ThemeData theme, IconData icon, String text) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pending = widget.appState.adminPendingVenues;

    return ResponsiveCenter(
      maxWidth: Responsive.defaultContentMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context),
        children: [
          Text('Kiểm duyệt cơ sở',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          Text('${pending.length} hồ sơ đang chờ',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          if (pending.isEmpty)
            const EmptyState(
              icon: Icons.task_alt,
              title: 'Đã xử lý hết hồ sơ',
              message: 'Hồ sơ cơ sở mới từ chủ sân sẽ hiện ở đây.',
            )
          else
            for (final v in List<Map<String, dynamic>>.from(pending))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: venueCoverColors(cs, v)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.sports_tennis, color: cs.onPrimary, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(v['name'].toString(),
                                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                Text('Chủ sân: ${v['ownerName'] ?? '-'}',
                                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _line(theme, Icons.place_outlined, '${v['address']}'),
                      _line(theme, Icons.my_location,
                          '${UiFmt.toNum(v['latitude'], 0).toStringAsFixed(4)}, ${UiFmt.toNum(v['longitude'], 0).toStringAsFixed(4)}'),
                      _line(theme, Icons.grid_view_rounded,
                          '${v['totalCourts'] ?? '-'} sân • ${v['openTime'] ?? '05:00'} - ${v['closeTime'] ?? '23:00'}'),
                      _line(theme, Icons.payments_outlined,
                          '${UiFmt.vnd(UiFmt.toNum(v['basePricePerHour'], 0))} - ${UiFmt.vnd(UiFmt.toNum(v['peakPricePerHour'], 0))}/giờ'),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _busy.contains(v['id']) ? null : () => _moderateVenue(v, 'REJECTED'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 48),
                                foregroundColor: cs.error,
                                side: BorderSide(color: cs.error.withValues(alpha: 0.6)),
                              ),
                              icon: const Icon(Icons.close, size: 18),
                              label: const Text('Từ chối'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _busy.contains(v['id']) ? null : () => _moderateVenue(v, 'APPROVED'),
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Phê duyệt'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
