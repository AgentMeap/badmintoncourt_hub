import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S16: Create Match Post Screen (Luồng 5)
// Giao diện theo design system + sửa logic:
// - Số người hiện có / tối đa chọn bằng bộ đếm (trước đây gán cứng 3/6)
// - Kiểm tra tiêu đề, chi phí; không cho mở kèo từ vé đã hủy
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
  String _skill = 'TB_YEU';
  int _currentPlayers = 2;
  int _maxPlayers = 6;
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _feeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitMatch() async {
    if (_loading) return;
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _loading = true);

    final newPost = {
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
      await ApiService.post('/matches', newPost);
    } catch (_) {}

    widget.appState.matches.insert(0, {
      'post': newPost,
      'participants': <Map<String, dynamic>>[],
    });

    if (!mounted) return;
    setState(() => _loading = false);
    widget.appState.pushNotification(
      title: 'Đã đăng kèo giao lưu',
      body: '${newPost['title']} tại ${newPost['venueName']} (${newPost['courtName']}).',
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
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Đăng kèo',
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
