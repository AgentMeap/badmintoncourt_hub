import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/match_deposit.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';
import 'package:badminton_v2_mobile/core/video_link.dart';
import 'package:badminton_v2_mobile/screens/customer/host_reputation.dart';

// S15: Kèo giao lưu (Luồng 5), chia 2 tab:
// - "Tìm kèo": chỉ kèo của NGƯỜI KHÁC, lọc theo trình độ, xin tham gia ngay trên thẻ.
//   Không còn nút duyệt ở đây để không lẫn với kèo của người khác. Thẻ kèo có điểm uy tín chủ kèo,
//   bộ lọc "Chủ kèo uy tín".
// - "Kèo của tôi": kèo tôi tổ chức (kèm số đơn chờ duyệt) và kèo tôi đã xin tham gia (trạng thái).
//   Bấm thẻ -> S30, nơi chủ kèo duyệt / từ chối đơn.
class S15MatchmakingFeedScreen extends StatefulWidget {
  final AppState appState;
  const S15MatchmakingFeedScreen({super.key, required this.appState});

  @override
  State<S15MatchmakingFeedScreen> createState() => _S15MatchmakingFeedScreenState();
}

class _S15MatchmakingFeedScreenState extends State<S15MatchmakingFeedScreen> {
  String _selectedSkill = 'ALL';
  bool _trustedOnly = false;
  late int _tab = widget.appState.matchTab == 1 ? 1 : 0;
  final Set<String> _joining = {};

  // Dữ liệu tab "Kèo của tôi" (null = chưa tải được, dùng dữ liệu tính từ app.matches)
  List<Json>? _hosting;
  List<Json>? _joined;
  bool _loadingMine = false;

  AppState get _app => widget.appState;

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  List<Json> _participantsOf(Json entry) {
    final list = asJsonList(entry['participants']);
    entry['participants'] = list;
    return list;
  }

  Json _post(Json entry) => asJson(entry['post']);

  bool _isHost(Json post) => '${post['hostId']}' == '${_app.userId}';

  Json? _myRequest(Json entry) =>
      _participantsOf(entry).where((p) => '${p['userId']}' == '${_app.userId}').firstOrNull;

  bool _isFull(Json post) => UiFmt.toNum(post['currentPlayers'], 0) >= UiFmt.toNum(post['maxPlayers'], 0);

  int _pendingOf(Json entry) {
    final n = entry['pendingCount'];
    if (n is num) return n.toInt();
    return _participantsOf(entry).where((p) => p['status'] == 'PENDING').length;
  }

  // ---- Dữ liệu tab "Kèo của tôi" ----

  List<Json> get _hostingList =>
      _hosting ?? _app.matches.where((m) => _isHost(_post(m))).toList();

  List<Json> get _joinedList =>
      _joined ?? _app.matches.where((m) => !_isHost(_post(m)) && _myRequest(m) != null).toList();

  int get _pendingTotal =>
      _hostingList.where((m) => !_isClosed(m)).fold(0, (sum, m) => sum + _pendingOf(m));

  Future<void> _loadMine() async {
    setState(() => _loadingMine = true);
    try {
      final res = await Repos.match.mine();
      if (!mounted) return;
      setState(() {
        _hosting = asJsonList(res['hosting']);
        _joined = asJsonList(res['joined']);
        _loadingMine = false;
      });
    } catch (_) {
      // Mất mạng / máy chủ cũ: vẫn hiện danh sách tính từ bảng tin đã tải
      if (mounted) setState(() => _loadingMine = false);
    }
  }

  Future<void> _refreshAll() async {
    await _app.syncFromBackend();
    await _loadMine();
  }

  void _setTab(int t) {
    setState(() => _tab = t);
    _app.matchTab = t;
    if (t == 1) _loadMine();
  }

  void _open(Json entry, {bool focusRequests = false}) {
    final id = _post(entry)['id'];
    if (id == null) return;
    _app.openMatch(id, focusRequests: focusRequests);
  }

  Future<void> _joinMatch(Json entry) async {
    final post = _post(entry);
    final key = '${post['id']}';
    if (_isHost(post) || _isFull(post) || _myRequest(entry) != null || _joining.contains(key)) return;
    // Kèo có cọc: xác nhận số tiền trước (ví không đủ thì đưa đi nạp)
    if (!await MatchDeposit.confirmJoin(context, _app, post) || !mounted) return;

    setState(() => _joining.add(key));
    final Json participant;
    try {
      participant = await Repos.match.join(post['id'], _app.userId);
    } catch (e) {
      if (mounted) {
        setState(() => _joining.remove(key));
        if (!MatchDeposit.handleJoinError(context, _app, e)) showApiError(context, e);
      }
      return;
    }
    if (!mounted) return;
    if (MatchDeposit.amountOf(post) > 0) _app.refreshWallet();
    setState(() {
      _joining.remove(key);
      _participantsOf(entry).add({
        if (_app.introVideoUrl.isNotEmpty) 'userVideoUrl': _app.introVideoUrl,
        ...participant,
      });
      entry['myStatus'] = 'PENDING';
      _joined = null; // tính lại từ app.matches cho tới lần tải sau
    });

    _app.pushNotification(
      title: 'Đã gửi yêu cầu tham gia kèo',
      body: 'Chủ kèo "${post['title']}" sẽ xem trình độ (${SkillLevel.label(_app.skillLevel)}) và duyệt bạn.',
      type: 'MATCHMAKING',
      targetScreen: 'S15',
      context: context,
    );
    _loadMine();
  }

