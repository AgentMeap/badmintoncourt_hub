import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/match_video.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S15: Matchmaking Community Social Feed & Host Approval Screen (Luồng 5)
// Giao diện theo design system + sửa logic:
// - Chỉ CHỦ KÈO thấy nút duyệt thành viên
// - Không xin vào kèo của chính mình, kèo đã đủ người, hoặc xin lại lần 2
// - Xin tham gia sẽ thêm bạn vào danh sách chờ duyệt của kèo
// - Bấm vào thẻ kèo để mở S30 (chi tiết + video nhóm đánh)
class S15MatchmakingFeedScreen extends StatefulWidget {
  final AppState appState;
  const S15MatchmakingFeedScreen({super.key, required this.appState});

  @override
  State<S15MatchmakingFeedScreen> createState() => _S15MatchmakingFeedScreenState();
}

class _S15MatchmakingFeedScreenState extends State<S15MatchmakingFeedScreen> {
  String _selectedSkill = 'ALL';

  AppState get _app => widget.appState;

  List<Map<String, dynamic>> _participantsOf(Map<String, dynamic> entry) {
    final raw = (entry['participants'] as List?) ?? [];
    // Đảm bảo danh sách có kiểu đúng và là cùng một list để cập nhật tại chỗ
    final list = raw.map((p) => p is Map<String, dynamic> ? p : Map<String, dynamic>.from(p as Map)).toList();
    entry['participants'] = list;
    return list;
  }

  bool _isHost(Map<String, dynamic> post) => '${post['hostId']}' == '${_app.userId}';

  bool _hasRequested(Map<String, dynamic> entry) =>
      _participantsOf(entry).any((p) => '${p['userId']}' == '${_app.userId}');

  bool _isFull(Map<String, dynamic> post) =>
      UiFmt.toNum(post['currentPlayers'], 0) >= UiFmt.toNum(post['maxPlayers'], 0);

