import 'package:flutter/material.dart';

/// Bộ tiện ích giao diện dùng chung (design system "Badminton Hub" - skill ui-ux-pro-max).
/// Mọi màu đều suy ra từ ColorScheme của Theme, không hardcode.
class UiFmt {
  static num toNum(dynamic value, num fallback) {
    if (value is num) return value;
    return num.tryParse('$value') ?? fallback;
  }

  /// 80000 -> "80k"
  static String k(num value) => '${value.toInt() ~/ 1000}k';

  /// 350000 -> "350.000đ"
  static String vnd(num value) {
    final s = value.toInt().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf.toString()}đ';
  }
}

/// Mỗi cơ sở một sắc độ riêng (dịch hue từ màu primary của Theme)
/// để phân biệt các sân khi chưa có ảnh thật.
List<Color> venueCoverColors(ColorScheme cs, Map<String, dynamic> v) {
  const hueShifts = [0.0, 32.0, -28.0, 58.0];
  final id = UiFmt.toNum(v['id'], 0).toInt();
  final base = HSLColor.fromColor(cs.primary);
  final shift = hueShifts[id.abs() % hueShifts.length];
  final start = base.withHue((base.hue + shift) % 360);
  final end = start
      .withHue((start.hue + 18) % 360)
      .withLightness((start.lightness + 0.12).clamp(0.0, 0.6).toDouble());
  return [start.toColor(), end.toColor()];
}

/// Nhãn bo tròn nền sáng, đặt trên ảnh bìa.
class InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  const InfoPill({super.key, required this.icon, required this.label, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor ?? cs.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Thanh hành động cố định ở đáy màn hình (tóm tắt + nút chính).
class BottomActionBar extends StatelessWidget {
  final Widget summary;
  final Widget action;
  const BottomActionBar({super.key, required this.summary, required this.action});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(child: summary),
                const SizedBox(width: 12),
                action,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ngày tháng & trạng thái đặt sân
// ---------------------------------------------------------------------------

class UiDate {
  static const _weekdays = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'CN'];

  /// "2026-10-30" -> "Thứ 6, 30/10/2026"
  static String full(String raw) {
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    return '${_weekdays[d.weekday - 1]}, ${_dd(d.day)}/${_dd(d.month)}/${d.year}';
  }

  /// "2026-10-30" -> "Thứ 6"
  static String weekday(String raw) {
    final d = DateTime.tryParse(raw);
    return d == null ? '' : _weekdays[d.weekday - 1];
  }

  /// "2026-10-30" -> "30"
  static String day(String raw) {
    final d = DateTime.tryParse(raw);
    return d == null ? raw : _dd(d.day);
  }

  /// "2026-10-30" -> "Th10"
  static String monthShort(String raw) {
    final d = DateTime.tryParse(raw);
    return d == null ? '' : 'Th${d.month}';
  }

  /// Số giờ giữa "18:00" và "20:00"
  static int hoursBetween(String start, String end) {
    int h(String t) => int.tryParse(t.split(':').first) ?? 0;
    final diff = h(end) - h(start);
    return diff > 0 ? diff : 0;
  }

  static String _dd(int v) => v.toString().padLeft(2, '0');
}

/// Nhãn tiếng Việt + icon + màu cho trạng thái đặt sân (màu luôn đi kèm icon & chữ).
class BookingStatusStyle {
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  const BookingStatusStyle(this.label, this.icon, this.background, this.foreground);

  static BookingStatusStyle of(ColorScheme cs, String? status) {
    switch (status) {
      case 'CONFIRMED':
      case 'PAID':
        return BookingStatusStyle(
            'Đã xác nhận', Icons.check_circle_outline, cs.primaryContainer, cs.onPrimaryContainer);
      case 'HELD':
      case 'PENDING':
        return BookingStatusStyle('Chờ thanh toán', Icons.hourglass_top_rounded,
            WarningTone.container(cs), WarningTone.onContainer(cs));
      case 'CHECKED_IN':
        return BookingStatusStyle(
            'Đã nhận sân', Icons.how_to_reg_outlined, cs.secondaryContainer, cs.onSecondaryContainer);
      case 'COMPLETED':
        return BookingStatusStyle(
            'Hoàn thành', Icons.flag_outlined, cs.surfaceContainerHighest, cs.onSurfaceVariant);
      case 'CANCELLED':
      case 'REFUNDED':
        return BookingStatusStyle(
            'Đã hủy', Icons.cancel_outlined, cs.errorContainer, cs.onErrorContainer);
      default:
        return BookingStatusStyle(status ?? '-', Icons.info_outline,
            cs.surfaceContainerHighest, cs.onSurfaceVariant);
    }
  }
}

class StatusBadge extends StatelessWidget {
  final String? status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = BookingStatusStyle.of(theme.colorScheme, status);
    // Icon nằm trong dòng chữ (WidgetSpan) để: tự cắt "…" khi bị bó hẹp,
    // nhưng KHÔNG dùng Flexible nên đặt trực tiếp trong Row vẫn không lỗi layout.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: s.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(s.icon, size: 14, color: s.foreground),
              ),
            ),
            TextSpan(text: s.label),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: s.foreground,
        ),
      ),
    );
  }
}

