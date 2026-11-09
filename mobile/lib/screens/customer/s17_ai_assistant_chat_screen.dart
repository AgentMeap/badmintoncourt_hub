import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';
import 'package:badminton_v2_mobile/screens/customer/ai/ai_cards.dart';
import 'package:badminton_v2_mobile/screens/customer/ai/ai_hold_sheet.dart';

// S17: Trợ lý AI (chỉ dành cho người chơi - CUSTOMER).
// - Lịch sử hội thoại lưu trên máy chủ, mở lại màn hình vẫn thấy.
// - Câu trả lời kèm Rich Card (sân trống + nút "Giữ chỗ", kèo giao lưu, bản đồ mini...).
// - Quick Chips do máy chủ gợi ý theo ngữ cảnh; nút micro nhập bằng giọng nói (speech_to_text).
// - Giới hạn 300 ký tự/câu, 5 tin/phút, 30 tin/ngày (máy chủ kiểm soát, app chỉ hiển thị).
class S17AiAssistantChatScreen extends StatefulWidget {
  final AppState appState;
  const S17AiAssistantChatScreen({super.key, required this.appState});

  @override
  State<S17AiAssistantChatScreen> createState() => _S17AiAssistantChatScreenState();
}

enum _Kind { user, ai, notice }

class _ChatMessage {
  _ChatMessage(this.kind, this.text, {this.cards = const [], this.outOfScope = false});
  final _Kind kind;
  final String text;
  final List<Json> cards;
  final bool outOfScope;
}

class _S17AiAssistantChatScreenState extends State<S17AiAssistantChatScreen> {
  static const _maxLength = 300;
  static const _greeting = 'Xin chào! Mình là Trợ lý AI Cầu Lông. Mình có thể giúp bạn:\n'
      '• Tìm sân còn trống và giữ chỗ ngay trong khung chat\n'
      '• Gợi ý kèo giao lưu hợp trình độ\n'
      '• Giải đáp bảng giá, chính sách hủy, hoàn tiền và đổi lịch';
  static const _defaultChips = [
    'Sân trống tối nay',
    'Kèo hợp trình độ của tôi',
    'Chính sách hủy sân',
    'Vé sắp tới của tôi',
  ];

  final _msgCtrl = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_ChatMessage>[];
  List<String> _chips = _defaultChips;
  Object? _sessionId;
  Json _quota = const {};
  bool _loading = true;
  bool _sending = false;
  String? _busySlotKey;

  final _speech = SpeechToText();
  bool _speechReady = false;
  bool _listening = false;
  String? _viLocaleId;

  AppState get _app => widget.appState;
  bool get _isCustomer => _app.role == 'CUSTOMER';

  @override
  void initState() {
    super.initState();
    _msgCtrl.addListener(() => setState(() {}));
    if (_isCustomer) _loadSession();
  }