  Future<void> _joinMatch(Map<String, dynamic> entry) async {
    final post = entry['post'] as Map<String, dynamic>;
    if (_isHost(post) || _isFull(post) || _hasRequested(entry)) return;

    setState(() {
      _participantsOf(entry).add({
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
    _app.pushNotification(
      title: 'Đã gửi yêu cầu tham gia kèo',
      body: 'Chủ kèo "${post['title']}" sẽ xem trình độ (${SkillLevel.label(_app.skillLevel)}) và duyệt bạn.',
      type: 'MATCHMAKING',
      targetScreen: 'S15',
      context: context,
    );
  }

  Future<void> _approveParticipant(Map<String, dynamic> entry, Map<String, dynamic> part) async {
    final post = entry['post'] as Map<String, dynamic>;
    if (!_isHost(post) || part['status'] != 'PENDING') return;
    if (_isFull(post)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kèo đã đủ người, không thể duyệt thêm.')),
      );
      return;
    }
    setState(() {
      part['status'] = 'APPROVED';
      post['currentPlayers'] = UiFmt.toNum(post['currentPlayers'], 0).toInt() + 1;
    });
    try {
      await ApiService.patch('/matches/${post['id']}/participants/${part['id']}', {
        'status': 'APPROVED',
      });
    } catch (_) {}

    if (!mounted) return;
    _app.pushNotification(
      title: 'Đã duyệt ${part['userName']} vào kèo',
      body: 'Hiện có ${post['currentPlayers']}/${post['maxPlayers']} người.',
      type: 'MATCHMAKING',
      targetScreen: 'S15',
      context: context,
    );
  }

  Widget _matchCard(BuildContext context, Map<String, dynamic> entry) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final post = entry['post'] as Map<String, dynamic>;
    final participants = _participantsOf(entry);
    final current = UiFmt.toNum(post['currentPlayers'], 0).toInt();
    final max = UiFmt.toNum(post['maxPlayers'], 0).toInt();
    final isHost = _isHost(post);
    final full = _isFull(post);
    final requested = _hasRequested(entry);
    final myRequest = participants.where((p) => '${p['userId']}' == '${_app.userId}').firstOrNull;

    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      onTap: () {
        _app.selectedMatch = entry;
        _app.goTo('S30');
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bar_chart_rounded, size: 14, color: cs.onTertiaryContainer),
                          const SizedBox(width: 4),
                          Text(
                            SkillLevel.label(post['requiredSkill']?.toString()),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: cs.onTertiaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (MatchVideoRules.hasVideo(post))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_circle_outline, size: 14, color: cs.onPrimaryContainer),
                            const SizedBox(width: 4),
                            Text(
                              'Có video',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: cs.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (isHost)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Kèo của bạn',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSecondaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.group_outlined, size: 18, color: full ? cs.error : cs.primary),
                  const SizedBox(width: 4),
                  Text(
                    '$current/$max',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: full ? cs.error : cs.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Thanh số người
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: max > 0 ? (current / max).clamp(0.0, 1.0) : 0,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
              color: full ? cs.error : cs.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            post['title'].toString(),
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          _line(theme, Icons.place_outlined, '${post['venueName']} • ${post['courtName']}'),
          _line(theme, Icons.schedule,
              '${UiDate.full(post['playDate']?.toString() ?? '')} • ${post['startTime']} - ${post['endTime']}'),
          _line(theme, Icons.payments_outlined,
              '${UiFmt.vnd(UiFmt.toNum(post['feePerPlayer'], 0))}/người (sân + cầu)'),
          _line(theme, Icons.person_outline, 'Chủ kèo: ${post['hostName']}'),

          // Danh sách xin tham gia: chủ kèo thấy đầy đủ để duyệt
          if (isHost && participants.isNotEmpty) ...[
            Divider(height: 20, color: cs.outlineVariant),
            Text('Yêu cầu tham gia (${participants.length})',
                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final p in participants)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: cs.secondaryContainer,
                      child: Text(
                        _initial(p['userName']?.toString()),
                        style: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p['userName']?.toString() ?? '',
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          Text('Trình độ: ${SkillLevel.label(p['userSkill']?.toString())}',
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    if (p['status'] == 'PENDING')
                      FilledButton.tonal(
                        onPressed: full ? null : () => _approveParticipant(entry, p),
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                        child: const Text('Duyệt'),
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, size: 18, color: cs.primary),
                          const SizedBox(width: 4),
                          Text('Đã duyệt',
                              style: theme.textTheme.labelMedium
                                  ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
                        ],
                      ),
                  ],
                ),
              ),
          ],

          if (!isHost) ...[
            const SizedBox(height: 12),
            if (myRequest != null)
              NoteBox(
                myRequest['status'] == 'APPROVED'
                    ? 'Bạn đã được duyệt vào kèo này.'
                    : 'Đã gửi yêu cầu, đang chờ chủ kèo duyệt.',
                tone: myRequest['status'] == 'APPROVED' ? NoteTone.success : NoteTone.info,
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: (full || requested) ? null : () => _joinMatch(entry),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  icon: Icon(full ? Icons.block : Icons.sports_tennis),
                  label: Text(full ? 'Kèo đã đủ người' : 'Xin tham gia'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _initial(String? name) {
    final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    if (parts.isEmpty) return '?';
    return String.fromCharCode(parts.last.runes.first).toUpperCase();
  }

  Widget _line(ThemeData theme, IconData icon, String text) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _app.matches.where((m) {
      if (_selectedSkill == 'ALL') return true;
      final p = m['post'] as Map<String, dynamic>;
      return p['requiredSkill'] == _selectedSkill;
    }).toList();

    return ResponsiveCenter(
      maxWidth: Responsive.defaultContentMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Tìm kèo giao lưu',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              FilledButton.icon(
                onPressed: () => _app.goTo('S16'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Đăng kèo'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in ['ALL', ...SkillLevel.codes])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s == 'ALL' ? 'Tất cả' : SkillLevel.label(s)),
                      selected: _selectedSkill == s,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _selectedSkill = s),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            EmptyState(
              icon: Icons.groups_outlined,
              title: 'Chưa có kèo phù hợp',
              message: 'Thử trình độ khác hoặc tự mở một kèo mới.',
              action: FilledButton.icon(
                onPressed: () => _app.goTo('S16'),
                icon: const Icon(Icons.add),
                label: const Text('Đăng kèo'),
              ),
            )
          else
            ...items.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _matchCard(context, e),
                )),
        ],
      ),
    );
  }
}