/// Thanh tiến trình 3 bước của luồng đặt sân: Chọn giờ -> Thanh toán -> Nhận vé.
/// [current] tính từ 0.
class BookingSteps extends StatelessWidget {
  final int current;
  const BookingSteps({super.key, required this.current});

  static const _labels = ['Chọn giờ', 'Thanh toán', 'Nhận vé'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final children = <Widget>[];
    for (var i = 0; i < _labels.length; i++) {
      final done = i < current;
      final active = i == current;
      final color = (done || active) ? cs.primary : cs.outline;
      children.add(
        Semantics(
          label: 'Bước ${i + 1}: ${_labels[i]}${done ? ', đã xong' : active ? ', đang thực hiện' : ''}',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (done || active) ? cs.primary : cs.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.5),
                ),
                child: done
                    ? Icon(Icons.check_rounded, size: 16, color: cs.onPrimary)
                    : Text(
                        '${i + 1}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: active ? cs.onPrimary : cs.outline,
                        ),
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                _labels[i],
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: (done || active) ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
      if (i < _labels.length - 1) {
        children.add(
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18, left: 6, right: 6),
              child: Container(height: 2, color: i < current ? cs.primary : cs.outlineVariant),
            ),
          ),
        );
      }
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: children);
  }
}

/// Một dòng thông tin: icon + nhãn + giá trị (căn phải).
class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool emphasize;
  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: (emphasize ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)
                  ?.copyWith(
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                color: emphasize ? cs.primary : cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thành phần bố cục dùng chung cho các màn hình
// ---------------------------------------------------------------------------

/// Logo + tiêu đề + mô tả cho các màn xác thực (S01-S04).
class AuthHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const AuthHeader({
    super.key,
    this.icon = Icons.sports_tennis,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, size: 34, color: cs.onPrimary),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
        ),
      ],
    );
  }
}

/// Tiêu đề khu vực + nút phụ (tùy chọn) bên phải.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Thẻ nền surface, viền mảnh, bo 20.
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Color? color;
  final VoidCallback? onTap;
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: color ?? cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor ?? cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Ô chỉ số (KPI) cho dashboard: icon, giá trị lớn, nhãn.
class StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? accent;
  const StatTile({super.key, required this.icon, required this.value, required this.label, this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final a = accent ?? cs.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: a.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: a),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Lưới tự chia cột cho các StatTile (2 cột điện thoại, 4 cột màn rộng).
class StatGrid extends StatelessWidget {
  final List<Widget> children;
  const StatGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 720 ? 4 : 2;
        const gap = 10.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final child in children) SizedBox(width: w, child: child)],
        );
      },
    );
  }
}

