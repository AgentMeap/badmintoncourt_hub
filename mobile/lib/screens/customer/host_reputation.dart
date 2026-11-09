import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

/// Uy tín chủ kèo (S15, S30): dòng điểm, hồ sơ chủ kèo, bảng đánh giá.
/// Dữ liệu `host` từ máy chủ: {score, count, skillAccuracy, skillBias, cancelRate, completed, badge}.
class HostReputation {
  HostReputation._();

  static const accuracyLabels = {
    'ACCURATE': 'Đúng như mô tả',
    'HIGHER': 'Cao hơn mô tả',
    'LOWER': 'Thấp hơn mô tả',
  };

  static const positiveTags = ['Đúng giờ', 'Vui vẻ', 'Chia tiền rõ ràng', 'Cầu tốt', 'Sân như mô tả'];
  static const negativeTags = ['Đến muộn', 'Thiếu người', 'Đổi giờ/đổi sân', 'Thu thêm tiền'];

  static bool isTrusted(Map? host) => host?['badge'] == 'TRUSTED';

  static String _pct(dynamic v) => '${(UiFmt.toNum(v, 0) * 100).round()}%';

  /// Dòng tóm tắt: ⭐ 4.7 (12) · Đúng trình độ 92% · huy hiệu. Chưa có đánh giá thì "Chủ kèo mới".
  static Widget summaryRow(ThemeData theme, Map? host, {VoidCallback? onTap}) {
    final cs = theme.colorScheme;
    final count = UiFmt.toNum(host?['count'], 0).toInt();
    final badge = host?['badge'];
    final style = theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant);
    final children = <Widget>[
      if (count == 0)
        Text('Chủ kèo mới, chưa có đánh giá', style: style)
      else ...[
        Icon(Icons.star_rounded, size: 16, color: Colors.amber.shade700),
        const SizedBox(width: 2),
        Text(UiFmt.toNum(host?['score'], 0).toStringAsFixed(1),
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
        Text(' ($count)', style: style),
        if (host?['skillAccuracy'] != null) Text(' · Đúng trình độ ${_pct(host?['skillAccuracy'])}', style: style),
      ],
      if (badge == 'TRUSTED') ...[
        const SizedBox(width: 6),
        _chip(theme, Icons.verified_rounded, 'Uy tín', cs.primaryContainer, cs.onPrimaryContainer),
      ] else if (badge == 'SKILL_MISMATCH') ...[
        const SizedBox(width: 6),
        _chip(theme, Icons.warning_amber_rounded,
            host?['skillBias'] == 'HIGHER' ? 'Hay mô tả thấp hơn thực tế' : 'Hay mô tả cao hơn thực tế',
            cs.errorContainer, cs.onErrorContainer),
      ],
    ];
    final row = Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 4, children: children),
    );
    if (onTap == null) return row;
    return InkWell(borderRadius: BorderRadius.circular(8), onTap: onTap, child: row);
  }

  static Widget _chip(ThemeData theme, IconData icon, String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
            Text(text, style: theme.textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  static Widget _stars(int value, {double size = 18, ValueChanged<int>? onChanged}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            onChanged == null
                ? Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: size, color: Colors.amber.shade700)
                : IconButton(
                    tooltip: '$i sao',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onChanged(i),
                    icon: Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: size, color: Colors.amber.shade700),
                  ),
        ],
      );

  /// Hồ sơ chủ kèo: chỉ số + 20 đánh giá gần nhất (hiện tên người đánh giá).
  static Future<void> showProfileSheet(BuildContext context, {required Object hostId, required String hostName}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.85,
        child: FutureBuilder<Json>(
          future: Repos.match.hostProfile(hostId),
          builder: (ctx, snap) {
            final theme = Theme.of(ctx);
            final cs = theme.colorScheme;
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: EmptyState(icon: Icons.cloud_off_outlined, title: 'Không tải được hồ sơ chủ kèo'),
              );
            }
            final data = snap.data ?? const <String, dynamic>{};
            final s = asJson(data['summary']);
            final reviews = asJsonList(data['reviews']);
            final count = UiFmt.toNum(s['count'], 0).toInt();
            Widget stat(String value, String label) => Expanded(
                  child: Column(
                    children: [
                      Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      Text(label,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                );
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text(hostName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                Text('Trình độ: ${SkillLevel.label(data['hostSkill']?.toString())}',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                summaryRow(theme, s),
                const SizedBox(height: 16),
                Row(
                  children: [
                    stat(count == 0 ? '–' : UiFmt.toNum(s['score'], 0).toStringAsFixed(1), 'Điểm ($count đánh giá)'),
                    stat(s['skillAccuracy'] == null ? '–' : _pct(s['skillAccuracy']), 'Đúng trình độ'),
                    stat('${UiFmt.toNum(s['completed'], 0).toInt()}', 'Kèo đã tổ chức'),
                    stat(s['cancelRate'] == null ? '–' : _pct(s['cancelRate']), 'Tỉ lệ hủy kèo'),
                  ],
                ),
                const SizedBox(height: 20),
                SectionHeader('Đánh giá gần đây (${reviews.length})'),
                if (reviews.isEmpty)
                  Text('Chưa có ai đánh giá chủ kèo này.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
                else
                  for (final r in reviews)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('${r['raterName'] ?? ''}',
                                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                              ),
                              _stars(UiFmt.toNum(r['rating'], 0).toInt(), size: 16),
                            ],
                          ),
                          Text(
                            'Trình độ nhóm: ${accuracyLabels[r['skillAccuracy']] ?? '-'} · ${r['matchTitle'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          if ((r['tags'] as List? ?? const []).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  for (final t in (r['tags'] as List? ?? const []))
                                    Text('#$t',
                                        style: theme.textTheme.labelSmall?.copyWith(
                                            color: negativeTags.contains(t) ? cs.error : cs.primary)),
                                ],
                              ),
                            ),
                          if ((r['comment'] ?? '').toString().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('${r['comment']}', style: theme.textTheme.bodyMedium),
                            ),
                        ],
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Bảng đánh giá chủ kèo (tạo mới hoặc sửa). Trả về `entry` mới của kèo nếu gửi thành công.
  static Future<Json?> showReviewSheet(BuildContext context,
      {required Object matchId, required String hostName, Map? existing}) {
    return showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ReviewForm(matchId: matchId, hostName: hostName, existing: existing),
    );
  }
}

