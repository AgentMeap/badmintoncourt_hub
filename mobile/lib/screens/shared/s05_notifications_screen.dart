import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S05: Notifications Center Screen (Module 5)
// Giao diện theo design system: mỗi loại thông báo có icon riêng (không dùng emoji),
// thông báo chưa đọc có chấm + nền nhấn, bộ lọc kèm số lượng, trạng thái rỗng.
class S05NotificationsScreen extends StatefulWidget {
  final AppState appState;
  const S05NotificationsScreen({super.key, required this.appState});

  @override
  State<S05NotificationsScreen> createState() => _S05NotificationsScreenState();
}

class _S05NotificationsScreenState extends State<S05NotificationsScreen> {
  String _filterType = 'ALL';

  static const _filters = {
    'ALL': 'Tất cả',
    'PAYMENT': 'Thanh toán',
    'BOOKING': 'Đặt sân',
    'MATCHMAKING': 'Ghép kèo',
  };

  static IconData _iconOf(String? type) {
    switch (type) {
      case 'PAYMENT':
        return Icons.payments_outlined;
      case 'BOOKING':
        return Icons.event_available_outlined;
      case 'MATCHMAKING':
        return Icons.groups_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  /// Bỏ emoji ở đầu tiêu đề cũ (dữ liệu từ backend / dữ liệu mẫu) vì đã có icon riêng.
  static String _cleanTitle(String raw) =>
      raw.replaceFirst(RegExp(r'^[^\p{L}\p{N}#\[(]+', unicode: true), '').trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final all = widget.appState.notifications;
    final unread = all.where((n) => n['isRead'] != true).length;
    final items = all.where((n) => _filterType == 'ALL' || n['type'] == _filterType).toList();

    return ResponsiveCenter(
      maxWidth: Responsive.defaultContentMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Thông báo',
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      unread > 0 ? '$unread thông báo chưa đọc' : 'Bạn đã đọc hết thông báo',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (unread > 0)
                TextButton.icon(
                  onPressed: () => widget.appState.markAllNotificationsRead(),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('Đọc tất cả'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final e in _filters.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.key == 'ALL' ? '${e.value} (${all.length})' : e.value),
                      selected: _filterType == e.key,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filterType = e.key),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const EmptyState(
              icon: Icons.notifications_none_outlined,
              title: 'Chưa có thông báo',
              message: 'Thông báo về đặt sân, thanh toán và kèo giao lưu sẽ hiện ở đây.',
            )
          else
            ...items.map((n) {
              final isRead = n['isRead'] == true;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isRead ? cs.surface : cs.primaryContainer.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: isRead ? cs.outlineVariant : cs.primary.withValues(alpha: 0.4)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      n['isRead'] = true;
                      widget.appState.goTo(n['targetScreen']?.toString() ?? 'S06');
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isRead ? cs.surfaceContainerHighest : cs.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _iconOf(n['type']?.toString()),
                              size: 20,
                              color: isRead ? cs.onSurfaceVariant : cs.onPrimary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _cleanTitle(n['title']?.toString() ?? ''),
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    if (!isRead)
                                      Semantics(
                                        label: 'Chưa đọc',
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          margin: const EdgeInsets.only(left: 6, top: 6),
                                          decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  n['body']?.toString() ?? '',
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.schedule, size: 14, color: cs.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Text(
                                      n['createdAt']?.toString() ?? '',
                                      style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
