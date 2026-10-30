import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S18: Customer Profile & In-App Wallet Screen
// Giao diện theo design system: thẻ ví màu primary của Theme, số dư định dạng
// tiền Việt, thao tác nhanh dạng ô icon, lịch sử giao dịch có icon theo loại,
// đăng xuất có hộp thoại xác nhận.
class S18ProfileWalletScreen extends StatelessWidget {
  final AppState appState;
  const S18ProfileWalletScreen({super.key, required this.appState});

  static (IconData, String) _txMeta(String? type, bool positive) {
    switch (type) {
      case 'REFUND':
        return (Icons.replay_rounded, 'Hoàn tiền');
      case 'BOOKING_PAYMENT':
        return (Icons.sports_tennis, 'Thanh toán đặt sân');
      case 'TOPUP':
        return (Icons.add_card_outlined, 'Nạp tiền');
      case 'WITHDRAW':
        return (Icons.account_balance_outlined, 'Rút tiền');
      default:
        return (positive ? Icons.south_west_rounded : Icons.north_east_rounded, 'Giao dịch');
    }
  }

  static String _clean(String raw) =>
      raw.replaceFirst(RegExp(r'^[^\p{L}\p{N}#\[(]+', unicode: true), '').trim();

  Widget _quickAction(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Expanded(
      child: Material(
        color: cs.onPrimary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Column(
              children: [
                Icon(icon, color: cs.onPrimary),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await confirmAction(
      context,
      title: 'Đăng xuất?',
      message: 'Bạn sẽ quay về màn hình đăng nhập. Có thể chọn vai trò khác để demo.',
      confirmLabel: 'Đăng xuất',
    );
    if (ok) appState.resetTo('S01');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final name = appState.fullName.split('(').first.trim();
    final txs = appState.walletTransactions;

    return ResponsiveCenter(
      maxWidth: Responsive.defaultContentMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context),
        children: [
          // Hồ sơ
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.person, color: cs.onPrimaryContainer, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text(appState.email,
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
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
                      SkillLevel.label(appState.skillLevel),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onTertiaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Sửa hồ sơ',
                onPressed: () => appState.goTo('S29'),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Thẻ ví
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        size: 18, color: cs.onPrimary.withValues(alpha: 0.85)),
                    const SizedBox(width: 6),
                    Text(
                      'Số dư Ví Cầu Lông',
                      style: theme.textTheme.labelLarge?.copyWith(color: cs.onPrimary.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    UiFmt.vnd(appState.walletBalance),
                    style: theme.textTheme.displaySmall?.copyWith(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _quickAction(context, Icons.sports_tennis, 'Đặt sân', () => appState.goToTab('S06', 'S06')),
                    const SizedBox(width: 8),
                    _quickAction(context, Icons.confirmation_number_outlined, 'Vé của tôi',
                        () => appState.goToTab('S12', 'S06')),
                    const SizedBox(width: 8),
                    // Mở màn nhập số tiền & tài khoản trước, OTP sau (S27 -> S03)
                    _quickAction(context, Icons.account_balance_outlined, 'Rút tiền',
                        () => appState.goTo('S27')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          SectionHeader('Lịch sử giao dịch', trailing: Text('${txs.length}',
              style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant))),
          if (txs.isEmpty)
            const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Chưa có giao dịch',
              message: 'Thanh toán và hoàn tiền qua Ví sẽ hiện ở đây.',
            )
          else
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < txs.length; i++) ...[
                    if (i > 0) Divider(height: 1, indent: 64, color: cs.outlineVariant),
                    Builder(builder: (context) {
                      final tx = txs[i];
                      final amt = UiFmt.toNum(tx['amount'], 0);
                      final pos = amt >= 0;
                      final (icon, typeLabel) = _txMeta(tx['type']?.toString(), pos);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: pos ? cs.primaryContainer : cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(icon, size: 20, color: pos ? cs.onPrimaryContainer : cs.onSurfaceVariant),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _clean(tx['title']?.toString() ?? typeLabel),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    '$typeLabel • ${tx['createdAt'] ?? ''}',
                                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${pos ? '+' : '-'}${UiFmt.vnd(amt.abs())}',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: pos ? cs.primary : cs.error,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _logout(context),
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            icon: const Icon(Icons.logout),
            label: const Text('Đăng xuất / đổi vai trò'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