class _ReviewForm extends StatefulWidget {
  final Object matchId;
  final String hostName;
  final Map? existing;
  const _ReviewForm({required this.matchId, required this.hostName, this.existing});

  @override
  State<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends State<_ReviewForm> {
  late int _rating = UiFmt.toNum(widget.existing?['rating'], 0).toInt();
  late String? _accuracy = widget.existing?['skillAccuracy']?.toString();
  late final Set<String> _tags = {...((widget.existing?['tags'] as List?) ?? const []).map((t) => '$t')};
  late final _comment = TextEditingController(text: widget.existing?['comment']?.toString() ?? '');
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0 || _accuracy == null || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await Repos.match.reviewHost(widget.matchId,
          rating: _rating, skillAccuracy: _accuracy!, tags: _tags.toList(), comment: _comment.text);
      if (!mounted) return;
      Navigator.pop(context, asJson(res['entry']));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showApiError(context, e);
    }
  }

  Widget _tagChip(String t, {required bool negative}) {
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(t),
      selected: _tags.contains(t),
      selectedColor: negative ? cs.errorContainer : null,
      onSelected: (v) => setState(() => v ? _tags.add(t) : _tags.remove(t)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ready = _rating > 0 && _accuracy != null;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.existing == null ? 'Đánh giá chủ kèo' : 'Sửa đánh giá',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text(widget.hostName, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          Center(child: HostReputation._stars(_rating, size: 34, onChanged: (v) => setState(() => _rating = v))),
          const SizedBox(height: 12),
          Text('Trình độ nhóm so với mô tả của chủ kèo?',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in HostReputation.accuracyLabels.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _accuracy == e.key,
                  onSelected: (_) => setState(() => _accuracy = e.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Điểm nổi bật (không bắt buộc)',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in HostReputation.positiveTags) _tagChip(t, negative: false),
            for (final t in HostReputation.negativeTags) _tagChip(t, negative: true),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _comment,
            maxLength: 300,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Nhận xét (không bắt buộc)',
              border: OutlineInputBorder(),
            ),
          ),
          Text('Tên của bạn sẽ hiện cùng đánh giá. Bạn có thể sửa trong 7 ngày sau khi kèo kết thúc.',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: ready && !_sending ? _submit : null,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
              label: Text(ready ? 'Gửi đánh giá' : 'Chọn số sao và trình độ'),
            ),
          ),
        ],
      ),
    );
  }
}