  @override
  void dispose() {
    if (_listening) _speech.cancel();
    _msgCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ dữ liệu

  void _applySession(Json res) {
    _sessionId = res['sessionId'];
    _quota = asJson(res['quota']);
    _messages.clear();
    List<String> lastChips = _defaultChips;
    for (final m in asJsonList(res['messages'])) {
      final isUser = '${m['role']}' == 'USER';
      _messages.add(_ChatMessage(
        isUser ? _Kind.user : _Kind.ai,
        '${m['content'] ?? ''}',
        cards: isUser ? const [] : asJsonList(m['cards']),
      ));
      if (!isUser) {
        final chips = _chipsOf(m['quickChips']);
        if (chips.isNotEmpty) lastChips = chips;
      }
    }
    _chips = lastChips;
  }

  Future<void> _loadSession() async {
    try {
      final res = await Repos.ai.currentSession();
      if (!mounted) return;
      setState(() => _applySession(res));
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  Future<void> _newConversation() async {
    if (_sending) return;
    setState(() => _loading = true);
    try {
      final res = await Repos.ai.newSession();
      if (!mounted) return;
      setState(() => _applySession(res));
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> _chipsOf(dynamic raw) =>
      raw is List ? raw.map((e) => '$e').where((e) => e.trim().isNotEmpty).take(4).toList() : const [];

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _sending) return;
    if (text.length > _maxLength) {
      setState(() => _messages.add(_ChatMessage(_Kind.notice, 'Câu hỏi tối đa $_maxLength ký tự, bạn rút gọn giúp mình nhé.')));
      return;
    }
    if (_listening) await _speech.stop();
    _msgCtrl.clear();
    setState(() {
      _messages.add(_ChatMessage(_Kind.user, text));
      _sending = true;
    });
    _scrollToBottom();

    try {
      final res = await Repos.ai.chat(text, sessionId: _sessionId);
      if (!mounted) return;
      setState(() {
        _sessionId = res['sessionId'] ?? _sessionId;
        final quota = asJson(res['quota']);
        if (quota.isNotEmpty) _quota = quota;
        _messages.add(_ChatMessage(
          _Kind.ai,
          '${res['reply'] ?? ''}',
          cards: asJsonList(res['cards']),
          outOfScope: res['inScope'] == false,
        ));
        final chips = _chipsOf(res['quickChips']);
        _chips = chips.isEmpty ? _defaultChips : chips;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          _Kind.notice,
          e.kind == ApiErrorKind.tooManyRequests
              ? '${e.message}\nBạn có thể dùng các màn Tìm sân / Kèo giao lưu trong lúc chờ.'
              : e.message,
        ));
        if (e.kind == ApiErrorKind.tooManyRequests) _refreshQuota();
      });
    } catch (e) {
      if (mounted) setState(() => _messages.add(_ChatMessage(_Kind.notice, 'Không gửi được câu hỏi, vui lòng thử lại.')));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  Future<void> _refreshQuota() async {
    try {
      final res = await Repos.ai.currentSession();
      if (mounted) setState(() => _quota = asJson(res['quota']));
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ------------------------------------------------------------- hành động thẻ

  void _snack(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)));

  void _openVenue(Json card) {
    final id = '${card['venueId'] ?? card['id']}';
    Json? venue;
    for (final v in _app.venues) {
      if ('${v['id']}' == id) venue = v;
    }
    if (venue == null) {
      _snack('Không tìm thấy sân này, vui lòng tải lại danh sách sân.');
      return;
    }
    _app.selectedVenue = venue;
    _app.goTo('S08');
  }

  Future<void> _holdSlot(Json slot) async {
    if (_busySlotKey != null) return;
    setState(() => _busySlotKey = AiCardList.slotKey(slot));
    try {
      await holdSlotFromAi(context, _app, slot);
    } finally {
      if (mounted) setState(() => _busySlotKey = null);
    }
  }

  Future<void> _openMatch(Object matchId) async {
    Json? find() {
      for (final m in _app.matches) {
        if ('${asJson(m['post'])['id']}' == '$matchId') return m;
      }
      return null;
    }

    var entry = find();
    if (entry == null) {
      try {
        _app.matches = await Repos.match.list();
        entry = find();
      } catch (e) {
        if (mounted) showApiError(context, e);
        return;
      }
    }
    if (!mounted) return;
    if (entry == null) {
      _snack('Kèo này không còn mở.');
      return;
    }
    _app.selectedMatch = entry;
    _app.goTo('S30');
  }

  Future<void> _openBooking(Object bookingId) async {
    Json? booking;
    for (final b in _app.bookings) {
      if ('${b['id']}' == '$bookingId') booking = b;
    }
    if (booking == null) {
      try {
        booking = asJson((await Repos.booking.detail(bookingId))['booking']);
      } catch (e) {
        if (mounted) showApiError(context, e);
        return;
      }
    }
    if (!mounted || booking.isEmpty) return;
    _app.selectedBooking = booking;
    _app.goTo('S13');
  }

  // ---------------------------------------------------------------- giọng nói

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (!_speechReady) {
      try {
        _speechReady = await _speech.initialize(
          onStatus: (status) {
            if (!mounted) return;
            if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
              setState(() => _listening = false);
            }
          },
          onError: (_) {
            if (mounted) setState(() => _listening = false);
          },
        );
        if (_speechReady) {
          final locales = await _speech.locales();
          for (final l in locales) {
            if (l.localeId.toLowerCase().startsWith('vi')) _viLocaleId = l.localeId;
          }
        }
      } catch (e) {
        debugPrint('[S17 voice] $e');
        _speechReady = false;
      }
    }
    if (!mounted) return;
    if (!_speechReady) {
      _snack('Không dùng được nhập giọng nói. Hãy cấp quyền Micro cho ứng dụng trong Cài đặt.');
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: _onSpeech,
      localeId: _viLocaleId,
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
      ),
    );
  }

  void _onSpeech(SpeechRecognitionResult result) {
    var words = result.recognizedWords;
    if (words.length > _maxLength) words = words.substring(0, _maxLength);
    _msgCtrl.value = TextEditingValue(
      text: words,
      selection: TextSelection.collapsed(offset: words.length),
    );
    if (result.finalResult && mounted) setState(() => _listening = false);
  }

