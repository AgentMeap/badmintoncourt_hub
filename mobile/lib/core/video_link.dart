import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'api/api_client.dart';
import 'video_source_io.dart' if (dart.library.js_interop) 'video_source_web.dart';

/// Video của hồ sơ người chơi (S29/S18) và kèo giao lưu (S16/S15/S30).
/// Dù dán link hay tải từ máy, app và backend chỉ lưu MỘT chuỗi `videoUrl`:
/// - YouTube: youtube.com/watch?v=, youtu.be/, /shorts/, /embed/, /live/, m.youtube.com, music.youtube.com
/// - Link file video trực tiếp qua https: .mp4, .mov, .m4v, .webm
/// - Video đã tải lên máy chủ của mình: đường dẫn tương đối `/uploads/videos/<tên file>`
///   (app tự ghép với địa chỉ backend, nên đổi IP / máy ảo vẫn xem được)
/// - Bản demo khi chưa có backend: `local:<đường dẫn trên máy>` (chỉ xem được trên máy đã chọn video)
enum VideoLinkKind { youtube, direct, uploaded, local }

class VideoLink {
  final VideoLinkKind kind;

  /// Link đã chuẩn hóa để lưu (YouTube luôn về dạng https://www.youtube.com/watch?v=ID).
  final String url;
  final String? youtubeId;

  const VideoLink._(this.kind, this.url, this.youtubeId);

  static const int maxLength = 500;
  static const uploadedPrefix = '/uploads/videos/';
  static const localPrefix = 'local:';
  static const _directExt = ['.mp4', '.mov', '.m4v', '.webm'];
  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  bool get isYoutube => kind == VideoLinkKind.youtube;

  /// Video do người dùng tải từ máy (lên máy chủ hoặc bản demo trên máy).
  bool get isFromDevice => kind == VideoLinkKind.uploaded || kind == VideoLinkKind.local;

  /// Địa chỉ dùng để phát / mở: video tải lên được ghép với địa chỉ backend.
  String get playableUrl => switch (kind) {
        VideoLinkKind.uploaded => '${ApiClient.origin}$url',
        VideoLinkKind.local => url.substring(localPrefix.length),
        _ => url,
      };

  /// Ảnh xem trước của YouTube (không cần API key).
  String? get thumbnailUrl => isYoutube ? 'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg' : null;

  /// Trả về null nếu link trống hoặc không hợp lệ.
  static VideoLink? tryParse(String? raw) => _parse(raw).$1;

  /// Thông báo lỗi để hiện dưới ô nhập; null nếu trống hoặc hợp lệ.
  static String? validate(String? raw) => _parse(raw).$2;

  static (VideoLink?, String?) _parse(String? raw) {
    var text = (raw ?? '').trim();
    if (text.isEmpty) return (null, null);
    if (text.length > maxLength) return (null, 'Link quá dài (tối đa $maxLength ký tự).');
    if (text.startsWith(uploadedPrefix) && text.length > uploadedPrefix.length) {
      return (VideoLink._(VideoLinkKind.uploaded, text, null), null);
    }
    if (text.startsWith(localPrefix) && text.length > localPrefix.length) {
      return (VideoLink._(VideoLinkKind.local, text, null), null);
    }
    if (!text.contains('://')) text = 'https://$text';

    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) {
      return (null, 'Link chưa đúng định dạng.');
    }
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www|m|music)\.'), '');

    // YouTube
    if (host == 'youtu.be' || host == 'youtube.com' || host == 'youtube-nocookie.com') {
      String? id;
      final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (host == 'youtu.be') {
        id = seg.isNotEmpty ? seg.first : null;
      } else if (seg.isNotEmpty && seg.first == 'watch') {
        id = uri.queryParameters['v'];
      } else if (seg.length >= 2 && const ['shorts', 'embed', 'live', 'v'].contains(seg.first)) {
        id = seg[1];
      }
      if (id == null || !_idPattern.hasMatch(id)) {
        return (null, 'Không tìm thấy video trong link YouTube này. Hãy mở video rồi bấm Chia sẻ > Sao chép đường liên kết.');
      }
      return (VideoLink._(VideoLinkKind.youtube, 'https://www.youtube.com/watch?v=$id', id), null);
    }

    // Link file video trực tiếp
    final path = uri.path.toLowerCase();
    if (_directExt.any(path.endsWith)) {
      if (uri.scheme != 'https') return (null, 'Hãy dùng link bắt đầu bằng https://');
      return (VideoLink._(VideoLinkKind.direct, uri.toString(), null), null);
    }

    return (null, 'Chưa hỗ trợ link này. Hãy dùng link YouTube hoặc link file video (.mp4).');
  }
}