  // ---- Giao diện ----

  /// Nhãn trạng thái đơn của tôi.
  Widget _statusChip(ThemeData theme, String? status) {
    final cs = theme.colorScheme;
    final (label, icon, bg, fg) = switch (status) {
      'APPROVED' => ('Đã được duyệt', Icons.check_circle, cs.primaryContainer, cs.onPrimaryContainer),
      'REJECTED' => ('Không được duyệt', Icons.block, cs.errorContainer, cs.onErrorContainer),
      'REMOVED' => ('Đã bị mời ra', Icons.person_remove_outlined, cs.errorContainer, cs.onErrorContainer),
      _ => ('Chờ chủ kèo duyệt', Icons.hourglass_top_rounded, cs.secondaryContainer, cs.onSecondaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  /// Thẻ kèo. [footer] là phần cuối thẻ, khác nhau theo tab.
  Widget _matchCard(BuildContext context, Json entry, {required Widget footer, VoidCallback? onTap}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final post = _post(entry);
    final current = UiFmt.toNum(post['currentPlayers'], 0).toInt();
    final max = UiFmt.toNum(post['maxPlayers'], 0).toInt();
    final isHost = _isHost(post);
    final full = _isFull(post);
    final video = VideoLink.tryParse(post['videoUrl']?.toString());

    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap ?? () => _open(entry),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ảnh xem trước video YouTube (bấm để mở S30 xem video)
          if (video?.thumbnailUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: cs.surfaceContainerHighest),
                    Image.network(
                      video!.thumbnailUrl!,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                    Center(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow_rounded, size: 34, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
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
                    if (UiFmt.toNum(entry['unreadMessages'], 0) > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: cs.error, borderRadius: BorderRadius.circular(999)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.forum_outlined, size: 14, color: cs.onError),
                            const SizedBox(width: 4),
                            Text('${UiFmt.toNum(entry['unreadMessages'], 0).toInt()} tin mới',
                                style: theme.textTheme.labelMedium?.copyWith(color: cs.onError, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    if (MatchDeposit.label(post) != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.account_balance_wallet_outlined, size: 14, color: cs.onSecondaryContainer),
                            const SizedBox(width: 4),
                            Text(
                              MatchDeposit.label(post)!,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: cs.onSecondaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (video != null)
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
          _line(theme, Icons.person_outline, 'Chủ kèo: ${isHost ? 'Bạn' : post['hostName']}'),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: HostReputation.summaryRow(theme, entry['host'] is Map ? entry['host'] as Map : null),
          ),
          const SizedBox(height: 12),
          footer,
        ],
      ),
    );
  }

  /// Phần cuối thẻ ở tab "Tìm kèo": xin tham gia hoặc trạng thái đơn của tôi.
  Widget _findFooter(ThemeData theme, Json entry) {
    final post = _post(entry);
    final full = _isFull(post);
    final mine = _myRequest(entry);
    if (mine != null) {
      return Align(alignment: Alignment.centerLeft, child: _statusChip(theme, mine['status']?.toString()));
    }
    final busy = _joining.contains('${post['id']}');
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        onPressed: (full || busy) ? null : () => _joinMatch(entry),
        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
        icon: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(full ? Icons.block : Icons.sports_tennis),
        label: Text(full
            ? 'Kèo đã đủ người'
            : MatchDeposit.amountOf(post) > 0
                ? 'Xin tham gia · cọc ${UiFmt.vnd(MatchDeposit.amountOf(post))}'
                : 'Xin tham gia'),
      ),
    );
  }

  /// Phần cuối thẻ kèo tôi tổ chức: số đơn chờ duyệt + nút vào duyệt.
  bool _isClosed(Json entry) {
    final st = _post(entry)['status'];
    return st == 'CANCELLED' || st == 'COMPLETED';
  }

  /// Nhãn kèo đã hủy / đã kết thúc (thay cho nút thao tác).
  Widget _closedLabel(ThemeData theme, Json entry) {
    final cs = theme.colorScheme;
    final cancelled = _post(entry)['status'] == 'CANCELLED';
    return Row(
      children: [
        Icon(cancelled ? Icons.event_busy_outlined : Icons.flag_outlined,
            size: 18, color: cancelled ? cs.error : cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(cancelled ? 'Kèo đã bị hủy' : 'Kèo đã kết thúc',
              style: theme.textTheme.labelLarge?.copyWith(color: cancelled ? cs.error : cs.onSurfaceVariant)),
        ),
        Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
      ],
    );
  }

  Widget _hostFooter(ThemeData theme, Json entry) {
    final cs = theme.colorScheme;
    if (_isClosed(entry)) return _closedLabel(theme, entry);
    final pending = _pendingOf(entry);
    if (pending == 0) {
      return Row(
        children: [
          Icon(Icons.inbox_outlined, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Chưa có đơn mới',
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
          Text('Xem chi tiết', style: theme.textTheme.labelLarge?.copyWith(color: cs.primary)),
          Icon(Icons.chevron_right, color: cs.primary),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => _open(entry, focusRequests: true),
        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
        icon: Badge(label: Text('$pending'), child: const Icon(Icons.how_to_reg_outlined)),
        label: Text('$pending đơn chờ duyệt'),
      ),
    );
  }

  /// Phần cuối thẻ kèo tôi đã xin: trạng thái (+ lý do nếu bị từ chối).
  Widget _joinedFooter(ThemeData theme, Json entry) {
    final cs = theme.colorScheme;
    if (_isClosed(entry)) return _closedLabel(theme, entry);
    final mine = _myRequest(entry);
    final status = (entry['myStatus'] ?? mine?['status'])?.toString();
    final reason = mine?['rejectReason'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _statusChip(theme, status),
        if ((status == 'REJECTED' || status == 'REMOVED') && reason != null) ...[
          const SizedBox(height: 6),
          Text('Lý do: $reason', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ],
    );
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

  List<Widget> _findTab(BuildContext context, ThemeData theme) {
    final cs = theme.colorScheme;
    final items = _app.matches.where((m) {
      final p = _post(m);
      if (_isHost(p)) return false; // kèo của mình nằm ở tab "Kèo của tôi"
      if (_isClosed(m)) return false; // kèo đã hủy / đã kết thúc
      if (_trustedOnly && !HostReputation.isTrusted(m['host'] is Map ? m['host'] as Map : null)) return false;
      if (_selectedSkill == 'ALL') return true;
      if (_selectedSkill == 'MATCH_ME') {
        final req = p['requiredSkill']?.toString();
        return req == _app.skillLevel || req == 'ALL';
      }
      return p['requiredSkill'] == _selectedSkill;
    }).toList();

    return [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                avatar: Icon(Icons.stars_rounded,
                    size: 16, color: _selectedSkill == 'MATCH_ME' ? cs.onPrimary : cs.primary),
                label: Text('Hợp với tôi (${SkillLevel.label(_app.skillLevel)})'),
                selected: _selectedSkill == 'MATCH_ME',
                showCheckmark: false,
                onSelected: (sel) => setState(() => _selectedSkill = sel ? 'MATCH_ME' : 'ALL'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                avatar: Icon(Icons.verified_rounded, size: 16, color: _trustedOnly ? cs.onPrimary : cs.primary),
                label: const Text('Chủ kèo uy tín'),
                selected: _trustedOnly,
                showCheckmark: false,
                onSelected: (sel) => setState(() => _trustedOnly = sel),
              ),
            ),
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
        for (final e in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _matchCard(context, e, footer: _findFooter(theme, e)),
          ),
    ];
  }

  List<Widget> _mineTab(BuildContext context, ThemeData theme) {
    final hosting = _hostingList;
    final joined = _joinedList;
    return [
      SectionHeader(
        'Tôi tổ chức (${hosting.length})',
        trailing: _loadingMine
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : null,
      ),
      if (hosting.isEmpty)
        EmptyState(
          icon: Icons.campaign_outlined,
          title: 'Bạn chưa mở kèo nào',
          message: 'Mở kèo để tìm thêm người chơi cùng.',
          action: FilledButton.icon(
            onPressed: () => _app.goTo('S16'),
            icon: const Icon(Icons.add),
            label: const Text('Đăng kèo'),
          ),
        )
      else
        for (final e in hosting)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _matchCard(context, e,
                footer: _hostFooter(theme, e),
                onTap: () => _open(e, focusRequests: !_isClosed(e) && _pendingOf(e) > 0)),
          ),
      const SizedBox(height: 8),
      SectionHeader('Tôi tham gia (${joined.length})'),
      if (joined.isEmpty)
        EmptyState(
          icon: Icons.sports_tennis,
          title: 'Bạn chưa xin vào kèo nào',
          action: OutlinedButton.icon(
            onPressed: () => _setTab(0),
            icon: const Icon(Icons.search),
            label: const Text('Tìm kèo'),
          ),
        )
      else
        for (final e in joined)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _matchCard(context, e, footer: _joinedFooter(theme, e)),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pendingTotal = _pendingTotal;

    return ResponsiveCenter(
      maxWidth: Responsive.defaultContentMaxWidth,
      child: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: Responsive.screenPadding(context),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Kèo giao lưu',
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
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(value: 0, icon: Icon(Icons.search), label: Text('Tìm kèo')),
                  ButtonSegment(
                    value: 1,
                    icon: pendingTotal > 0
                        ? Badge(label: Text('$pendingTotal'), child: const Icon(Icons.event_note_outlined))
                        : const Icon(Icons.event_note_outlined),
                    label: const Text('Kèo của tôi'),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => _setTab(s.first),
              ),
            ),
            const SizedBox(height: 12),
            if (_tab == 0) ..._findTab(context, theme) else ..._mineTab(context, theme),
          ],
        ),
      ),
    );
  }
}
