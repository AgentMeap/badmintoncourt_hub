import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S28: Đánh giá sân sau khi chơi
// - Chỉ mở từ vé ĐÃ NHẬN SÂN (check-in) hoặc đã hoàn thành, mỗi vé đánh giá 1 lần
// - Chọn sao (bắt buộc), gợi ý nhanh, nhận xét (không bắt buộc)
// - Lưu vào appState.reviews; S08 hiển thị các đánh giá gần đây của cơ sở.
//   Điểm trung bình của cơ sở do backend tính lại (app không tự sửa số liệu).
class S28VenueReviewScreen extends StatefulWidget {
  final AppState appState;
  const S28VenueReviewScreen({super.key, required this.appState});

  /// Vé có được đánh giá không (đã nhận sân / hoàn thành và chưa đánh giá).
  static bool canReview(Map<String, dynamic> b) =>
      (b['status'] == 'CHECKED_IN' || b['status'] == 'COMPLETED') &&
      b['bookingType'] == 'ONLINE' &&
      b['reviewed'] != true;

  @override
  State<S28VenueReviewScreen> createState() => _S28VenueReviewScreenState();
}

class _S28VenueReviewScreenState extends State<S28VenueReviewScreen> {
  final _commentCtrl = TextEditingController();
  final Set<String> _tags = {};
  int _rating = 0;
  bool _loading = false;

  static const _tagOptions = [
    'Mặt sân tốt',
    'Ánh sáng tốt',
    'Sạch sẽ',
    'Giá hợp lý',
    'Chủ sân thân thiện',
    'Gửi xe tiện',
  ];
  static const _ratingLabels = ['', 'Rất tệ', 'Chưa tốt', 'Bình thường', 'Tốt', 'Tuyệt vời'];

  AppState get _app => widget.appState;
  Map<String, dynamic> get _b => _app.selectedBooking ?? _app.bookings.first;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final b = _b;
    if (_loading || _rating == 0) return;
    if (!S28VenueReviewScreen.canReview(b)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vé này chưa thể đánh giá hoặc đã được đánh giá.')),
      );
      return;
    }
    setState(() => _loading = true);
    final review = <String, dynamic>{
      'id': DateTime.now().millisecondsSinceEpoch % 100000,
      'bookingCode': b['bookingCode'],
      'venueId': b['venueId'],
      'venueName': b['venueName'],
      'userId': _app.userId,
      'userName': _app.fullName.split('(').first.trim(),
      'rating': _rating,
      'tags': _tags.toList(),
      'comment': _commentCtrl.text.trim(),
      'createdAt': 'Vừa xong',
    };
    try {
      await ApiService.post('/reviews', review);
    } catch (_) {}

    if (!mounted) return;
    _app.reviews.insert(0, review);
    b['reviewed'] = true;
    b['reviewRating'] = _rating;
    setState(() => _loading = false);
    _app.pushNotification(
      title: 'Cảm ơn bạn đã đánh giá',
      body: 'Đánh giá $_rating sao cho ${b['venueName']} đã được ghi nhận.',
      type: 'BOOKING',
      targetScreen: 'S13',
      context: context,
    );
    // Quay về vé, bỏ màn đánh giá khỏi lịch sử
    _app.completeFlow('S13', flowStart: 'S28');
  }

  Widget _star(ColorScheme cs, int i) {
    final filled = i <= _rating;
    return Semantics(
      button: true,
      selected: filled,
      label: '$i sao',
      child: IconButton(
        tooltip: '$i sao',
        iconSize: 40,
        style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
        onPressed: () => setState(() => _rating = i),
        icon: Icon(
          filled ? Icons.star_rounded : Icons.star_outline_rounded,
          color: filled ? Colors.amber.shade700 : cs.outline,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final b = _b;
    final allowed = S28VenueReviewScreen.canReview(b);

    return Column(
      children: [
        Expanded(
          child: ResponsiveCenter(
            maxWidth: Responsive.defaultFormMaxWidth,
            child: ListView(
              padding: Responsive.screenPadding(context),
              children: [
                Text('Đánh giá sân',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                SurfaceCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.sports_tennis, color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${b['venueName']}',
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
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
                if (!allowed)
                  NoteBox(
                    b['reviewed'] == true
                        ? 'Bạn đã đánh giá vé này (${b['reviewRating'] ?? '-'} sao).'
                        : 'Bạn có thể đánh giá sau khi đã nhận sân (check-in).',
                  )
                else ...[
                  Center(
                    child: Text('Bạn thấy sân thế nào?',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [for (var i = 1; i <= 5; i++) _star(cs, i)],
                  ),
                  Center(
                    child: Text(
                      _rating == 0 ? 'Chạm để chọn số sao' : _ratingLabels[_rating],
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _rating == 0 ? cs.onSurfaceVariant : cs.onSurface,
                        fontWeight: _rating == 0 ? FontWeight.w400 : FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SectionHeader('Điểm bạn hài lòng'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in _tagOptions)
                        FilterChip(
                          label: Text(t),
                          selected: _tags.contains(t),
                          onSelected: (on) => setState(() => on ? _tags.add(t) : _tags.remove(t)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _commentCtrl,
                    maxLines: 4,
                    maxLength: 300,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nhận xét (không bắt buộc)',
                      hintText: 'Chia sẻ trải nghiệm của bạn cho người chơi khác',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        if (allowed)
          BottomActionBar(
            summary: Text(
              _rating == 0 ? 'Chọn số sao để gửi' : '$_rating sao • ${_ratingLabels[_rating]}',
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            action: FilledButton.icon(
              onPressed: (_rating == 0 || _loading) ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: _loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                    )
                  : const Icon(Icons.send_outlined),
              label: const Text('Gửi đánh giá'),
            ),
          ),
      ],
    );
  }
}
