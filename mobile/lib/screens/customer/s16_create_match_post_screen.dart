import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/match_video.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S16: Create Match Post Screen (Luồng 5)
// Giao diện theo design system + sửa logic:
// - Số người hiện có / tối đa chọn bằng bộ đếm (trước đây gán cứng 3/6)
// - Kiểm tra tiêu đề, chi phí; không cho mở kèo từ vé đã hủy
// - Video nhóm đánh (không bắt buộc): chọn từ thư viện hoặc quay mới, tối đa 60 giây / 50 MB,
//   xem trước trước khi đăng; người xin tham gia xem ở S30 để biết kèo có hợp trình độ không
class S16CreateMatchPostScreen extends StatefulWidget {
  final AppState appState;
  const S16CreateMatchPostScreen({super.key, required this.appState});

  @override
  State<S16CreateMatchPostScreen> createState() => _S16CreateMatchPostScreenState();
}

class _S16CreateMatchPostScreenState extends State<S16CreateMatchPostScreen> {
  final _titleCtrl = TextEditingController(
    text: 'Giao lưu cầu lông tối nay - Tuyển thêm 2 nam/nữ đánh đôi vui vẻ',
  );
  final _feeCtrl = TextEditingController(text: '65000');
  final _picker = ImagePicker();
  String _skill = 'TB_YEU';
  int _currentPlayers = 2;
  int _maxPlayers = 6;
  bool _loading = false;