/// Mở link bằng ứng dụng / trình duyệt bên ngoài.
Future<void> openVideoExternally(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// Ô nhập link video: nút Dán / Xóa, báo lỗi ngay khi gõ, link hợp lệ thì hiện xem trước.
class VideoLinkField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? helperText;
  final ValueChanged<String>? onChanged;

  const VideoLinkField({
    super.key,
    required this.controller,
    this.label = 'Link video',
    this.helperText = 'Dán link YouTube hoặc link file .mp4',
    this.onChanged,
  });

  @override
  State<VideoLinkField> createState() => _VideoLinkFieldState();
}

class _VideoLinkFieldState extends State<VideoLinkField> {
  void _changed() {
    setState(() {});
    widget.onChanged?.call(widget.controller.text);
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) return;
      widget.controller.text = text;
      widget.controller.selection = TextSelection.collapsed(offset: text.length);
      _changed();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final link = VideoLink.tryParse(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          keyboardType: TextInputType.url,
          autocorrect: false,
          maxLength: VideoLink.maxLength,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: 'https://youtu.be/...',
            helperText: widget.helperText,
            errorText: VideoLink.validate(text),
            errorMaxLines: 3,
            counterText: '',
            prefixIcon: const Icon(Icons.link),
            border: const OutlineInputBorder(),
            suffixIcon: text.isEmpty
                ? IconButton(tooltip: 'Dán link', onPressed: _paste, icon: const Icon(Icons.content_paste))
                : IconButton(
                    tooltip: 'Xóa link',
                    onPressed: () {
                      widget.controller.clear();
                      _changed();
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        if (link != null) ...[
          const SizedBox(height: 10),
          VideoLinkPlayer(key: ValueKey(link.url), url: link.url),
        ],
      ],
    );
  }
}

/// Trình phát video từ link. Ban đầu chỉ hiện ảnh xem trước + nút phát (nhẹ, danh sách không bị chậm);
/// bấm phát mới tải trình phát YouTube / video.
class VideoLinkPlayer extends StatefulWidget {
  final String? url;
  const VideoLinkPlayer({super.key, required this.url});

  /// Trình phát YouTube nhúng chạy trên Android, iOS, macOS và web; nền tảng khác mở ra ngoài.
  static bool get canEmbedYoutube =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  State<VideoLinkPlayer> createState() => _VideoLinkPlayerState();
}

class _VideoLinkPlayerState extends State<VideoLinkPlayer> {
  bool _started = false;
  bool _error = false;
  YoutubePlayerController? _yt;
  StreamSubscription<YoutubePlayerValue>? _ytSub;
  VideoPlayerController? _vp;

  VideoLink? get _link => VideoLink.tryParse(widget.url);

