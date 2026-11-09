import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'ui_kit.dart';
import 'video_link.dart';
import 'video_upload.dart';

enum _VideoSource { link, device }

enum _UploadStep { idle, checking, uploading, failed, done }

/// Ô video dạng tùy chọn: [ Dán link | Tải từ máy ].
/// Dù chọn cách nào, kết quả trả ra qua [onChanged] luôn là MỘT chuỗi `videoUrl`
/// (rỗng = không có video). [onBusyChanged] báo đang kiểm tra / tải lên để màn cha khóa nút Lưu.
class VideoInput extends StatefulWidget {
  final String initialUrl;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool>? onBusyChanged;
  final String linkHelper;

  const VideoInput({
    super.key,
    required this.initialUrl,
    required this.onChanged,
    this.onBusyChanged,
    this.linkHelper = 'Dán link YouTube hoặc link file .mp4',
  });

  @override
  State<VideoInput> createState() => _VideoInputState();
}

class _VideoInputState extends State<VideoInput> {
  late _VideoSource _source;
  late final TextEditingController _linkCtrl;

  _UploadStep _step = _UploadStep.idle;
  String _deviceUrl = ''; // /uploads/videos/... hoặc local:...
  String? _error;
  double _progress = 0;
  PickedVideo? _picked;
  VideoUploadTask? _task;

  @override
  void initState() {
    super.initState();
    final initial = VideoLink.tryParse(widget.initialUrl);
    if (initial != null && initial.isFromDevice) {
      _source = _VideoSource.device;
      _deviceUrl = initial.url;
      _step = _UploadStep.done;
      _linkCtrl = TextEditingController();
    } else {
      _source = _VideoSource.link;
      _linkCtrl = TextEditingController(text: widget.initialUrl);
    }
  }

  @override
  void dispose() {
    _task?.cancel();
    _linkCtrl.dispose();
    super.dispose();
  }

  bool get _busy => _step == _UploadStep.checking || _step == _UploadStep.uploading;

  void _emit() {
    widget.onChanged(_source == _VideoSource.link ? _linkCtrl.text.trim() : _deviceUrl);
    widget.onBusyChanged?.call(_busy);
  }

  void _setStep(_UploadStep step, {String? error}) {
    if (!mounted) return;
    setState(() {
      _step = step;
      _error = error;
    });
    _emit();
  }

  void _switchSource(_VideoSource s) {
    if (s == _source || _busy) return;
    setState(() => _source = s);
    _emit();
  }

  // ---------- Tải từ máy ----------

  Future<void> _pick() async {
    if (_busy) return;
    XFile? file;
    try {
      file = await VideoUploadService.pickFromGallery();
    } catch (_) {
      _setStep(_deviceUrl.isEmpty ? _UploadStep.idle : _UploadStep.done,
          error: 'Không mở được thư viện ảnh. Hãy kiểm tra quyền truy cập ảnh của ứng dụng.');
      return;
    }
    if (file == null) return; // người dùng bỏ chọn

    _setStep(_UploadStep.checking);
    final PickedVideo picked;
    try {
      picked = await VideoUploadService.inspect(file);
    } on VideoUploadException catch (e) {
      _setStep(_deviceUrl.isEmpty ? _UploadStep.idle : _UploadStep.done, error: e.message);
      return;
    }
    if (!mounted) return;

    // Cách A: vượt giới hạn thì không tự cắt, hướng dẫn người dùng tự cắt rồi chọn lại
    if (picked.tooLarge || picked.tooLong) {
      _setStep(_deviceUrl.isEmpty ? _UploadStep.idle : _UploadStep.done);
      final again = await _showTrimGuide(picked);
      if (again == true && mounted) await _pick();
      return;
    }
    _picked = picked;
    await _upload();
  }

  Future<void> _upload() async {
    final picked = _picked;
    if (picked == null) return;
    setState(() => _progress = 0);
    _setStep(_UploadStep.uploading);
    final task = VideoUploadTask(picked.file, picked.bytes, onProgress: (p) {
      if (mounted) setState(() => _progress = p);
    });
    _task = task;
    try {
      final url = await task.start();
      _deviceUrl = url;
      _setStep(_UploadStep.done);
    } on VideoUploadException catch (e) {
      if (!mounted || _task != task) return;
      _setStep(_UploadStep.failed, error: e.message);
    } finally {
      if (_task == task) _task = null;
    }
  }

  void _cancelUpload() {
    _task?.cancel();
    _task = null;
    _setStep(_deviceUrl.isEmpty ? _UploadStep.idle : _UploadStep.done, error: 'Đã hủy tải lên.');
  }

  /// Chưa có backend (đồ án demo): dùng file trên máy, chỉ xem được trên máy này.
  void _useLocal() {
    final picked = _picked;
    if (picked == null) return;
    _deviceUrl = VideoUploadService.localValue(picked.file);
    _setStep(_UploadStep.done);
  }

  void _remove() {
    _deviceUrl = '';
    _picked = null;
    _setStep(_UploadStep.idle);
  }

