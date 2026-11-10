import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

/// Cọc kèo giao lưu qua ví (dùng chung cho S15, S16, S30).
/// Chính sách giống backend (MatchDepositService): trừ ví khi xin, giữ hộ đến khi kèo kết thúc rồi trả chủ kèo.
class MatchDeposit {
  MatchDeposit._();

  static const policyText = 'Hoàn cọc: bị từ chối / tự hủy đơn khi chưa duyệt / chủ kèo hủy kèo → hoàn đủ. '
      'Đã được duyệt mà tự rời kèo: còn từ 24 giờ → hoàn đủ; 2–24 giờ → hoàn 50%; dưới 2 giờ → mất cọc.';

  /// Giống backend: phí × % rồi làm tròn lên bội số 1.000đ.
  static double amountFor(double fee, int percent) {
    if (percent <= 0 || fee <= 0) return 0;
    return (fee * percent / 100 / 1000).ceilToDouble() * 1000;
  }

  static int percentOf(Map post) => UiFmt.toNum(post['depositPercent'], 0).toInt();

  static double amountOf(Map post) {
    final saved = UiFmt.toNum(post['depositAmount'], -1).toDouble();
    if (saved >= 0) return saved;
    return amountFor(UiFmt.toNum(post['feePerPlayer'], 0).toDouble(), percentOf(post));
  }

  /// "Cọc 50% · 33.000đ" (null nếu kèo không cọc).
  static String? label(Map post) {
    final amount = amountOf(post);
    if (amount <= 0) return null;
    return 'Cọc ${percentOf(post)}% · ${UiFmt.vnd(amount)}';
  }

  /// Trước khi xin vào kèo có cọc: hiện số cọc, số dư trước / sau và chính sách hoàn.
  /// Trả về true nếu người dùng đồng ý trả cọc. Ví không đủ thì có nút Nạp ví (đi S18) và trả về false.
  static Future<bool> confirmJoin(BuildContext context, AppState app, Map post) async {
    final amount = amountOf(post);
    if (amount <= 0) return true;
    final balance = app.walletBalance;
    final enough = balance >= amount;

    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        Widget row(String label, String value, {Color? color, bool bold = false}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
                  Text(value,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: color,
                        fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                      )),
                ],
              ),
            );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Kèo này yêu cầu cọc trước',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${post['title'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              row('Cọc (${percentOf(post)}% chi phí)', UiFmt.vnd(amount), color: cs.primary, bold: true),
              row('Số dư ví hiện tại', UiFmt.vnd(balance)),
              row('Số dư sau khi cọc', enough ? UiFmt.vnd(balance - amount) : 'Không đủ',
                  color: enough ? null : cs.error),
              const SizedBox(height: 8),
              NoteBox(
                'Tiền cọc được giữ hộ, chỉ chuyển cho chủ kèo khi kèo kết thúc. $policyText',
                icon: Icons.verified_user_outlined,
              ),
              const SizedBox(height: 16),
              if (enough)
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'ok'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                  icon: const Icon(Icons.sports_tennis),
                  label: Text('Xin tham gia và cọc ${UiFmt.vnd(amount)}'),
                )
              else
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'topup'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                  icon: const Icon(Icons.add_card_outlined),
                  label: Text('Nạp ví (cần thêm ${UiFmt.vnd(amount - balance)})'),
                ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Để sau')),
            ],
          ),
        );
      },
    );
    if (result == 'topup') app.goTo('S18');
    return result == 'ok';
  }

  /// Lỗi 402 (ví không đủ) khi xin tham gia: báo lỗi kèm nút Nạp ví. Trả về true nếu đã xử lý.
  static bool handleJoinError(BuildContext context, AppState app, Object error) {
    if (error is! ApiException || error.statusCode != 402) return false;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(error.message),
        action: SnackBarAction(label: 'Nạp ví', onPressed: () => app.goTo('S18')),
      ));
    return true;
  }

  /// Hỏi lại trước khi hủy đơn chờ duyệt / tự rời kèo, kèm số tiền cọc được hoàn lấy từ máy chủ.
  static Future<bool> confirmLeave(BuildContext context, Map post, {required bool approved}) async {
    Json? preview;
    if (amountOf(post) > 0) {
      try {
        preview = await Repos.match.leavePreview(post['id']);
      } catch (_) {
        preview = null; // mất mạng: vẫn hỏi, máy chủ sẽ tính đúng khi rời
      }
    }
    if (!context.mounted) return false;
    final refund = UiFmt.toNum(preview?['refundAmount'], 0);
    final forfeit = UiFmt.toNum(preview?['forfeitAmount'], 0);
    final money = preview == null
        ? (amountOf(post) > 0 ? '\n\n$policyText' : '')
        : UiFmt.toNum(preview['deposit'], 0) <= 0
            ? ''
            : '\n\n${preview['rule']}\nHoàn lại: ${UiFmt.vnd(refund)}'
                '${forfeit > 0 ? ' • Mất cọc: ${UiFmt.vnd(forfeit)}' : ''}';
    return confirmAction(
      context,
      title: approved ? 'Rời kèo này?' : 'Hủy đơn xin tham gia?',
      message: (approved
              ? 'Chỗ của bạn sẽ được trả lại và chủ kèo sẽ nhận thông báo.'
              : 'Bạn có thể xin lại sau nếu kèo còn chỗ.') +
          money,
      confirmLabel: approved ? 'Rời kèo' : 'Hủy đơn',
      destructive: forfeit > 0,
    );
  }

  /// Dòng mô tả cọc của tôi trong kèo (S30), null nếu không có cọc.
  static String? myDepositLine(Map? myRequest) {
    if (myRequest == null) return null;
    final amount = UiFmt.toNum(myRequest['depositAmount'], 0);
    if (amount <= 0) return null;
    final refunded = UiFmt.toNum(myRequest['refundedAmount'], 0);
    return switch (myRequest['depositStatus']) {
      'HELD' => 'Đã cọc ${UiFmt.vnd(amount)} qua ví (đang giữ hộ, chuyển cho chủ kèo khi kèo kết thúc).',
      'REFUNDED' => 'Đã hoàn ${UiFmt.vnd(refunded)} cọc vào ví.',
      'PARTIAL' => 'Đã hoàn ${UiFmt.vnd(refunded)} / ${UiFmt.vnd(amount)} cọc.',
      'FORFEITED' => 'Cọc ${UiFmt.vnd(amount)} đã chuyển cho chủ kèo.',
      'RELEASED' => 'Cọc ${UiFmt.vnd(amount)} đã chuyển cho chủ kèo sau khi kèo kết thúc.',
      _ => null,
    };
  }
}
