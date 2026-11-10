import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/directions.dart';
import 'package:badminton_v2_mobile/core/match_deposit.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';
import 'package:badminton_v2_mobile/core/video_link.dart';
import 'package:badminton_v2_mobile/screens/customer/host_reputation.dart';
import 'package:badminton_v2_mobile/screens/customer/match_chat_sheet.dart';

// S30: Chi tiết kèo giao lưu
// - Luôn tải bản mới nhất của kèo từ máy chủ (GET /matches/{id}); mở từ thông báo cũng vào đúng kèo.
// - Video nhóm đánh + video giới thiệu của chủ kèo, thước đo độ phù hợp trình độ.
// - CHỦ KÈO: mục "Đơn xin tham gia" để xem video trình độ, Duyệt / Từ chối (kèm lý do),
//   mục "Thành viên" (đã duyệt / số chỗ, có thể mời ra). Mở từ thông báo "Có người xin tham gia" thì tự cuộn tới đây.
// - NGƯỜI XIN: trạng thái đơn (chờ duyệt / đã duyệt / bị từ chối / bị mời ra + lý do), hủy đơn hoặc rời kèo,
//   đồng đội, dẫn đường tới sân.
// - Chủ kèo + thành viên đã duyệt: nhóm chat của kèo. Chủ kèo có thể hủy cả kèo (báo cho mọi người).
// - Uy tín chủ kèo: điểm + huy hiệu (bấm để xem hồ sơ); kèo kết thúc thì thành viên đã duyệt đánh giá chủ kèo
//   (mở từ thông báo "Đánh giá chủ kèo" thì tự bật bảng đánh giá).
// - Thành viên đã duyệt tự rời kèo (hoàn cọc theo mốc 24h / 2h lúc rời); chủ kèo mời ra thì chọn hoàn đủ / theo chính sách.
// - Nhóm chat có số tin chưa đọc; mở từ thông báo tin nhắn thì tự mở khung chat.
// - Kèo có cọc: xác nhận số cọc trước khi xin, hộp thoại rời kèo hiện số tiền được hoàn, dòng trạng thái cọc.
// - Kèo đã hủy / đã kết thúc: hiện thông báo ở đầu, ẩn các nút thao tác (vẫn xem lại được nhóm chat).
class S30MatchDetailScreen extends StatefulWidget {
  final AppState appState;
  const S30MatchDetailScreen({super.key, required this.appState});

  @override
  State<S30MatchDetailScreen> createState() => _S30MatchDetailScreenState();
}

class _S30MatchDetailScreenState extends State<S30MatchDetailScreen> {
  final _requestsKey = GlobalKey();
  Json? _entry;
  Object? _matchId;
  bool _loading = false;
  bool _gone = false;
  bool _joining = false;
  bool _focusRequests = false;
  bool _openReview = false;
  bool _openChat = false;
  /// Kèo đã hủy / đã kết thúc (tính lại mỗi lần build) -> ẩn nút duyệt, mời ra, rời kèo.
  bool _closed = false;
  final Set<String> _busy = {};

  AppState get _app => widget.appState;