/// Trạng thái rỗng: icon + tiêu đề + mô tả + nút (tùy chọn).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

/// Hộp ghi chú: icon + nội dung, tông secondary / cảnh báo / lỗi.
enum NoteTone { info, warning, error, success }

class NoteBox extends StatelessWidget {
  final String text;
  final IconData? icon;
  final NoteTone tone;
  const NoteBox(this.text, {super.key, this.icon, this.tone = NoteTone.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (bg, fg, defIcon) = switch (tone) {
      NoteTone.info => (cs.secondaryContainer, cs.onSecondaryContainer, Icons.info_outline),
      NoteTone.warning => (WarningTone.container(cs), WarningTone.onContainer(cs), Icons.warning_amber_rounded),
      NoteTone.error => (cs.errorContainer, cs.onErrorContainer, Icons.error_outline),
      NoteTone.success => (cs.primaryContainer, cs.onPrimaryContainer, Icons.check_circle_outline),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defIcon, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: fg, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

/// Hộp thoại xác nhận chung. Trả về true nếu người dùng đồng ý.
Future<bool> confirmAction(
  BuildContext context, {
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

/// Nút chính full width, cao 52.
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool tonal;
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.tonal = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = FilledButton.styleFrom(
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
    final child = loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: tonal ? cs.onSecondaryContainer : cs.onPrimary),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          );
    final onTap = loading ? null : onPressed;
    return tonal
        ? FilledButton.tonal(onPressed: onTap, style: style, child: child)
        : FilledButton(onPressed: onTap, style: style, child: child);
  }
}

/// Nhãn tiếng Việt cho mã trình độ cầu lông.
class SkillLevel {
  static const codes = ['NEWBIE', 'TB_YEU', 'TRUNG_BINH', 'KHA'];
  static const _labels = {
    'NEWBIE': 'Mới chơi',
    'TB_YEU': 'TB yếu',
    'TRUNG_BINH': 'Trung bình',
    'KHA': 'Khá',
  };
  static String label(String? code) => _labels[code] ?? (code ?? '-');
}

/// Ảnh bìa cơ sở: luôn có nền gradient theo sắc độ riêng của cơ sở làm placeholder,
/// ảnh mạng hiện dần khi tải xong (tắt hiệu ứng nếu hệ thống bật giảm chuyển động),
/// giải mã đúng kích thước hiển thị (cacheWidth) để tiết kiệm bộ nhớ, lỗi tải thì
/// giữ nguyên gradient. Ảnh là trang trí nên ẩn khỏi trình đọc màn hình.
class VenueCoverImage extends StatelessWidget {
  final Map<String, dynamic> venue;
  const VenueCoverImage({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = venue['imageUrl']?.toString();
    final gradient = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: venueCoverColors(cs, venue),
      ),
    );
    if (url == null || !url.startsWith('http')) {
      return DecoratedBox(decoration: gradient, child: const SizedBox.expand());
    }
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return DecoratedBox(
      decoration: gradient,
      child: LayoutBuilder(
        builder: (context, c) {
          final dpr = MediaQuery.of(context).devicePixelRatio;
          final w = c.maxWidth.isFinite ? (c.maxWidth * dpr).round() : 0;
          return Image.network(
            url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: w > 0 ? w : null,
            excludeFromSemantics: true,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || reduceMotion) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: child,
              );
            },
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}

/// Tông cảnh báo (chờ duyệt, chờ thanh toán, bảo trì, sắp hết giờ giữ chỗ).
/// Tự đổi theo giao diện sáng / tối để không bị chói hoặc thiếu tương phản.
class WarningTone {
  WarningTone._();
  static bool _dark(ColorScheme cs) => cs.brightness == Brightness.dark;
  static Color container(ColorScheme cs) =>
      _dark(cs) ? const Color(0xFF4D3B00) : Colors.amber.shade100;
  static Color onContainer(ColorScheme cs) =>
      _dark(cs) ? Colors.amber.shade100 : Colors.brown.shade800;
}