  @override
  void dispose() {
    _ytSub?.cancel();
    _yt?.close();
    _vp?.removeListener(_onVideoTick);
    _vp?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final link = _link;
    if (link == null || _started) return;
    if (link.isYoutube && !VideoLinkPlayer.canEmbedYoutube) {
      await openVideoExternally(link.playableUrl);
      return;
    }
    setState(() => _started = true);

    if (link.isYoutube) {
      final c = YoutubePlayerController.fromVideoId(
        videoId: link.youtubeId!,
        autoPlay: true,
        params: const YoutubePlayerParams(showFullscreenButton: true, strictRelatedVideos: true),
      );
      _ytSub = c.listen((v) {
        if (v.error != YoutubeError.none && !_error && mounted) setState(() => _error = true);
      });
      setState(() => _yt = c);
      return;
    }

    final c = link.kind == VideoLinkKind.local
        ? controllerFromLocalPath(link.playableUrl)
        : VideoPlayerController.networkUrl(Uri.parse(link.playableUrl));
    setState(() => _vp = c);
    c.addListener(_onVideoTick);
    try {
      await c.initialize();
      if (!mounted) return;
      await c.play();
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  void _onVideoTick() {
    if (!mounted) return;
    final v = _vp!.value;
    if (v.hasError && !_error) {
      setState(() => _error = true);
    } else {
      setState(() {});
    }
  }

  void _toggleVideo() {
    final c = _vp;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      if (c.value.position >= c.value.duration) c.seekTo(Duration.zero);
      c.play();
    }
  }

  static String _fmt(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  Widget _frame(Widget child) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ColoredBox(color: Colors.black, child: child),
      );

  Widget _message(ThemeData theme, IconData icon, String text, {String? openUrl}) {
    return _frame(AspectRatio(
      aspectRatio: 16 / 9,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 36),
              const SizedBox(height: 8),
              Text(text,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white)),
              if (openUrl != null) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => openVideoExternally(openUrl),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(_link?.isYoutube == true ? 'Mở trên YouTube' : 'Mở trong trình duyệt'),
                ),
              ],
            ],
          ),
        ),
      ),
    ));
  }

  Widget _poster(ThemeData theme, VideoLink link) {
    final cs = theme.colorScheme;
    return _frame(AspectRatio(
      aspectRatio: 16 / 9,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _start,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (link.thumbnailUrl != null)
                Image.network(
                  link.thumbnailUrl!,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                )
              else
                const Icon(Icons.movie_outlined, size: 48, color: Colors.white24),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
              ),
              Center(
                child: Semantics(
                  button: true,
                  label: 'Phát video',
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                    child: Icon(Icons.play_arrow_rounded, size: 40, color: cs.onPrimary),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                bottom: 10,
                child: Row(
                  children: [
                    Icon(link.isYoutube ? Icons.smart_display_outlined : Icons.movie_outlined,
                        size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(link.isYoutube ? 'YouTube' : 'Video',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _directPlayer(ThemeData theme, VideoPlayerController c) {
    final cs = theme.colorScheme;
    final v = c.value;
    if (!v.isInitialized) {
      return _frame(const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      ));
    }
    final ratio = v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio;
    // Center nới ràng buộc chiều rộng để video dọc giữ đúng tỉ lệ (viền đen 2 bên)
    return _frame(Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: AspectRatio(
          aspectRatio: ratio,
          child: Stack(
            children: [
              Positioned.fill(child: GestureDetector(onTap: _toggleVideo, child: VideoPlayer(c))),
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
                        onPressed: _toggleVideo,
                        icon: Icon(v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white),
                      ),
                      Text('${_fmt(v.position)} / ${_fmt(v.duration)}',
                          style: theme.textTheme.labelMedium?.copyWith(color: Colors.white)),
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
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = _link;
    if (link == null) return _message(theme, Icons.link_off, 'Link video không hợp lệ');
    if (_error) {
      return _message(
        theme,
        Icons.videocam_off_outlined,
        switch (link.kind) {
          VideoLinkKind.youtube => 'Video không phát được trong app (có thể bị đặt riêng tư hoặc tắt nhúng).',
          VideoLinkKind.uploaded => 'Không tải được video từ máy chủ. Kiểm tra kết nối hoặc backend.',
          VideoLinkKind.local => 'Video trên máy không còn (có thể đã bị xóa). Hãy chọn lại.',
          VideoLinkKind.direct => 'Không phát được video từ link này.',
        },
        openUrl: link.kind == VideoLinkKind.local ? null : link.playableUrl,
      );
    }
    if (!_started) return _poster(theme, link);
    if (_yt != null) return _frame(YoutubePlayer(controller: _yt!, aspectRatio: 16 / 9));
    if (_vp != null) return _directPlayer(theme, _vp!);
    return _poster(theme, link);
  }
}

/// Mở bottom sheet xem video (dùng khi chủ kèo xem video của người xin tham gia).
Future<void> showVideoSheet(BuildContext context, {required String title, String? subtitle, required String url}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (subtitle != null)
                Text(subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              VideoLinkPlayer(url: url),
            ],
          ),
        ),
      );
    },
  );
}