  Future<bool?> _showTrimGuide(PickedVideo v) {
    final theme = Theme.of(context);
    final reasons = <String>[
      if (v.tooLong)
        'Video dài ${VideoUploadRules.formatDuration(v.duration)}, tối đa ${VideoUploadRules.maxSeconds} giây.',
      if (v.tooLarge)
        'Video nặng ${VideoUploadRules.formatSize(v.bytes)}, tối đa ${VideoUploadRules.formatSize(VideoUploadRules.maxBytes)}.',
    ];
    Widget step(String n, String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 22, child: Text(n, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ],
          ),
        );
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.content_cut),
        title: Text(v.tooLong ? 'Video dài quá ${VideoUploadRules.maxSeconds} giây' : 'Video quá nặng'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in reasons) Text(r, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              Text('Cắt video bằng app Ảnh có sẵn trên điện thoại:',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('iPhone', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              step('1.', 'Mở app Ảnh, chọn video, bấm Sửa.'),
              step('2.', 'Kéo 2 đầu thanh khung hình bên dưới để giữ đoạn ≤ ${VideoUploadRules.maxSeconds} giây.'),
              step('3.', 'Bấm Xong > Lưu video thành video mới.'),
              const SizedBox(height: 8),
              Text('Android', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              step('1.', 'Mở Google Photos hoặc Thư viện, chọn video, bấm Sửa / Chỉnh sửa.'),
              step('2.', 'Kéo 2 đầu thanh cắt để giữ đoạn ≤ ${VideoUploadRules.maxSeconds} giây.'),
              step('3.', 'Bấm Lưu bản sao.'),
              if (v.tooLarge) ...[
                const SizedBox(height: 10),
                Text('Mẹo: quay ở độ phân giải 720p hoặc 1080p (không quay 4K) để video nhẹ hơn.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Để sau')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Chọn video khác')),
        ],
      ),
    );
  }

  // ---------- Giao diện ----------

  Widget _deviceSection(ThemeData theme) {
    final cs = theme.colorScheme;
    final link = VideoLink.tryParse(_deviceUrl);

    switch (_step) {
      case _UploadStep.checking:
        return SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 12),
              Expanded(child: Text('Đang kiểm tra video...', style: theme.textTheme.bodyMedium)),
            ],
          ),
        );

      case _UploadStep.uploading:
        {
          final p = _picked!;
          return SurfaceCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_upload_outlined, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Đang tải lên ${(_progress * 100).round()}% • ${VideoUploadRules.formatSize(p.bytes)}',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(onPressed: _cancelUpload, child: const Text('Hủy')),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(value: _progress, minHeight: 6),
                  ),
                ),
                if (p.heavy) ...[
                  const SizedBox(height: 8),
                  Text('Video khá nặng, có thể mất vài phút nếu dùng 4G.',
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ],
            ),
          );
        }

      case _UploadStep.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NoteBox(_error ?? 'Tải lên thất bại.', tone: NoteTone.error, icon: Icons.cloud_off_outlined),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _upload,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Thử lại'),
                ),
                OutlinedButton.icon(
                  onPressed: _useLocal,
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  icon: const Icon(Icons.phone_android, size: 18),
                  label: const Text('Dùng tạm trên máy này'),
                ),
                TextButton(onPressed: _remove, child: const Text('Bỏ video')),
              ],
            ),
          ],
        );

      case _UploadStep.done when link != null:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VideoLinkPlayer(key: ValueKey(_deviceUrl), url: _deviceUrl),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(link.kind == VideoLinkKind.local ? Icons.phone_android : Icons.cloud_done_outlined,
                    size: 18, color: link.kind == VideoLinkKind.local ? cs.onSurfaceVariant : cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    link.kind == VideoLinkKind.local ? 'Chỉ xem được trên máy này (chưa tải lên)' : 'Đã tải lên',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                TextButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Đổi'),
                ),
                TextButton.icon(
                  onPressed: _remove,
                  style: TextButton.styleFrom(foregroundColor: cs.error),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Xóa'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              NoteBox(_error!, tone: NoteTone.warning),
            ],
          ],
        );

      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SurfaceCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.video_library_outlined, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Chọn video từ thư viện ảnh của điện thoại. Tối đa ${VideoUploadRules.maxSeconds} giây, '
                          '${VideoUploadRules.formatSize(VideoUploadRules.maxBytes)}.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pick,
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Chọn video từ thư viện'),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              NoteBox(_error!, tone: NoteTone.warning),
            ],
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<_VideoSource>(
          segments: const [
            ButtonSegment(value: _VideoSource.link, icon: Icon(Icons.link), label: Text('Dán link')),
            ButtonSegment(value: _VideoSource.device, icon: Icon(Icons.upload_file), label: Text('Tải từ máy')),
          ],
          selected: {_source},
          showSelectedIcon: false,
          onSelectionChanged: _busy ? null : (s) => _switchSource(s.first),
        ),
        const SizedBox(height: 12),
        if (_source == _VideoSource.link)
          VideoLinkField(
            controller: _linkCtrl,
            label: 'Link video',
            helperText: widget.linkHelper,
            onChanged: (_) => _emit(),
          )
        else
          _deviceSection(theme),
      ],
    );
  }
}
