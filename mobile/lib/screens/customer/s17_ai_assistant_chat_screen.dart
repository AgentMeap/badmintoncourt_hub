import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/booking_rules.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S17: AI Badminton Assistant Chat Screen (Module 6: Gemini AI + SQLite RAG)
// Giao diện theo design system: bong bóng chat theo màu Theme, avatar AI bằng icon,
// gợi ý nhanh không dùng emoji, chỉ báo "đang trả lời", tự cuộn xuống tin mới.
// Câu trả lời dự phòng (khi không gọi được API) lấy từ DỮ LIỆU THẬT trong AppState
// và chính sách trong BookingRules, không còn gán cứng tên sân cũ.
class S17AiAssistantChatScreen extends StatefulWidget {
  final AppState appState;
  const S17AiAssistantChatScreen({super.key, required this.appState});

  @override
  State<S17AiAssistantChatScreen> createState() => _S17AiAssistantChatScreenState();
}

class _S17AiAssistantChatScreenState extends State<S17AiAssistantChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scroll = ScrollController();
  late final List<Map<String, dynamic>> _messages;
  bool _sending = false;

  AppState get _app => widget.appState;

  @override
  void initState() {
    super.initState();
    _messages = [
      {
        'sender': 'AI',
        'text': 'Xin chào! Mình là Trợ lý AI Cầu Lông. Bạn có thể hỏi mình về:\n'
            '• Sân còn trống gần bạn\n'
            '• Kèo giao lưu hợp trình độ\n'
            '• Chính sách hủy, hoàn tiền và đổi lịch',
        'showActions': false,
      }
    ];
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _suggestedVenue => _app.venues.isEmpty ? null : _app.venues.first;

  /// Câu trả lời dự phòng dựa trên dữ liệu hiện có trong app.
  String _fallbackReply() {
    final v = _suggestedVenue;
    final openMatch = _app.matches
        .map((m) => m['post'] as Map<String, dynamic>)
        .where((p) => p['status'] == 'OPEN')
        .firstOrNull;
    final lines = <String>[];
    if (v != null) {
      lines.add('• ${v['name']} đang mở cửa ${v['openTime']} - ${v['closeTime']}, '
          'giá từ ${UiFmt.k(UiFmt.toNum(v['basePricePerHour'], 0))}/giờ '
          '(giờ vàng ${UiFmt.k(UiFmt.toNum(v['peakPricePerHour'], 0))}).');
    }
    if (openMatch != null) {
      lines.add('• Kèo "${openMatch['title']}" (${SkillLevel.label(openMatch['requiredSkill']?.toString())}) '
          'đang có ${openMatch['currentPlayers']}/${openMatch['maxPlayers']} người, '
          '${UiFmt.vnd(UiFmt.toNum(openMatch['feePerPlayer'], 0))}/người.');
    }
    lines.add('• Hủy trước ≥ ${BookingRules.fullRefundHours} tiếng hoàn 100%, '
        'từ ${BookingRules.halfRefundHours} - ${BookingRules.fullRefundHours} tiếng hoàn 50%, '
        'dưới ${BookingRules.halfRefundHours} tiếng không hoàn. Mỗi vé được đổi lịch '
        '${BookingRules.maxReschedules} lần.');
    return 'Mình tìm được vài thông tin cho bạn:\n${lines.join('\n')}';
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      // Tôn trọng cài đặt "giảm chuyển động" của hệ thống
      if (MediaQuery.of(context).disableAnimations) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
        return;
      }
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _sending) return;
    setState(() {
      _messages.add({'sender': 'USER', 'text': text.trim()});
      _msgCtrl.clear();
      _sending = true;
    });
    _scrollToEnd();

    String reply = _fallbackReply();
    try {
      final res = await ApiService.post('/ai/chat', {'message': text.trim()});
      if (res is Map && res['reply'] != null) {
        reply = res['reply'].toString();
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _sending = false;
      _messages.add({'sender': 'AI', 'text': reply, 'showActions': true});
    });
    _scrollToEnd();
  }

  Widget _bubble(BuildContext context, Map<String, dynamic> m, double maxWidth) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isUser = m['sender'] == 'USER';

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      constraints: BoxConstraints(maxWidth: maxWidth),
      decoration: BoxDecoration(
        color: isUser ? cs.primary : cs.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 18),
        ),
        border: isUser ? null : Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            m['text'].toString(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isUser ? cs.onPrimary : cs.onSurface,
              height: 1.45,
            ),
          ),
          if (m['showActions'] == true) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_suggestedVenue != null)
                  FilledButton.tonalIcon(
                    onPressed: () {
                      _app.selectedVenue = _suggestedVenue;
                      _app.goTo('S09');
                    },
                    icon: const Icon(Icons.event_available_outlined, size: 18),
                    label: const Text('Đặt sân'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _app.goTo('S15'),
                  icon: const Icon(Icons.groups_outlined, size: 18),
                  label: const Text('Xem kèo'),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (isUser) {
      return Align(alignment: Alignment.centerRight, child: bubble);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: cs.secondaryContainer,
          child: Icon(Icons.auto_awesome, size: 16, color: cs.onSecondaryContainer),
        ),
        const SizedBox(width: 8),
        Flexible(child: bubble),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final suggestions = <(IconData, String, String)>[
      (Icons.search, 'Sân trống tối nay', 'Tìm giúp mình sân còn trống tối nay gần đây'),
      (Icons.groups_outlined, 'Kèo hợp trình độ',
          'Có kèo giao lưu trình độ ${SkillLevel.label(_app.skillLevel)} nào đang mở không?'),
      (Icons.policy_outlined, 'Chính sách hoàn tiền', 'Chính sách hủy sân và hoàn tiền về ví như thế nào?'),
    ];

    return ResponsiveCenter(
      maxWidth: Responsive.defaultContentMaxWidth,
      child: Column(
        children: [
          // Gợi ý nhanh
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (icon, label, prompt) in suggestions)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: Icon(icon, size: 18),
                        label: Text(label),
                        onPressed: _sending ? null : () => _sendMessage(prompt),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth =
                    (constraints.maxWidth * (constraints.maxWidth < 600 ? 0.82 : 0.66)).clamp(220.0, 620.0);
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(14),
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  itemBuilder: (context, idx) {
                    if (idx == _messages.length) {
                      // Chỉ báo đang trả lời
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: cs.secondaryContainer,
                              child: Icon(Icons.auto_awesome, size: 16, color: cs.onSecondaryContainer),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                            ),
                            const SizedBox(width: 8),
                            Text('Đang trả lời...',
                                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _bubble(context, _messages[idx], maxWidth),
                    );
                  },
                );
              },
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
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      onSubmitted: _sendMessage,
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Hỏi Trợ lý AI...',
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
                    onPressed: _sending ? null : () => _sendMessage(_msgCtrl.text),
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
