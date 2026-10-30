import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'video_source_io.dart' if (dart.library.js_interop) 'video_source_web.dart';

/// Giới hạn video giới thiệu kèo: đủ để xem trình độ, tải nhanh, tiết kiệm dung lượng.
class MatchVideoRules {
  MatchVideoRules._();
  static const int maxSeconds = 60;
  static const int maxBytes = 50 * 1024 * 1024;

  static bool hasVideo(Map<String, dynamic> post) =>
      (post['videoUrl']?.toString().isNotEmpty ?? false) ||
      (post['videoLocalPath']?.toString().isNotEmpty ?? false);

  static String formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static String formatSize(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(0)} KB';
}

/// Tạo controller cho video của kèo: ưu tiên URL trên máy chủ, sau đó file trên máy.
VideoPlayerController? matchVideoController(Map<String, dynamic> post) {
  final url = post['videoUrl']?.toString() ?? '';
  if (url.startsWith('http')) return VideoPlayerController.networkUrl(Uri.parse(url));
  final local = post['videoLocalPath']?.toString() ?? '';
  if (local.isNotEmpty) return controllerFromLocalPath(local);
  return null;
}

/// Tạo controller từ đường dẫn video vừa chọn (dùng cho xem trước ở S16).
VideoPlayerController localVideoController(String path) => controllerFromLocalPath(path);

/// Trình phát video kèo: tỉ lệ đúng của video, nút phát/dừng lớn ở giữa,
/// thanh tiến trình kéo được, thời gian, bật/tắt tiếng. Không tự phát.
class MatchVideoPlayer extends StatefulWidget {
  /// Controller truyền từ ngoài (S16 xem trước) — widget KHÔNG dispose controller này.
  final VideoPlayerController? controller;

  /// Hoặc truyền bài đăng kèo để widget tự tạo & tự dispose controller.
  final Map<String, dynamic>? post;

  const MatchVideoPlayer({super.key, this.controller, this.post});

  @override
  State<MatchVideoPlayer> createState() => _MatchVideoPlayerState();
}

class _MatchVideoPlayerState extends State<MatchVideoPlayer> {
  VideoPlayerController? _c;
  bool _owned = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    if (widget.controller != null) {
      _c = widget.controller;
    } else if (widget.post != null) {
      _c = matchVideoController(widget.post!);
      _owned = true;
    }
    final c = _c;
    if (c == null) return;
    c.addListener(_onTick);
    if (!c.value.isInitialized) {
      try {
        await c.initialize();
      } catch (_) {
        if (mounted) setState(() => _error = true);
        return;
      }
    }
    if (mounted) setState(() {});
  }

  void _onTick() {
    if (!mounted) return;
    final v = _c!.value;
    if (v.hasError && !_error) {
      setState(() => _error = true);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _c?.removeListener(_onTick);
    if (_owned) _c?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      if (c.value.position >= c.value.duration) c.seekTo(Duration.zero);
      c.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final c = _c;

    Widget frame(Widget child) => ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ColoredBox(color: Colors.black, child: child),
        );

    if (c == null || _error) {
      return frame(AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_outlined, color: cs.inversePrimary, size: 36),
              const SizedBox(height: 8),
              Text(
                _error ? 'Không phát được video' : 'Chưa có video',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ));
    }
    final v = c.value;
    if (!v.isInitialized) {
      return frame(const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      ));
    }

    // Video dọc (quay bằng điện thoại) thì giới hạn chiều cao để không chiếm cả màn hình
    final ratio = v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio;
    // Center nới lỏng ràng buộc chiều rộng để AspectRatio giữ đúng tỉ lệ (video dọc có viền đen 2 bên)
    return frame(
      Center(
        child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: AspectRatio(
          aspectRatio: ratio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              GestureDetector(onTap: _togglePlay, child: VideoPlayer(c)),
              // Nút phát / dừng ở giữa (ẩn khi đang phát)
              IgnorePointer(
                ignoring: v.isPlaying,
                child: AnimatedOpacity(
                  opacity: v.isPlaying ? 0 : 1,
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Phát video',
                      iconSize: 40,
                      style: IconButton.styleFrom(minimumSize: const Size(64, 64)),
                      onPressed: _togglePlay,
                      icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                    ),
                  ),
                ),
              ),
              // Thanh điều khiển dưới
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black54],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: v.isPlaying ? 'Tạm dừng' : 'Phát',
                        onPressed: _togglePlay,
                        icon: Icon(v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white),
                      ),
                      Text(
                        '${MatchVideoRules.formatDuration(v.position)} / ${MatchVideoRules.formatDuration(v.duration)}',
                        style: theme.textTheme.labelMedium?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: VideoProgressIndicator(
                          c,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          colors: VideoProgressColors(
                            playedColor: cs.primaryContainer,
                            bufferedColor: Colors.white38,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: v.volume == 0 ? 'Bật tiếng' : 'Tắt tiếng',
                        onPressed: () => c.setVolume(v.volume == 0 ? 1 : 0),
                        icon: Icon(v.volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