  // ---------------------------------------------------------------------- UI

  Widget _avatar(ColorScheme cs) => CircleAvatar(
        radius: 16,
        backgroundColor: cs.secondaryContainer,
        child: Icon(Icons.auto_awesome, size: 16, color: cs.onSecondaryContainer),
      );

  Widget _messageView(BuildContext context, _ChatMessage m, double maxWidth) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (m.kind == _Kind.notice) {
      return NoteBox(m.text, icon: Icons.info_outline, tone: NoteTone.warning);
    }

    final isUser = m.kind == _Kind.user;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser ? cs.primary : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isUser ? 16 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 16),
        ),
      ),
      child: Text(
        m.text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: isUser ? cs.onPrimary : cs.onSurface,
          height: 1.45,
        ),
      ),
    );

    if (isUser) return Align(alignment: Alignment.centerRight, child: bubble);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _avatar(cs),
        const SizedBox(width: 8),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bubble,
                if (m.cards.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  AiCardList(
                    cards: m.cards,
                    busySlotKey: _busySlotKey,
                    onOpenVenue: _openVenue,
                    onHoldSlot: _holdSlot,
                    onOpenMatch: _openMatch,
                    onOpenBooking: _openBooking,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _typingIndicator(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        _avatar(cs),
        const SizedBox(width: 8),
        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
        const SizedBox(width: 8),
        Text('Đang trả lời...', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCustomer) {
      return const EmptyState(
        icon: Icons.lock_outline,
        title: 'Trợ lý AI dành cho người chơi',
        message: 'Tính năng hỏi đáp và đặt sân bằng AI chỉ mở cho tài khoản Người chơi.',
      );
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dayLeft = asNum(_quota['dayLeft']);
    final outOfQuota = dayLeft != null && dayLeft <= 0;
    final canSend = !_sending && !_loading && !outOfQuota && _msgCtrl.text.trim().isNotEmpty;

    return ResponsiveCenter(
      maxWidth: Responsive.defaultContentMaxWidth,
      child: Column(
        children: [
          // Thanh trạng thái: hạn mức + cuộc trò chuyện mới
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(Icons.bolt_outlined, size: 18, color: outOfQuota ? cs.error : cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    dayLeft == null
                        ? 'Trợ lý chỉ trả lời về đặt sân, kèo và chính sách'
                        : outOfQuota
                            ? 'Đã hết lượt hỏi hôm nay'
                            : 'Còn ${dayLeft.toInt()}/${_quota['perDay'] ?? 30} lượt hỏi hôm nay',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: outOfQuota ? cs.error : cs.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: (_loading || _sending) ? null : _newConversation,
                  icon: const Icon(Icons.add_comment_outlined, size: 18),
                  label: const Text('Cuộc trò chuyện mới'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final maxWidth =
                          (constraints.maxWidth * (constraints.maxWidth < 600 ? 0.82 : 0.66)).clamp(220.0, 620.0);
                      final items = <Widget>[
                        if (_messages.isEmpty) _messageView(context, _ChatMessage(_Kind.ai, _greeting), maxWidth),
                        for (final m in _messages) _messageView(context, m, maxWidth),
                        if (_sending) _typingIndicator(context),
                      ];
                      return ListView.separated(
                        controller: _scroll,
                        padding: const EdgeInsets.all(14),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => items[i],
                      );
                    },
                  ),
          ),
          // Quick Chips
          if (!_loading && _chips.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final chip in _chips)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(chip),
                          onPressed: (_sending || outOfQuota) ? null : () => _send(chip),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          // Ô nhập
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!kIsWeb) ...[
                    IconButton(
                      tooltip: _listening ? 'Dừng ghi âm' : 'Nói để nhập',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor: _listening ? cs.errorContainer : null,
                      ),
                      onPressed: (_sending || outOfQuota) ? null : _toggleListening,
                      icon: Icon(
                        _listening ? Icons.stop_circle_outlined : Icons.mic_none_rounded,
                        color: _listening ? cs.onErrorContainer : null,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      enabled: !outOfQuota,
                      maxLength: _maxLength,
                      onSubmitted: _send,
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: _listening
                            ? 'Đang nghe...'
                            : outOfQuota
                                ? 'Hết lượt hỏi hôm nay, quay lại vào ngày mai nhé'
                                : 'Hỏi về sân trống, kèo, chính sách...',
                        counterText: _msgCtrl.text.length > 250 ? '${_msgCtrl.text.length}/$_maxLength' : '',
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Gửi',
                    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: canSend ? () => _send(_msgCtrl.text) : null,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
