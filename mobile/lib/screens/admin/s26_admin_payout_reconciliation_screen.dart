import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S26: Admin Payout & Reconciliation Screen (Luồng 3)
// Giao diện theo design system + bổ sung logic:
// - Xác nhận đã chuyển khoản có hộp thoại xác nhận
// - "Từ chối" bắt buộc nhập lý do; máy chủ trả doanh thu lại cho chủ sân gửi yêu cầu mới
// - Lọc Chờ duyệt / Đã xử lý, số tiền định dạng tiền Việt
class S26AdminPayoutReconciliationScreen extends StatefulWidget {
  final AppState appState;
  const S26AdminPayoutReconciliationScreen({super.key, required this.appState});

  @override
  State<S26AdminPayoutReconciliationScreen> createState() => _S26AdminPayoutReconciliationScreenState();
}

class _S26AdminPayoutReconciliationScreenState extends State<S26AdminPayoutReconciliationScreen> {
  bool _showPending = true;

  final Set<Object?> _busy = {};

  @override
  void initState() {
    super.initState();
    widget.appState.refreshAdminDashboard().catchError((Object e) => debugPrint('[S26] $e'));
  }

  Future<String?> _askReason(Map<String, dynamic> pr) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Từ chối yêu cầu #${pr['payoutCode']}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Doanh thu được trả lại để chủ sân gửi yêu cầu mới.'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: 300,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setLocal(() {}),
                decoration: const InputDecoration(
                  hintText: 'Lý do (VD: sai tên chủ tài khoản...)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: ctrl.text.trim().isEmpty ? null : () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Từ chối'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _decide(Map<String, dynamic> pr, String decision) async {
    if (_busy.contains(pr['id'])) return;
    final paid = decision == 'PAID';
    final net = UiFmt.vnd(UiFmt.toNum(pr['netPayoutAmount'], 0));
    String? reason;
    if (paid) {
      final ok = await confirmAction(
        context,
        title: 'Xác nhận đã chuyển khoản?',
        message: 'Xác nhận đã chuyển $net tới ${pr['bankName']} • ${pr['bankAccountNumber']} (${pr['bankAccountHolder']}).',
        confirmLabel: 'Đã chuyển khoản',
      );
      if (!ok) return;
    } else {
      reason = await _askReason(pr);
      if (reason == null) return;
    }
    if (!mounted || pr['status'] != 'PENDING') return;

    setState(() => _busy.add(pr['id']));
    final Json saved;
    try {
      saved = await Repos.admin.updatePayoutStatus(pr['id'], decision, reason: reason);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(pr['id']));
      showApiError(context, e);
      // 409: yêu cầu đã được xử lý ở nơi khác -> tải lại trạng thái thật
      widget.appState.refreshAdminDashboard().catchError((Object e) => debugPrint('[S26] $e'));
      return;
    }

    if (!mounted) return;
    setState(() {
      _busy.remove(pr['id']);
      pr.addAll(saved);
      pr['status'] = decision;
    });
    widget.appState.refreshAdminDashboard().catchError((Object e) => debugPrint('[S26] $e'));
    widget.appState.pushNotification(
      title: paid ? 'Đã giải ngân #${pr['payoutCode']}' : 'Đã từ chối yêu cầu #${pr['payoutCode']}',
      body: paid ? 'Đã chuyển $net cho chủ sân.' : 'Chủ sân có thể kiểm tra lại và gửi yêu cầu mới.',
      type: 'PAYMENT',
      targetScreen: 'S23',
      context: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final all = widget.appState.payoutRequests;
    final pending = all.where((p) => p['status'] == 'PENDING').toList();
    final done = all.where((p) => p['status'] != 'PENDING').toList();
    final shown = _showPending ? pending : done;

    return ResponsiveCenter(
      maxWidth: Responsive.defaultContentMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context),
        children: [
          Text('Duyệt giải ngân',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text('Chờ duyệt (${pending.length})')),
                ButtonSegment(value: false, label: Text('Đã xử lý (${done.length})')),
              ],
              selected: {_showPending},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _showPending = s.first),
            ),
          ),
          const SizedBox(height: 16),
          if (shown.isEmpty)
            EmptyState(
              icon: Icons.task_alt,
              title: _showPending ? 'Không có yêu cầu chờ duyệt' : 'Chưa có yêu cầu đã xử lý',
            )
          else
            for (final pr in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('#${pr['payoutCode']}',
                                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                Text('${pr['venueName']} • ${pr['ownerName']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _statusBadge(theme, pr['status']?.toString()),
                        ],
                      ),
                      const SizedBox(height: 8),
                      InfoRow(
                          icon: Icons.receipt_long_outlined,
                          label: 'Doanh thu thu hộ',
                          value: UiFmt.vnd(UiFmt.toNum(pr['grossAmount'], 0))),
                      InfoRow(
                          icon: Icons.percent,
                          label: 'Phí nền tảng',
                          value: '-${UiFmt.vnd(UiFmt.toNum(pr['commissionFee'], 0))}'),
                      InfoRow(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'Thực chi',
                          value: UiFmt.vnd(UiFmt.toNum(pr['netPayoutAmount'], 0)),
                          emphasize: true),
                      Divider(height: 16, color: cs.outlineVariant),
                      InfoRow(
                          icon: Icons.account_balance_outlined,
                          label: '${pr['bankName']}',
                          value: '${pr['bankAccountNumber']} • ${pr['bankAccountHolder']}'),
                      if (pr['status'] == 'PENDING') ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _decide(pr, 'REJECTED'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  foregroundColor: cs.error,
                                  side: BorderSide(color: cs.error.withValues(alpha: 0.6)),
                                ),
                                child: const Text('Từ chối'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                onPressed: () => _decide(pr, 'PAID'),
                                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                                icon: const Icon(Icons.check_circle_outline, size: 18),
                                label: const Text('Đã chuyển khoản', maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _statusBadge(ThemeData theme, String? s) {
    final cs = theme.colorScheme;
    final (label, icon, bg, fg) = switch (s) {
      'PAID' || 'APPROVED' => ('Đã chuyển', Icons.check_circle_outline, cs.primaryContainer, cs.onPrimaryContainer),
      'REJECTED' => ('Từ chối', Icons.block, cs.errorContainer, cs.onErrorContainer),
      _ => ('Chờ duyệt', Icons.hourglass_top_rounded, WarningTone.container(cs), WarningTone.onContainer(cs)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text.rich(
        TextSpan(children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(padding: const EdgeInsets.only(right: 4), child: Icon(icon, size: 14, color: fg)),
          ),
          TextSpan(text: label),
        ]),
        style: theme.textTheme.labelMedium?.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }
}