  @override
  void initState() {
    super.initState();
    _entry = _app.selectedMatch ?? (_app.openMatchId == null && _app.matches.isNotEmpty ? _app.matches.first : null);
    _matchId = _app.openMatchId ?? (_entry?['post'] is Map ? (_entry!['post'] as Map)['id'] : null);
    _focusRequests = _app.openMatchFocusRequests;
    _openReview = _app.openMatchReview;
    _app.openMatchReview = false;
    _openChat = _app.openMatchChat;
    _app.openMatchChat = false;
    _loading = _matchId != null;
    _app.openMatchId = null;
    _app.openMatchFocusRequests = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  /// Tải bản mới nhất của kèo (người xin mới, trạng thái duyệt...).
  Future<void> _refresh() async {
    final id = _matchId;
    if (id == null) return;
    setState(() => _loading = true);
    try {
      final fresh = await Repos.match.detail(id);
      if (!mounted) return;
      setState(() {
        _apply(fresh);
        _gone = false;
        _loading = false;
      });
      if (_openChat) {
        _openChat = false;
        if (fresh['canChat'] == true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openChatSheet();
          });
        }
      }
      if (_openReview) {
        _openReview = false;
        if (fresh['canReviewHost'] == true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _reviewHost();
          });
        }
      }
      if (_focusRequests) {
        _focusRequests = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _requestsKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), alignment: 0.1);
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e is ApiException && e.statusCode == 404) _gone = true;
      });
      // Mất mạng: vẫn hiện dữ liệu đang có trên máy
      if (!_gone) showApiError(context, e);
    }
  }

  /// Mở bảng đánh giá chủ kèo (tạo mới hoặc sửa).
  Future<void> _reviewHost() async {
    final entry = _entry;
    if (entry == null) return;
    final post = asJson(entry['post']);
    final updated = await HostReputation.showReviewSheet(
      context,
      matchId: post['id'],
      hostName: post['hostName']?.toString() ?? 'Chủ kèo',
      existing: entry['myHostReview'] is Map ? entry['myHostReview'] as Map : null,
    );
    if (updated == null || !mounted) return;
    setState(() => _apply(updated));
    _snack('Đã gửi đánh giá. Cảm ơn bạn!');
  }

  /// Ghi kèo mới vào màn hình và danh sách kèo của app (để S15 cũng thấy ngay).
  void _apply(Json fresh) {
    if (fresh.isEmpty) return;
    _entry = fresh;
    _app.selectedMatch = fresh;
    final id = '${(fresh['post'] as Map?)?['id']}';
    final idx = _app.matches.indexWhere((m) => '${(m['post'] as Map?)?['id']}' == id);
    if (idx >= 0) _app.matches[idx] = fresh;
  }

  List<Json> _participantsOf(Json entry) {
    final list = asJsonList(entry['participants']);
    entry['participants'] = list;
    return list;
  }

  Future<void> _join(Json entry) async {
    final post = asJson(entry['post']);
    final isHost = '${post['hostId']}' == '${_app.userId}';
    final full = UiFmt.toNum(post['currentPlayers'], 0) >= UiFmt.toNum(post['maxPlayers'], 0);
    final parts = _participantsOf(entry);
    if (_joining || isHost || full || parts.any((p) => '${p['userId']}' == '${_app.userId}')) return;
    // Kèo có cọc: xác nhận số tiền trước (ví không đủ thì đưa đi nạp)
    if (!await MatchDeposit.confirmJoin(context, _app, post) || !mounted) return;

    setState(() => _joining = true);
    try {
      await Repos.match.join(post['id'], _app.userId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _joining = false);
      if (!MatchDeposit.handleJoinError(context, _app, e)) showApiError(context, e);
      return;
    }
    if (!mounted) return;
    setState(() => _joining = false);
    final deposit = MatchDeposit.amountOf(post);
    if (deposit > 0) _app.refreshWallet();
    _app.pushNotification(
      title: 'Đã gửi yêu cầu tham gia kèo',
      body: 'Chủ kèo "${post['title']}" sẽ xem trình độ (${SkillLevel.label(_app.skillLevel)}) và duyệt bạn.'
          '${deposit > 0 ? ' Đã cọc ${UiFmt.vnd(deposit)} qua ví.' : ''}',
      type: 'MATCHMAKING',
      targetScreen: 'S30',
      context: context,
    );
    await _refresh();
  }

  /// Chủ kèo duyệt / từ chối một đơn.
  Future<void> _review(Json post, Json part, bool approve) async {
    final key = '${part['id']}';
    if (_busy.contains(key)) return;
    String? reason;
    if (approve) {
      final ok = await confirmAction(
        context,
        title: 'Duyệt ${part['userName']}?',
        message: 'Trình độ: ${SkillLevel.label(part['userSkill']?.toString())}. '
            'Người này sẽ nhận thông báo đã được vào kèo.',
        confirmLabel: 'Duyệt',
      );
      if (!ok) return;
    } else {
      final result = await _askReason(title: 'Từ chối ${part['userName']}?', confirmLabel: 'Từ chối');
      if (result == null) return;
      reason = result;
    }
    if (!mounted) return;
    setState(() => _busy.add(key));
    try {
      final res = await Repos.match.reviewParticipant(post['id'], part['id'], approve ? 'APPROVED' : 'REJECTED',
          reason: reason);
      if (!mounted) return;
      setState(() {
        _busy.remove(key);
        _apply(asJson(res['entry']));
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(approve ? 'Đã duyệt ${part['userName']} vào kèo' : 'Đã từ chối ${part['userName']}'),
        ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(key));
      showApiError(context, e);
      _refresh(); // 409: đơn đã được xử lý ở nơi khác -> tải lại trạng thái thật
    }
  }

  /// Hộp thoại chọn cách hoàn cọc khi mời thành viên ra: trả về 'FULL' / 'POLICY', null nếu huỷ.
  Future<String?> _askRefundMode(Json post, Json part, {required String title, required String defaultMode,
      required String confirmLabel}) async {
    Json preview;
    try {
      preview = await Repos.match.removePreview(post['id'], part['id']);
    } catch (e) {
      if (mounted) showApiError(context, e);
      return null;
    }
    if (!mounted) return null;
    final deposit = UiFmt.toNum(preview['deposit'], 0);
    if (deposit <= 0) {
      // Kèo không cọc: chỉ cần xác nhận
      final ok = await confirmAction(context,
          title: title, message: 'Chỗ của ${part['userName']} sẽ được trả lại cho kèo.', confirmLabel: confirmLabel);
      return ok ? defaultMode : null;
    }
    final full = UiFmt.toNum(preview['fullRefund'], 0);
    final policy = UiFmt.toNum(preview['policyRefund'], 0);
    var mode = defaultMode;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${part['userName']} đã cọc ${UiFmt.vnd(deposit)}. Chọn cách hoàn cọc:'),
              const SizedBox(height: 8),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: 'POLICY',
                groupValue: mode,
                onChanged: (v) => setLocal(() => mode = v!),
                title: Text('Theo chính sách: hoàn ${UiFmt.vnd(policy)}'),
                subtitle: Text(
                    'Tính theo thời gian còn lại tới giờ đánh${deposit - policy > 0 ? ', bạn nhận ${UiFmt.vnd(deposit - policy)}' : ''}'),
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: 'FULL',
                groupValue: mode,
                onChanged: (v) => setLocal(() => mode = v!),
                title: Text('Hoàn đủ ${UiFmt.vnd(full)}'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(ctx, mode), child: Text(confirmLabel)),
          ],
        ),
      ),
    );
  }

  /// Chủ kèo mời một thành viên đã duyệt ra khỏi kèo (người đó không xin lại được kèo này).
  Future<void> _remove(Json post, Json part) async {
    final key = '${part['id']}';
    if (_busy.contains(key)) return;
    final reason = await _askReason(
      title: 'Mời ${part['userName']} ra khỏi kèo?',
      confirmLabel: 'Tiếp tục',
      hint: 'VD: Đổi đội hình',
    );
    if (reason == null || !mounted) return;
    final mode = await _askRefundMode(post, part,
        title: 'Mời ${part['userName']} ra', defaultMode: 'FULL', confirmLabel: 'Mời ra');
    if (mode == null || !mounted) return;
    setState(() => _busy.add(key));
    try {
      final res = await Repos.match.removeParticipant(post['id'], part['id'], reason: reason, refundMode: mode);
      if (!mounted) return;
      setState(() {
        _busy.remove(key);
        _apply(asJson(res['entry']));
      });
      _snack('Đã mời ${part['userName']} ra khỏi kèo');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(key));
      showApiError(context, e);
      _refresh();
    }
  }

  /// Người xin hủy đơn đang chờ duyệt (hoàn đủ cọc).
  Future<void> _cancelPending(Json post) async {
    final ok = await MatchDeposit.confirmLeave(context, post, approved: false);
    if (!ok || !mounted) return;
    setState(() => _joining = true);
    try {
      final res = await Repos.match.leave(post['id']);
      if (!mounted) return;
      setState(() {
        _joining = false;
        _apply(asJson(res['entry']));
      });
      final refunded = UiFmt.toNum(res['refundedAmount'], 0);
      if (MatchDeposit.amountOf(post) > 0) _app.refreshWallet();
      _snack('Đã hủy đơn xin tham gia${refunded > 0 ? '. Đã hoàn ${UiFmt.vnd(refunded)} vào ví' : ''}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _joining = false);
      showApiError(context, e);
      _refresh();
    }
  }

  /// Thành viên đã duyệt tự rời kèo ngay (hộp thoại hiện số tiền được hoàn lấy từ máy chủ).
  Future<void> _leaveNow(Json post) async {
    final ok = await MatchDeposit.confirmLeave(context, post, approved: true);
    if (!ok || !mounted) return;
    setState(() => _joining = true);
    try {
      final res = await Repos.match.leave(post['id']);
      if (!mounted) return;
      setState(() {
        _joining = false;
        _apply(asJson(res['entry']));
      });
      final refunded = UiFmt.toNum(res['refundedAmount'], 0);
      if (MatchDeposit.amountOf(post) > 0) _app.refreshWallet();
      _snack('Bạn đã rời kèo${refunded > 0 ? '. Đã hoàn ${UiFmt.vnd(refunded)} vào ví' : ''}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _joining = false);
      showApiError(context, e);
      _refresh();
    }
  }

  /// Mở nhóm chat; đóng lại thì tải lại kèo để cập nhật số tin chưa đọc.
  Future<void> _openChatSheet() async {
    final entry = _entry;
    if (entry == null) return;
    final post = asJson(entry['post']);
    await showMatchChatSheet(context, matchId: post['id'], title: post['title']?.toString() ?? 'Kèo giao lưu');
    if (mounted) _refresh();
  }

  /// Chủ kèo hủy cả kèo (lý do không bắt buộc), mọi người đã xin / đã vào nhận thông báo.
  Future<void> _cancelMatch(Json post) async {
    final entry = _entry;
    final pendingOrIn = (entry == null ? <Json>[] : _participantsOf(entry))
        .where((p) => p['status'] == 'PENDING' || p['status'] == 'APPROVED')
        .length;
    final reason = await _askReason(
      title: 'Hủy kèo "${post['title']}"?',
      confirmLabel: 'Hủy kèo',
      hint: pendingOrIn > 0 ? 'Lý do gửi cho $pendingOrIn người (VD: Sân bảo trì)' : 'VD: Sân bảo trì',
    );
    if (reason == null || !mounted) return;
    setState(() => _joining = true);
    try {
      final res = await Repos.match.cancel(post['id'], reason: reason);
      if (!mounted) return;
      setState(() {
        _joining = false;
        _apply(asJson(res['entry']));
      });
      _snack('Đã hủy kèo');
    } catch (e) {
      if (!mounted) return;
      setState(() => _joining = false);
      showApiError(context, e);
      _refresh();
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)));
  }

  /// Hộp thoại xin lý do (không bắt buộc). Trả về null nếu huỷ, '' nếu không nhập lý do.
  Future<String?> _askReason({
    required String title,
    required String confirmLabel,
    String hint = 'VD: Kèo cần trình độ khá hơn',
    String note = 'Lý do sẽ được gửi kèm thông báo (không bắt buộc).',
    bool destructive = true,
  }) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(note),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLength: 200,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  /// "2026-11-09T14:05:00" -> "gửi 14:05 09/11"
  static String? _sentAt(dynamic raw) {
    final t = DateTime.tryParse('${raw ?? ''}');
    if (t == null) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    return 'gửi ${two(t.hour)}:${two(t.minute)} ${two(t.day)}/${two(t.month)}';
  }

  static String _initial(String? name) {
    final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    if (parts.isEmpty) return '?';
    return String.fromCharCode(parts.last.runes.first).toUpperCase();
  }

  /// Một dòng người tham gia: ảnh chữ cái, tên, trình độ, video; [trailing] là nút / trạng thái.
  Widget _personTile(ThemeData theme, Json p, {Widget? trailing, bool highlight = false, String? extra}) {
    final cs = theme.colorScheme;
    final hasVideo = VideoLink.tryParse(p['userVideoUrl']?.toString()) != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: highlight ? cs.primaryContainer.withValues(alpha: 0.35) : cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight ? cs.primary.withValues(alpha: 0.5) : cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: cs.secondaryContainer,
                child: Text(_initial(p['userName']?.toString()),
                    style: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${p['userName'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      [
                        'Trình độ: ${SkillLevel.label(p['userSkill']?.toString())}',
                        if (p['userPhone'] != null) '${p['userPhone']}',
                        if (extra != null) extra,
                      ].join(' • '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (hasVideo)
                IconButton(
                  tooltip: 'Xem video trình độ của ${p['userName']}',
                  onPressed: () => showVideoSheet(
                    context,
                    title: 'Video của ${p['userName']}',
                    subtitle: 'Trình độ tự đánh giá: ${SkillLevel.label(p['userSkill']?.toString())}',
                    url: p['userVideoUrl'].toString(),
                  ),
                  icon: Icon(Icons.play_circle_outline, color: cs.primary),
                ),
            ],
          ),
          if (trailing != null) ...[const SizedBox(height: 8), trailing],
        ],
      ),
    );
  }

  /// Phần dành cho chủ kèo: đơn chờ duyệt, thành viên, đơn đã từ chối.
  List<Widget> _hostSection(ThemeData theme, Json post, List<Json> parts, bool full) {
    final cs = theme.colorScheme;
    final pending = parts.where((p) => p['status'] == 'PENDING').toList();
    final approved = parts.where((p) => p['status'] == 'APPROVED').toList();
    final rejected = parts.where((p) => p['status'] == 'REJECTED' || p['status'] == 'REMOVED').toList();
    final current = UiFmt.toNum(post['currentPlayers'], 0).toInt();
    final max = UiFmt.toNum(post['maxPlayers'], 0).toInt();
    final newest = pending.isEmpty ? null : pending.last;

    return [
      const SizedBox(height: 20),
      KeyedSubtree(
        key: _requestsKey,
        child: SectionHeader(
          'Đơn xin tham gia (${pending.length})',
          trailing: _loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
        ),
      ),
      if (full && pending.isNotEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: NoteBox('Kèo đã đủ người. Bạn chỉ có thể từ chối các đơn còn lại.', tone: NoteTone.warning),
        ),
      if (pending.isEmpty)
        const NoteBox('Chưa có đơn mới. Khi có người xin tham gia, bạn sẽ nhận thông báo.', icon: Icons.inbox_outlined)
      else
        for (final p in pending)
          _personTile(
            theme,
            p,
            highlight: identical(p, newest),
            extra: _sentAt(p['joinedAt']),
            trailing: _closed ? null : Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy.contains('${p['id']}') ? null : () => _review(post, p, false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      foregroundColor: cs.error,
                      side: BorderSide(color: cs.error.withValues(alpha: 0.6)),
                    ),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Từ chối'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (full || _busy.contains('${p['id']}')) ? null : () => _review(post, p, true),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    icon: _busy.contains('${p['id']}')
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check, size: 18),
                    label: const Text('Duyệt'),
                  ),
                ),
              ],
            ),
          ),
      const SizedBox(height: 12),
      SectionHeader('Thành viên ($current/$max)'),
      if (UiFmt.toNum(_entry?['depositHeldTotal'], 0) > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: NoteBox(
            'Đang giữ hộ ${UiFmt.vnd(UiFmt.toNum(_entry?['depositHeldTotal'], 0))} tiền cọc của thành viên đã duyệt. '
            'Tiền vào ví của bạn sau khi kèo kết thúc.',
            icon: Icons.account_balance_wallet_outlined,
            tone: NoteTone.success,
          ),
        ),
      if (approved.isEmpty)
        Text('Chưa duyệt ai. Số người hiện tại gồm cả bạn và người bạn tự thêm khi đăng kèo.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))
      else
        for (final p in approved)
            _personTile(theme, p,
                trailing: Row(children: [
                  Icon(Icons.check_circle, size: 18, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Đã duyệt', style: theme.textTheme.labelLarge?.copyWith(color: cs.primary))),
                  if (!_closed)
                    TextButton.icon(
                      onPressed: _busy.contains('${p['id']}') ? null : () => _remove(post, p),
                      style: TextButton.styleFrom(foregroundColor: cs.error, minimumSize: const Size(0, 40)),
                      icon: const Icon(Icons.person_remove_outlined, size: 18),
                      label: const Text('Mời ra'),
                    ),
                ])),
      if (rejected.isNotEmpty)
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Đã từ chối / mời ra (${rejected.length})',
                style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
            children: [
              for (final p in rejected)
                _personTile(theme, p,
                    extra: [
                      p['status'] == 'REMOVED' ? 'Đã mời ra' : 'Đã từ chối',
                      if (p['rejectReason'] != null) 'Lý do: ${p['rejectReason']}',
                    ].join(' • ')),
            ],
          ),
        ),
    ];
  }

  /// Phần dành cho người đã xin tham gia: trạng thái đơn, đồng đội, dẫn đường.
  List<Widget> _memberSection(ThemeData theme, Json post, List<Json> parts, Json myRequest) {
    final status = myRequest['status'];
    final teammates = parts.where((p) => p['status'] == 'APPROVED').toList();
    Json? venue;
    for (final v in _app.venues) {
      if ('${v['id']}' == '${post['venueId']}') venue = v;
    }
    final depositLine = MatchDeposit.myDepositLine(myRequest);
    return [
      const SizedBox(height: 16),
      if (depositLine != null) ...[
        NoteBox(depositLine, icon: Icons.account_balance_wallet_outlined),
        const SizedBox(height: 8),
      ],
      if (status == 'APPROVED') ...[
        if (!_closed)
          const NoteBox('Bạn đã được duyệt vào kèo. Hẹn gặp ở sân!', tone: NoteTone.success, icon: Icons.celebration_outlined),
        if (venue != null && !_closed) ...[
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: () => showDirectionsSheet(context, venue!),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.navigation_outlined),
            label: const Text('Dẫn đường tới sân'),
          ),
        ],
        const SizedBox(height: 16),
        SectionHeader('Đồng đội (${teammates.length})'),
        for (final p in teammates) _personTile(theme, p),
        if (!_closed) ...[
          const SizedBox(height: 8),
          Text('Không đi được? Bạn có thể rời kèo, tiền cọc hoàn theo thời gian còn lại tới giờ đánh.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _joining ? null : () => _leaveNow(post),
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Rời kèo'),
            ),
          ),
        ],
      ] else if (status == 'REJECTED' || status == 'REMOVED') ...[
        NoteBox(
          '${status == 'REMOVED' ? 'Chủ kèo đã mời bạn ra khỏi kèo này.' : 'Chủ kèo chưa nhận bạn vào kèo này.'}'
          '${myRequest['rejectReason'] != null ? '\nLý do: ${myRequest['rejectReason']}' : ''}',
          tone: NoteTone.warning,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {
            _app.matchTab = 0;
            _app.goTo('S15');
          },
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          icon: const Icon(Icons.search),
          label: const Text('Tìm kèo khác hợp trình độ'),
        ),
      ] else ...[
        const NoteBox('Đã gửi yêu cầu, đang chờ chủ kèo duyệt. Bạn sẽ nhận thông báo khi có kết quả.',
            icon: Icons.hourglass_top_rounded),
        if (!_closed) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _joining ? null : () => _cancelPending(post),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          icon: const Icon(Icons.undo, size: 18),
          label: const Text('Hủy đơn'),
        ),
        ],
      ],
    ];
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

  Widget _buildSkillMeter(ThemeData theme, ColorScheme cs, String? requiredSkill) {
    final mineIdx = SkillLevel.codes.indexOf(_app.skillLevel);
    final reqIdx = SkillLevel.codes.indexOf(requiredSkill ?? '');
    final (fitText, fitTone, fitIcon) = _skillFit(requiredSkill);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed_rounded, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Thước đo độ phù hợp trình độ',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(SkillLevel.codes.length, (idx) {
              final code = SkillLevel.codes[idx];
              final isMySkill = idx == mineIdx;
              final isReqSkill = idx == reqIdx;
              final isBoth = isMySkill && isReqSkill;

              Color stepColor = cs.surfaceContainerHighest;
              if (isBoth) {
                stepColor = cs.primary;
              } else if (isMySkill) {
                stepColor = cs.secondary;
              } else if (isReqSkill) {
                stepColor = cs.tertiary;
              }

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: idx < SkillLevel.codes.length - 1 ? 4 : 0),
                  child: Column(
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: stepColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        SkillLevel.label(code),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: (isMySkill || isReqSkill) ? FontWeight.bold : FontWeight.normal,
                          color: (isMySkill || isReqSkill) ? cs.onSurface : cs.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (isBoth)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Khớp 100%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onPrimary,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else if (isMySkill)
                        Text(
                          'Bạn',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.secondary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      else if (isReqSkill)
                        Text(
                          'Yêu cầu',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.tertiary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      else
                        const SizedBox(height: 14),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          NoteBox(fitText, tone: fitTone, icon: fitIcon),
        ],
      ),
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
    if (_gone) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: EmptyState(
          icon: Icons.event_busy_outlined,
          title: 'Kèo này đã kết thúc hoặc bị xoá',
          message: 'Bạn có thể tìm kèo khác đang mở.',
          action: FilledButton.icon(
            onPressed: () {
              _app.matchTab = 0;
              _app.goTo('S15');
            },
            icon: const Icon(Icons.search),
            label: const Text('Tìm kèo khác'),
          ),
        ),
      );
    }
    if (entry == null || entry['post'] is! Map) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : const EmptyState(icon: Icons.groups_outlined, title: 'Không tìm thấy kèo'),
      );
    }
    final post = asJson(entry['post']);
    final parts = _participantsOf(entry);
    final current = UiFmt.toNum(post['currentPlayers'], 0).toInt();
    final max = UiFmt.toNum(post['maxPlayers'], 0).toInt();
    final isHost = '${post['hostId']}' == '${_app.userId}';
    final full = current >= max;
    final myRequest = parts.where((p) => '${p['userId']}' == '${_app.userId}').firstOrNull;
    final videoUrl = post['videoUrl']?.toString();
    final hasVideo = VideoLink.tryParse(videoUrl) != null;
    final hostVideoUrl = post['hostVideoUrl']?.toString();
    final hasHostVideo = VideoLink.tryParse(hostVideoUrl) != null;
    final myStatus = myRequest?['status'];
    final status = post['status']?.toString();
    _closed = status == 'CANCELLED' || status == 'COMPLETED';
    final canChat = entry['canChat'] == true || isHost || myStatus == 'APPROVED';
    final messageCount = UiFmt.toNum(entry['messageCount'], 0).toInt();
    final unread = UiFmt.toNum(entry['unreadMessages'], 0).toInt();

    return Column(
      children: [
        Expanded(
          child: ResponsiveCenter(
            maxWidth: Responsive.defaultFormMaxWidth,
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: Responsive.screenPadding(context),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_closed) ...[
                    NoteBox(
                      status == 'CANCELLED'
                          ? 'Kèo này đã bị chủ kèo hủy.'
                          : 'Kèo này đã kết thúc. Cảm ơn bạn đã tham gia!',
                      tone: status == 'CANCELLED' ? NoteTone.error : NoteTone.info,
                      icon: status == 'CANCELLED' ? Icons.event_busy_outlined : Icons.flag_outlined,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (hasVideo) ...[
                    VideoLinkPlayer(key: ValueKey('video-${post['id']}'), url: videoUrl),
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
                  ] else if (!isHost)
                    const EmptyState(
                      icon: Icons.videocam_off_outlined,
                      title: 'Kèo này chưa có video',
                      message: 'Bạn có thể hỏi chủ kèo về trình độ của nhóm khi xin tham gia.',
                    ),
                  const SizedBox(height: 16),

                  Text(post['title'].toString(),
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.group_outlined, size: 18, color: full ? cs.error : cs.primary),
                          const SizedBox(width: 4),
                          Text('$current/$max người',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: full ? cs.error : cs.primary,
                              )),
                        ],
                      ),
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
                    _buildSkillMeter(theme, cs, post['requiredSkill']?.toString()),
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
                        if (MatchDeposit.label(post) != null)
                          _line(theme, Icons.account_balance_wallet_outlined,
                              '${MatchDeposit.label(post)} qua ví khi xin vào, phần còn lại trả tại sân'),
                        _line(theme, Icons.person_outline,
                            'Chủ kèo: ${isHost ? 'Bạn' : post['hostName']} (${SkillLevel.label(post['hostSkill']?.toString())})'),
                        Padding(
                          padding: const EdgeInsets.only(left: 22),
                          child: HostReputation.summaryRow(
                            theme,
                            entry['host'] is Map ? entry['host'] as Map : null,
                            onTap: () => HostReputation.showProfileSheet(context,
                                hostId: post['hostId'], hostName: post['hostName']?.toString() ?? 'Chủ kèo'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (canChat) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _openChatSheet,
                      style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                      icon: Badge(
                        isLabelVisible: unread > 0,
                        label: Text('$unread'),
                        child: Icon(entry['chatMuted'] == true ? Icons.notifications_off_outlined : Icons.forum_outlined),
                      ),
                      label: Text(unread > 0
                          ? 'Nhóm chat ($unread tin mới)'
                          : messageCount > 0
                              ? 'Nhóm chat ($messageCount tin)'
                              : 'Mở nhóm chat'),
                    ),
                  ],

                  // Thành viên đánh giá chủ kèo sau khi kèo kết thúc
                  if (entry['canReviewHost'] == true) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _reviewHost,
                      style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                      icon: const Icon(Icons.star_rate_rounded),
                      label: Text(entry['myHostReview'] is Map
                          ? 'Sửa đánh giá chủ kèo (${UiFmt.toNum((entry['myHostReview'] as Map)['rating'], 0).toInt()}★)'
                          : 'Đánh giá chủ kèo'),
                    ),
                  ] else if (entry['myHostReview'] is Map) ...[
                    const SizedBox(height: 12),
                    NoteBox(
                      'Bạn đã đánh giá chủ kèo ${UiFmt.toNum((entry['myHostReview'] as Map)['rating'], 0).toInt()} sao.',
                      icon: Icons.star_rate_rounded,
                    ),
                  ],

                  // Chủ kèo: duyệt đơn ngay tại đây
                  if (isHost) ..._hostSection(theme, post, parts, full),
                  if (isHost && !_closed) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _joining ? null : () => _cancelMatch(post),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        foregroundColor: cs.error,
                        side: BorderSide(color: cs.error.withValues(alpha: 0.6)),
                      ),
                      icon: const Icon(Icons.event_busy_outlined),
                      label: const Text('Hủy kèo'),
                    ),
                  ],

                  // Người đã xin: trạng thái đơn
                  if (!isHost && myRequest != null) ..._memberSection(theme, post, parts, myRequest),

                  if (!isHost && hasHostVideo) ...[
                    const SizedBox(height: 20),
                    SectionHeader('Video giới thiệu của ${post['hostName']}'),
                    VideoLinkPlayer(key: ValueKey('host-${post['id']}'), url: hostVideoUrl),
                  ],
                  if (!isHost && myRequest == null && _app.introVideoUrl.isEmpty) ...[
                    const SizedBox(height: 16),
                    SurfaceCard(
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                      onTap: () => _app.goTo('S29'),
                      child: Row(
                        children: [
                          Icon(Icons.video_call_outlined, color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Thêm link video của bạn vào hồ sơ để chủ kèo dễ duyệt hơn.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
        if (!isHost && !(_closed && myRequest == null))
          BottomActionBar(
            summary: Text(
              switch (myStatus) {
                'APPROVED' => 'Bạn đã được duyệt',
                'REJECTED' => 'Chủ kèo chưa nhận bạn',
                'REMOVED' => 'Bạn không còn trong kèo',
                _ when _closed => status == 'CANCELLED' ? 'Kèo đã bị hủy' : 'Kèo đã kết thúc',
                'PENDING' => 'Đang chờ chủ kèo duyệt',
                _ => full
                    ? 'Kèo đã đủ người'
                    : MatchDeposit.amountOf(post) > 0
                        ? 'Cọc ${UiFmt.vnd(MatchDeposit.amountOf(post))} qua ví'
                        : '${UiFmt.vnd(UiFmt.toNum(post['feePerPlayer'], 0))}/người',
              },
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            action: FilledButton.icon(
              onPressed: (myRequest != null || full || _joining || _closed) ? null : () => _join(entry),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: _joining
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(switch (myStatus) {
                      'APPROVED' => Icons.check_circle_outline,
                      'REJECTED' || 'REMOVED' => Icons.block,
                      'PENDING' => Icons.hourglass_top_rounded,
                      _ => Icons.sports_tennis,
                    }),
              label: Text(switch (myStatus) {
                'APPROVED' => 'Đã vào kèo',
                'REJECTED' => 'Không được duyệt',
                'REMOVED' => 'Đã bị mời ra',
                'PENDING' => 'Đã gửi yêu cầu',
                _ => 'Xin tham gia',
              }),
            ),
          ),
      ],
    );
  }
}
