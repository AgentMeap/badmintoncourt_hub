import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S13: Booking Detail & QR Check-in Screen (Giao điểm Luồng 1, 2, 4, 5)
// Thiết kế lại dạng "vé": đầu vé màu thương hiệu, thông tin chia ô,
// đường xé răng cưa, mã QR check-in là trọng tâm. Khi vừa thanh toán xong
// hiện thanh tiến trình bước 3 + lời chúc mừng. Vé đã hủy thì làm mờ QR.
class S13BookingDetailQrScreen extends StatelessWidget {
  final AppState appState;
  const S13BookingDetailQrScreen({super.key, required this.appState});

  /// Vé này vừa được thanh toán xong (S10 / S11 đặt cờ trước khi mở S13).
  bool get _justPaid {
    final b = appState.selectedBooking;
    return b != null && appState.justPaidBookingCode == b['bookingCode']?.toString();
  }


  Widget _infoCell(ThemeData theme, String label, String value) {
    final cs = theme.colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final b = appState.selectedBooking ?? appState.bookings.first;
    final status = b['status']?.toString();
    final cancelled = status == 'CANCELLED' || status == 'REFUNDED';
    final token = b['qrCheckInToken']?.toString() ?? 'QR-${b['bookingCode']}';
    final pageBg = theme.scaffoldBackgroundColor;

    return ResponsiveCenter(
      maxWidth: Responsive.defaultFormMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context),
        children: [
          if (_justPaid && !cancelled) ...[
            const BookingSteps(current: 3),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.check_circle, color: cs.primary, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Đặt sân thành công!',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Vé đã được lưu trong mục Lịch đặt.',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // ----- VÉ -----
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              color: cs.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Đầu vé
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    color: cancelled ? cs.surfaceContainerHighest : cs.primary,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'VÉ ĐẶT SÂN',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  letterSpacing: 1.2,
                                  color: (cancelled ? cs.onSurfaceVariant : cs.onPrimary)
                                      .withValues(alpha: 0.85),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                b['venueName']?.toString() ?? '',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: cancelled ? cs.onSurfaceVariant : cs.onPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusBadge(status: status),
                      ],
                    ),
                  ),
                  // Thông tin
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _infoCell(theme, 'Ngày', UiDate.full(b['playDate']?.toString() ?? '')),
                            _infoCell(theme, 'Giờ', '${b['startTime']} - ${b['endTime']}'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _infoCell(theme, 'Sân', b['courtName']?.toString() ?? '-'),
                            _infoCell(theme, 'Mã vé', '#${b['bookingCode']}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Đường xé vé (2 khuyết tròn + nét đứt)
                  SizedBox(
                    height: 24,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: LayoutBuilder(
                            builder: (context, c) {
                              final count = (c.maxWidth / 10).floor();
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: List.generate(
                                  count,
                                  (_) => Container(width: 5, height: 1.5, color: cs.outlineVariant),
                                ),
                              );
                            },
                          ),
                        ),
                        Positioned(
                          left: -12,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(color: pageBg, shape: BoxShape.circle),
                          ),
                        ),
                        Positioned(
                          right: -12,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(color: pageBg, shape: BoxShape.circle),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // QR check-in
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // [Responsive] Kích thước QR co giãn theo chiều rộng vé
                        final qrSize =
                            math.min(constraints.maxWidth * 0.55, 200.0).clamp(130.0, 200.0);
                        return Column(
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Opacity(
                                  opacity: cancelled ? 0.15 : 1,
                                  child: QrImageView(
                                    data: token,
                                    version: QrVersions.auto,
                                    size: qrSize,
                                    backgroundColor: Colors.white,
                                  ),
                                ),
                                if (cancelled)
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: cs.errorContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Vé đã hủy',
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        color: cs.onErrorContainer,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              token,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              cancelled
                                  ? 'Mã này không còn hiệu lực.'
                                  : 'Đưa mã này cho chủ sân quét khi đến nhận sân.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),

          // Đánh giá sân: hiện khi vé đã nhận sân / hoàn thành
          if (b['status'] == 'CHECKED_IN' || b['status'] == 'COMPLETED') ...[
            const SizedBox(height: 16),
            if (b['reviewed'] == true)
              NoteBox('Bạn đã đánh giá sân ${b['reviewRating'] ?? ''} sao. Cảm ơn bạn!',
                  icon: Icons.star_rounded, tone: NoteTone.success)
            else
              PrimaryButton(
                label: 'Đánh giá sân',
                icon: Icons.star_outline_rounded,
                onPressed: () => appState.goTo('S28'),
              ),
          ],

          if (!cancelled) ...[
            const SizedBox(height: 16),
            // Mở kèo giao lưu
            Material(
              color: cs.tertiaryContainer,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => appState.goTo('S16'),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.group_add_outlined, color: cs.onTertiaryContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Thiếu người? Mở kèo giao lưu',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.onTertiaryContainer,
                              ),
                            ),
                            Text(
                              'Tuyển thêm người chơi cho sân này',
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => appState.goTo('S14'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                    label: const Text('Đổi lịch', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => appState.goTo('S14'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      foregroundColor: cs.error,
                      side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
                    ),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Hủy vé', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ],
          if (_justPaid) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => appState.goToTab('S06', 'S06'),
              child: const Text('Về trang chủ'),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
