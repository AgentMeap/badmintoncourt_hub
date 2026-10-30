import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

/// Nút "Lên đầu trang" dùng chung cho mọi màn hình (đặt trong AppShell).
///
/// - Theo dõi danh sách cuộn DỌC chính của màn hình (bỏ qua danh sách ngang, cuộn lồng nhau)
/// - Hiện khi đã cuộn sâu hơn ~1 màn hình; ẩn khi đang vuốt xuống để không che nội dung,
///   hiện lại khi dừng hoặc vuốt lên; ẩn khi gần đầu trang
/// - Đặt ở giữa phía trên, tránh đè nút "Đặt sân" ở góc thẻ, thanh tab và thanh hành động dưới
/// - Cuộn mượt; nhảy thẳng nếu hệ thống bật "giảm chuyển động"
class ScrollToTopHost extends StatefulWidget {
  /// Đổi giá trị này khi chuyển màn để đặt lại trạng thái nút.
  final String screenKey;
  final bool enabled;
  final Widget child;
  const ScrollToTopHost({
    super.key,
    required this.screenKey,
    required this.child,
    this.enabled = true,
  });

  @override
  State<ScrollToTopHost> createState() => ScrollToTopHostState();
}

class ScrollToTopHostState extends State<ScrollToTopHost> {
  ScrollPosition? _position;
  bool _visible = false;
  bool _scrollingDown = false;

  @override
  void didUpdateWidget(covariant ScrollToTopHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.screenKey != widget.screenKey || !widget.enabled) {
      _position = null;
      _visible = false;
      _scrollingDown = false;
    }
  }

  bool _onNotification(ScrollNotification n) {
    if (!widget.enabled || n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final ctx = n.context;
    if (ctx != null) _position = Scrollable.maybeOf(ctx)?.position ?? _position;

    if (n is UserScrollNotification) {
      _scrollingDown = n.direction == ScrollDirection.reverse;
    } else if (n is ScrollEndNotification) {
      _scrollingDown = false;
    }

    final m = n.metrics;
    final deep = m.pixels > m.viewportDimension * 1.0;
    final nearTop = m.pixels < m.viewportDimension * 0.5;
    var next = _visible;
    if (nearTop) {
      next = false;
    } else if (deep) {
      next = !_scrollingDown;
    }
    if (next != _visible) setState(() => _visible = next);
    return false;
  }

  /// Cuộn danh sách hiện tại về đầu (dùng cho nút và khi chạm lại tab đang mở).
  Future<void> scrollToTop() async {
    final p = _position;
    if (p == null || !p.hasPixels || !p.hasViewportDimension) return;
    if (p.pixels <= p.minScrollExtent) return;
    if (MediaQuery.of(context).disableAnimations) {
      p.jumpTo(p.minScrollExtent);
    } else {
      // Quãng rất xa: nhảy tới gần đầu trước rồi trượt nốt, tránh hoạt ảnh quá dài
      final near = p.viewportDimension * 2;
      if (p.pixels > near * 2) p.jumpTo(near);
      await p.animateTo(
        p.minScrollExtent,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
    if (mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 200);
    final show = widget.enabled && _visible;

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onNotification,
          child: widget.child,
        ),
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(
            child: IgnorePointer(
              ignoring: !show,
              child: AnimatedSlide(
                offset: show ? Offset.zero : const Offset(0, -1.6),
                duration: duration,
                curve: Curves.easeOut,
                child: AnimatedOpacity(
                  opacity: show ? 1 : 0,
                  duration: duration,
                  child: Semantics(
                    button: true,
                    label: 'Lên đầu trang',
                    excludeSemantics: true,
                    child: Material(
                      color: cs.inverseSurface,
                      elevation: 3,
                      shadowColor: cs.shadow.withValues(alpha: 0.3),
                      shape: const StadiumBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: scrollToTop,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_upward_rounded, size: 18, color: cs.onInverseSurface),
                                const SizedBox(width: 6),
                                Text(
                                  'Lên đầu trang',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: cs.onInverseSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