  XFile? _video;
  VideoPlayerController? _preview;
  int _videoBytes = 0;
  Duration _videoDuration = Duration.zero;
  bool _pickingVideo = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _feeCtrl.dispose();
    _preview?.dispose();
    super.dispose();
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickVideo(ImageSource source) async {
    if (_pickingVideo) return;
    setState(() => _pickingVideo = true);
    XFile? picked;
    try {
      picked = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: MatchVideoRules.maxSeconds),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _pickingVideo = false);
        _toast('Không mở được ${source == ImageSource.camera ? 'camera' : 'thư viện'}. Hãy kiểm tra quyền truy cập.');
      }
      return;
    }
    if (picked == null) {
      if (mounted) setState(() => _pickingVideo = false);
      return;
    }

    final bytes = await picked.length();
    if (bytes > MatchVideoRules.maxBytes) {
      if (!mounted) return;
      setState(() => _pickingVideo = false);
      _toast('Video ${MatchVideoRules.formatSize(bytes)} quá lớn. Tối đa ${MatchVideoRules.formatSize(MatchVideoRules.maxBytes)}.');
      return;
    }

    final controller = localVideoController(picked.path);
    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _pickingVideo = false);
      _toast('Không đọc được video này. Hãy chọn video khác (MP4/MOV).');
      return;
    }
    final duration = controller.value.duration;
    // Thư viện không áp maxDuration như camera nên kiểm tra lại (cho dư 1 giây do làm tròn)
    if (duration.inSeconds > MatchVideoRules.maxSeconds + 1) {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _pickingVideo = false);
      _toast('Video dài ${MatchVideoRules.formatDuration(duration)}. Tối đa ${MatchVideoRules.maxSeconds} giây, hãy cắt ngắn rồi chọn lại.');
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }

    final old = _preview;
    setState(() {
      _video = picked;
      _preview = controller;
      _videoBytes = bytes;
      _videoDuration = duration;
      _pickingVideo = false;
    });
    await old?.dispose();
  }

  Future<void> _removeVideo() async {
    final old = _preview;
    setState(() {
      _video = null;
      _preview = null;
      _videoBytes = 0;
      _videoDuration = Duration.zero;
    });
    await old?.dispose();
  }

  /// Tải video lên máy chủ, trả về URL nếu thành công (null nếu lỗi / chạy offline).
  Future<String?> _uploadVideo(Object matchId, XFile video) async {
    try {
      final req = http.MultipartRequest('POST', Uri.parse('${ApiService.baseUrl}/matches/$matchId/video'))
        ..files.add(http.MultipartFile.fromBytes('file', await video.readAsBytes(), filename: video.name));
      final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 60)));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final body = jsonDecode(res.body);
      final url = body is Map ? (body['videoUrl'] ?? body['url'])?.toString() : null;
      return (url != null && url.startsWith('http')) ? url : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _submitMatch() async {
    if (_loading || _pickingVideo) return;
    final b = widget.appState.selectedBooking ?? widget.appState.bookings.first;
    String? error;
    if (b['status'] == 'CANCELLED') {
      error = 'Vé này đã hủy, không thể mở kèo.';
    } else if (_titleCtrl.text.trim().length < 5) {
      error = 'Tiêu đề cần ít nhất 5 ký tự.';
    } else if ((double.tryParse(_feeCtrl.text) ?? -1) < 0) {
      error = 'Chi phí mỗi người chưa hợp lệ.';
    }
    if (error != null) {
      _toast(error);
      return;
    }
    setState(() => _loading = true);

    final newPost = <String, dynamic>{
      'id': DateTime.now().millisecondsSinceEpoch % 10000,
      'hostId': widget.appState.userId,
      'hostName': widget.appState.fullName.split('(').first.trim(),
      'hostSkill': widget.appState.skillLevel,
      'bookingId': b['id'],
      'venueId': b['venueId'],
      'venueName': b['venueName'],
      'venueAddress': 'TP. Hồ Chí Minh',
      'courtName': b['courtName'],
      'title': _titleCtrl.text.trim(),
      'playDate': b['playDate'],
      'startTime': b['startTime'],
      'endTime': b['endTime'],
      'requiredSkill': _skill,
      'maxPlayers': _maxPlayers,
      'currentPlayers': _currentPlayers,
      'feePerPlayer': double.tryParse(_feeCtrl.text) ?? 65000,
      'status': 'OPEN',
    };

    try {
      final res = await ApiService.post('/matches', newPost);
      if (res is Map && res['id'] != null) newPost['id'] = res['id'];
    } catch (_) {}

    final video = _video;
    if (video != null) {
      final url = await _uploadVideo(newPost['id'], video);
      if (url != null) newPost['videoUrl'] = url;
      // Giữ đường dẫn trên máy để chủ kèo / bản demo offline vẫn xem được
      newPost['videoLocalPath'] = video.path;
      newPost['videoDurationSec'] = _videoDuration.inSeconds;
      newPost['videoSizeBytes'] = _videoBytes;
    }

    widget.appState.matches.insert(0, {
      'post': newPost,
      'participants': <Map<String, dynamic>>[],
    });

    if (!mounted) return;
    setState(() => _loading = false);
    widget.appState.pushNotification(
      title: 'Đã đăng kèo giao lưu',
      body: '${newPost['title']} tại ${newPost['venueName']} (${newPost['courtName']})'
          '${video != null ? ' kèm video' : ''}.',
      type: 'MATCHMAKING',
      targetScreen: 'S15',
      context: context,
    );
    widget.appState.goTo('S15');
  }

  Widget _stepper(ThemeData theme, String label, int value, int min, int max, ValueChanged<int> onChanged) {
    final cs = theme.colorScheme;
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        IconButton.outlined(
          tooltip: 'Giảm',
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.primary),
          ),
        ),
        IconButton.outlined(
          tooltip: 'Tăng',
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  Widget _videoSection(ThemeData theme) {
    final cs = theme.colorScheme;
    final preview = _preview;
    if (preview != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MatchVideoPlayer(key: ValueKey(_video?.path), controller: preview),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${MatchVideoRules.formatDuration(_videoDuration)} • ${MatchVideoRules.formatSize(_videoBytes)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              TextButton.icon(
                onPressed: _pickingVideo || _loading ? null : () => _pickVideo(ImageSource.gallery),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Đổi'),
              ),
              TextButton.icon(
                onPressed: _loading ? null : _removeVideo,
                style: TextButton.styleFrom(foregroundColor: cs.error),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Xóa'),
              ),
            ],
          ),
        ],
      );
    }

    return SurfaceCard(
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
                  'Thêm một đoạn video nhóm đang đánh để người xin vào kèo thấy trình độ thực tế. '
                  'Tối đa ${MatchVideoRules.maxSeconds} giây, ${MatchVideoRules.formatSize(MatchVideoRules.maxBytes)}.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_pickingVideo)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickVideo(ImageSource.gallery),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Chọn từ thư viện', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                if (!kIsWeb) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickVideo(ImageSource.camera),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                      icon: const Icon(Icons.videocam_outlined),
                      label: const Text('Quay video', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final b = widget.appState.selectedBooking ?? widget.appState.bookings.first;
    final missing = _maxPlayers - _currentPlayers;

    return ResponsiveCenter(
      maxWidth: Responsive.defaultFormMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context),
        children: [
          Text('Đăng kèo giao lưu',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),

          // Vé liên kết
          SurfaceCard(
            color: cs.primaryContainer.withValues(alpha: 0.4),
            borderColor: cs.primary.withValues(alpha: 0.4),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.confirmation_number_outlined, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Từ vé #${b['bookingCode']}',
                          style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                      Text(
                        '${b['venueName']}',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${b['courtName']} • ${b['startTime']} - ${b['endTime']} • ${UiDate.full(b['playDate']?.toString() ?? '')}',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _titleCtrl,
            maxLines: 2,
            maxLength: 100,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Tiêu đề',
              hintText: 'VD: Giao lưu đánh đôi tối nay, tuyển thêm 2 bạn',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _feeCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Chi phí mỗi người',
              helperText: 'Gồm tiền sân và cầu, chia đều',
              suffixText: 'đ',
              prefixIcon: Icon(Icons.payments_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader('Số người'),
          _stepper(theme, 'Đã có (gồm bạn)', _currentPlayers, 1, _maxPlayers - 1,
              (v) => setState(() => _currentPlayers = v)),
          _stepper(theme, 'Tối đa', _maxPlayers, _currentPlayers + 1, 12,
              (v) => setState(() => _maxPlayers = v)),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Cần tuyển thêm $missing người',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
          const SizedBox(height: 20),
          const SectionHeader('Trình độ yêu cầu'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in SkillLevel.codes)
                ChoiceChip(
                  label: Text(SkillLevel.label(s)),
                  selected: _skill == s,
                  onSelected: (_) => setState(() => _skill = s),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const SectionHeader('Video nhóm đánh (không bắt buộc)'),
          _videoSection(theme),
          const SizedBox(height: 24),
          PrimaryButton(
            label: _video != null ? 'Đăng kèo kèm video' : 'Đăng kèo',
            icon: Icons.send_outlined,
            loading: _loading,
            onPressed: _submitMatch,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
