import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/match_video.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S30: Chi tiết kèo giao lưu
// - Video nhóm đánh (do chủ kèo đăng ở S16) để người xem tự đánh giá có hợp trình độ không
// - So sánh trình độ yêu cầu với trình độ của bạn
// - Thông tin kèo + nút xin tham gia (cùng quy tắc với S15: không xin kèo của mình,
//   kèo đã đủ người, hoặc xin lại lần 2)
class S30MatchDetailScreen extends StatefulWidget {
  final AppState appState;
  const S30MatchDetailScreen({super.key, required this.appState});

  @override
  State<S30MatchDetailScreen> createState() => _S30MatchDetailScreenState();
}

class _S30MatchDetailScreenState extends State<S30MatchDetailScreen> {
  bool _joining = false;

  AppState get _app => widget.appState;

  Map<String, dynamic>? get _entry =>
      _app.selectedMatch ?? (_app.matches.isNotEmpty ? _app.matches.first : null);

  List<Map<String, dynamic>> _participantsOf(Map<String, dynamic> entry) {
    final raw = (entry['participants'] as List?) ?? [];
    final list =
        raw.map((p) => p is Map<String, dynamic> ? p : Map<String, dynamic>.from(p as Map)).toList();
    entry['participants'] = list;
    return list;
  }

  Future<void> _join(Map<String, dynamic> entry) async {
    final post = entry['post'] as Map<String, dynamic>;
    final isHost = '${post['hostId']}' == '${_app.userId}';
    final full = UiFmt.toNum(post['currentPlayers'], 0) >= UiFmt.toNum(post['maxPlayers'], 0);
    final parts = _participantsOf(entry);
    if (_joining || isHost || full || parts.any((p) => '${p['userId']}' == '${_app.userId}')) return;

    setState(() {
      _joining = true;
      parts.add({
        'id': DateTime.now().millisecondsSinceEpoch % 100000,
        'matchId': post['id'],
        'userId': _app.userId,
        'userName': _app.fullName.split('(').first.trim(),
        'userSkill': _app.skillLevel,
        'userPhone': _app.phone,
        'status': 'PENDING',
      });
    });
    try {
      await ApiService.post('/matches/${post['id']}/join', {'userId': _app.userId});
    } catch (_) {}
    if (!mounted) return;
    setState(() => _joining = false);
    _app.pushNotification(
      title: 'Đã gửi yêu cầu tham gia kèo',
      body: 'Chủ kèo "${post['title']}" sẽ xem trình độ (${SkillLevel.label(_app.skillLevel)}) và duyệt bạn.',
      type: 'MATCHMAKING',
      targetScreen: 'S30',
      context: context,
    );
  }

  /// So sánh trình độ: cùng mức / lệch 1 / lệch nhiều.
  (String, NoteTone, IconData) _skillFit(String? required) {
    final mine = SkillLevel.codes.indexOf(_app.skillLevel);
    final need = SkillLevel.codes.indexOf(required ?? '');
    if (mine < 0 || need < 0) return ('Chưa rõ trình độ yêu cầu.', NoteTone.info, Icons.help_outline);
    final diff = mine - need;
    if (diff == 0) {
      return ('Trình độ của bạn (${SkillLevel.label(_app.skillLevel)}) khớp với yêu cầu.',
          NoteTone.success, Icons.check_circle_outline);
    }
    if (diff.abs() == 1) {
      return (
        'Bạn ${diff > 0 ? 'cao hơn' : 'thấp hơn'} yêu cầu một bậc. Xem video để chắc chắn nhé.',
        NoteTone.info,
        Icons.info_outline
      );
    }
    return (
      'Trình độ của bạn ${diff > 0 ? 'cao hơn' : 'thấp hơn'} yêu cầu khá nhiều, có thể không phù hợp.',
      NoteTone.warning,
      Icons.warning_amber_rounded
    );
  }

