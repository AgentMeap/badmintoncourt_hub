import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S08: Venue Detail Screen
// Thiết kế lại theo design system "Badminton Hub" (skill ui-ux-pro-max):
// ảnh bìa cùng sắc độ với thẻ ở Home, thông tin chia khối rõ ràng,
// nút "Chọn sân & giờ" cố định ở đáy màn hình.
class S08VenueDetailScreen extends StatelessWidget {
  final AppState appState;
  const S08VenueDetailScreen({super.key, required this.appState});

  Widget _statTile(BuildContext context, IconData icon, String value, String label) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: cs.primary),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceRow(BuildContext context,
      {required IconData icon,
      required String title,
      required String time,
      required num price,
      bool highlight = false}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight ? cs.primaryContainer : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: highlight ? cs.onPrimaryContainer : cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: highlight ? cs.onPrimaryContainer : cs.onSurface,
                  ),
                ),
                Text(
                  time,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: highlight
                        ? cs.onPrimaryContainer.withValues(alpha: 0.85)
                        : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: UiFmt.vnd(price),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: highlight ? cs.onPrimaryContainer : cs.primary,
                  ),
                ),
                TextSpan(
                  text: '/giờ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: highlight ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final v = appState.selectedVenue ?? appState.venues.first;
    final base = UiFmt.toNum(v['basePricePerHour'], 0);
    final peak = UiFmt.toNum(v['peakPricePerHour'], base);
    final open = v['openTime'] ?? '05:00';
    final close = v['closeTime'] ?? '23:00';
    final distance = v['distanceKm'];
    final description = v['description']?.toString() ?? '';

    return Column(
      children: [
        Expanded(
          child: ResponsiveCenter(
            maxWidth: Responsive.defaultContentMaxWidth,
            child: ListView(
              padding: Responsive.screenPadding(context),
              children: [
                // Ảnh bìa sân cầu lông thực tế (có lớp phủ gradient và fallback)
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 180),
                    child: Stack(
                      children: [
                        // Ảnh nền thực tế hoặc DecoratedBox fallback
                        Positioned.fill(
                          child: VenueCoverImage(venue: v),
                        ),
                        // Lớp phủ Gradient đen tối bảo đảm độ tương phản cao cho chữ và pill
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.35),
                                  Colors.black.withValues(alpha: 0.20),
                                  Colors.black.withValues(alpha: 0.75),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: -16,
                          bottom: -26,
                          child: Icon(
                            Icons.sports_tennis,
                            size: 160,
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  InfoPill(
                                    icon: Icons.star_rounded,
                                    label: '${v['rating'] ?? 4.9}',
                                    iconColor: Colors.amber.shade700,
                                  ),
                                  if (distance != null)
                                    InfoPill(icon: Icons.near_me, label: '$distance km'),
                                  const InfoPill(
                                    icon: Icons.verified_outlined,
                                    label: 'Đã kiểm duyệt',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 52),
                              Text(
                                v['name'].toString(),
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Địa chỉ + chỉ đường
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(Icons.place_outlined, size: 20, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        v['address'].toString(),
                        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => appState.goTo('S07'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                      icon: const Icon(Icons.directions_outlined, size: 18),
                      label: const Text('Bản đồ'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Thông số nhanh
                Row(
                  children: [
                    _statTile(context, Icons.grid_view_rounded, '${v['totalCourts'] ?? '-'} sân',
                        'Thảm Yonex'),
                    const SizedBox(width: 8),
                    _statTile(context, Icons.schedule, '$open - $close', 'Giờ mở cửa'),
                    const SizedBox(width: 8),
                    _statTile(context, Icons.star_outline_rounded, '${v['rating'] ?? 4.9}/5',
                        'Đánh giá'),
                  ],
                ),

                if (description.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('Giới thiệu',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                Text('Bảng giá',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _priceRow(
                  context,
                  icon: Icons.wb_sunny_outlined,
                  title: 'Giờ thường',
                  time: '05:00 - 17:00, thứ 2 - thứ 6',
                  price: base,
                ),
                const SizedBox(height: 8),
                _priceRow(
                  context,
                  icon: Icons.nightlight_outlined,
                  title: 'Giờ vàng',
                  time: '17:00 - 23:00 & cuối tuần',
                  price: peak,
                  highlight: true,
                ),

                const SizedBox(height: 24),
                // Kèo giao lưu tại cơ sở
                Material(
                  color: cs.tertiaryContainer,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => appState.goTo('S15'),
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
                            child: Icon(Icons.groups_outlined, color: cs.tertiary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Có kèo giao lưu đang tuyển người',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: cs.onTertiaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Xem danh sách kèo và xin ghép đội tại cơ sở này',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onTertiaryContainer.withValues(alpha: 0.85),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: cs.onTertiaryContainer),
                        ],
                      ),
                    ),
                  ),
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
              Text('Giá từ',
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: UiFmt.k(base),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.primary,
                      ),
                    ),
                    TextSpan(
                      text: '/giờ',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          action: FilledButton.icon(
            onPressed: () => appState.goTo('S09'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.event_available_outlined),
            label: const Text('Chọn sân & giờ'),
          ),
        ),
      ],
    );
  }
}
