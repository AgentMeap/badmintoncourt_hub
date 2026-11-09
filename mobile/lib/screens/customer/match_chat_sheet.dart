import 'dart:async';

import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

/// Mở nhóm chat của một kèo (chủ kèo + thành viên đã duyệt) dạng bảng trượt gần toàn màn hình.
Future<void> showMatchChatSheet(BuildContext context, {required Object matchId, required String title}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: MatchChatSheet(matchId: matchId, title: title),
    ),
  );
}

/// Nhóm chat của kèo. Tải 100 tin gần nhất, sau đó cứ 4 giây hỏi tin mới (afterId) khi bảng đang mở.
class MatchChatSheet extends StatefulWidget {
  final Object matchId;
  final String title;
  const MatchChatSheet({super.key, required this.matchId, required this.title});

  @override
  State<MatchChatSheet> createState() => _MatchChatSheetState();
}

class _MatchChatSheetState extends State<MatchChatSheet> {
  static const _pollEvery = Duration(seconds: 4);

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Json> _items = [];
  Timer? _timer;
  bool _loading = true;
  bool _sending = false;
  bool _closed = false;
  bool _polling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Object? get _lastId => _items.isEmpty ? null : _items.last['id'];

  Future<void> _load() async {
    try {
      final res = await Repos.match.messages(widget.matchId);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(asJsonList(res['items']));
        _closed = res['closed'] == true;
        _loading = false;
        _error = null;
      });
      _jumpToEnd();
      _timer ??= Timer.periodic(_pollEvery, (_) => _poll());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : 'Không tải được tin nhắn.';
      });
    }
  }

  Future<void> _poll() async {
    if (_polling || !mounted) return;
    _polling = true;
    try {
      final res = await Repos.match.messages(widget.matchId, afterId: _lastId);
      final fresh = asJsonList(res['items']);
      if (!mounted) return;
      final known = _items.map((m) => '${m['id']}').toSet();
      final add = fresh.where((m) => !known.contains('${m['id']}')).toList();
      if (add.isNotEmpty || (res['closed'] == true) != _closed) {
        final atEnd = !_scroll.hasClients || _scroll.position.extentAfter < 80;
        setState(() {
          _items.addAll(add);
          _closed = res['closed'] == true;
        });
        if (atEnd) _jumpToEnd();
      }
    } catch (_) {
      // Mất mạng tạm thời: lần hỏi sau thử lại
    } finally {
      _polling = false;
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final msg = await Repos.match.sendMessage(widget.matchId, text);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _input.clear();
        if (!_items.any((m) => '${m['id']}' == '${msg['id']}')) _items.add(msg);
      });
      _jumpToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showApiError(context, e);
    }
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  /// "2026-11-09 23:50:12" -> "23:50" (hôm nay) hoặc "23:50 09/11".
  static String _time(dynamic raw) {
    final t = DateTime.tryParse('${raw ?? ''}'.replaceFirst(' ', 'T'));
    if (t == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final hm = '${two(t.hour)}:${two(t.minute)}';
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    return sameDay ? hm : '$hm ${two(t.day)}/${two(t.month)}';
  }

  Widget _bubble(ThemeData theme, Json m, bool showName) {
    final cs = theme.colorScheme;
    final mine = m['mine'] == true;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (showName && !mine)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 8, bottom: 2),
                child: Text('${m['userName'] ?? ''}',
                    style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              decoration: BoxDecoration(
                color: mine ? cs.primary : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${m['content'] ?? ''}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: mine ? cs.onPrimary : cs.onSurface)),
                  const SizedBox(height: 2),
                  Text(_time(m['createdAt']),
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: (mine ? cs.onPrimary : cs.onSurfaceVariant).withValues(alpha: 0.8))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'Không mở được nhóm chat',
          message: _error,
          action: OutlinedButton(
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
            child: const Text('Thử lại'),
          ),
        ),
      );
    } else if (_items.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.all(16),
        child: EmptyState(
          icon: Icons.forum_outlined,
          title: 'Chưa có tin nhắn',
          message: 'Hẹn giờ, chia tiền sân, ai mang cầu... nhắn ở đây cho cả nhóm.',
        ),
      );
    } else {
      body = ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final m = _items[i];
          final showName = i == 0 || '${_items[i - 1]['userId']}' != '${m['userId']}';
          return _bubble(theme, m, showName);
        },
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          child: Row(
            children: [
              Icon(Icons.forum_outlined, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nhóm chat', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Đóng',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(child: body),
        if (!_loading && _error == null)
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 8, 8 + MediaQuery.viewInsetsOf(context).bottom),
              child: _closed
                  ? const NoteBox('Kèo đã kết thúc hoặc đã hủy. Bạn vẫn xem lại được tin nhắn.',
                      icon: Icons.lock_clock_outlined)
                  : Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: 500,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: const InputDecoration(
                              hintText: 'Nhắn cho cả nhóm...',
                              counterText: '',
                              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filled(
                          tooltip: 'Gửi',
                          onPressed: _sending ? null : _send,
                          icon: _sending
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
            ),
          ),
      ],
    );
  }
}