  Widget _line(ThemeData theme, IconData icon, String text) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final entry = _entry;
    if (entry == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: EmptyState(icon: Icons.groups_outlined, title: 'Không tìm thấy kèo'),
      );
    }
    final post = entry['post'] as Map<String, dynamic>;
    final parts = _participantsOf(entry);
    final current = UiFmt.toNum(post['currentPlayers'], 0).toInt();
    final max = UiFmt.toNum(post['maxPlayers'], 0).toInt();
    final isHost = '${post['hostId']}' == '${_app.userId}';
    final full = current >= max;
    final myRequest = parts.where((p) => '${p['userId']}' == '${_app.userId}').firstOrNull;
    final (fitText, fitTone, fitIcon) = _skillFit(post['requiredSkill']?.toString());
    final hasVideo = MatchVideoRules.hasVideo(post);

    return Column(
      children: [
        Expanded(
          child: ResponsiveCenter(
            maxWidth: Responsive.defaultFormMaxWidth,
            child: ListView(
              padding: Responsive.screenPadding(context),
              children: [
                // Video nhóm đánh
                if (hasVideo) ...[
                  MatchVideoPlayer(key: ValueKey('video-${post['id']}'), post: post),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.videocam_outlined, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Video do chủ kèo quay, giúp bạn ước lượng trình độ của nhóm.',
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ] else
                  const EmptyState(
                    icon: Icons.videocam_off_outlined,
                    title: 'Kèo này chưa có video',
                    message: 'Bạn có thể hỏi chủ kèo về trình độ của nhóm khi xin tham gia.',
                  ),
                const SizedBox(height: 16),

                // Tiêu đề + trình độ + số người
                Text(post['title'].toString(),
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Yêu cầu: ${SkillLevel.label(post['requiredSkill']?.toString())}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: cs.onTertiaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.group_outlined, size: 18, color: full ? cs.error : cs.primary),
                    const SizedBox(width: 4),
                    Text('$current/$max người',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: full ? cs.error : cs.primary,
                        )),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: max > 0 ? (current / max).clamp(0.0, 1.0) : 0,
                    minHeight: 6,
                    backgroundColor: cs.surfaceContainerHighest,
                    color: full ? cs.error : cs.primary,
                  ),
                ),
                if (!isHost) ...[
                  const SizedBox(height: 12),
                  NoteBox(fitText, tone: fitTone, icon: fitIcon),
                ],
                const SizedBox(height: 16),

                SurfaceCard(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _line(theme, Icons.place_outlined, '${post['venueName']} • ${post['courtName']}'),
                      _line(theme, Icons.schedule,
                          '${UiDate.full(post['playDate']?.toString() ?? '')} • ${post['startTime']} - ${post['endTime']}'),
                      _line(theme, Icons.payments_outlined,
                          '${UiFmt.vnd(UiFmt.toNum(post['feePerPlayer'], 0))}/người (sân + cầu)'),
                      _line(theme, Icons.person_outline,
                          'Chủ kèo: ${post['hostName']} (${SkillLevel.label(post['hostSkill']?.toString())})'),
                    ],
                  ),
                ),
                if (isHost && parts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  NoteBox('Có ${parts.length} yêu cầu tham gia. Duyệt thành viên ở bảng tin Tìm kèo.',
                      icon: Icons.how_to_reg_outlined),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        if (!isHost)
          BottomActionBar(
            summary: Text(
              myRequest != null
                  ? (myRequest['status'] == 'APPROVED' ? 'Bạn đã được duyệt' : 'Đang chờ chủ kèo duyệt')
                  : full
                      ? 'Kèo đã đủ người'
                      : '${UiFmt.vnd(UiFmt.toNum(post['feePerPlayer'], 0))}/người',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            action: FilledButton.icon(
              onPressed: (myRequest != null || full || _joining) ? null : () => _join(entry),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: Icon(myRequest != null ? Icons.hourglass_top_rounded : Icons.sports_tennis),
              label: Text(myRequest != null ? 'Đã gửi yêu cầu' : 'Xin tham gia'),
            ),
          ),
      ],
    );
  }
}
