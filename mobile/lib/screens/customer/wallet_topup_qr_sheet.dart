import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

/// Màn mã VietQR PayOS để nạp Ví Cầu Lông.
/// Tự hỏi máy chủ mỗi 3 giây (GET /wallet/topup/{orderCode}); máy chủ hỏi lại PayOS và chỉ cộng tiền
/// khi đơn đã thanh toán. Trả về true khi đã nạp thành công.
class WalletTopupQrSheet extends StatefulWidget {
  const WalletTopupQrSheet({super.key, required this.order});
  final Map<String, dynamic> order;

  static Future<bool> show(BuildContext context, Map<String, dynamic> order) async {
    final paid = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => WalletTopupQrSheet(order: order),
    );
    return paid == true;
  }

  @override
  State<WalletTopupQrSheet> createState() => _WalletTopupQrSheetState();
}

class _WalletTopupQrSheetState extends State<WalletTopupQrSheet> {
  static const _pollInterval = Duration(seconds: 3);

  late Map<String, dynamic> _order = widget.order;
  Timer? _pollTimer;
  bool _checking = false;
  bool _simulating = false;

  int get _orderCode => (_order['orderCode'] as num).toInt();
  num get _amount => (_order['amount'] as num?) ?? 0;
  String get _status => _order['status']?.toString() ?? 'PENDING';
  bool get _live => _order['live'] == true;
  bool get _canSimulate => _order['canSimulate'] == true;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _check());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      _apply(await Repos.auth.topupStatus(_orderCode));
    } catch (e) {
      debugPrint('[topup] $e');
    } finally {
      _checking = false;
    }
  }

  void _apply(Map<String, dynamic> res) {
    if (!mounted || res.isEmpty) return;
    setState(() => _order = {..._order, ...res});
    if (res['paid'] == true) {
      _pollTimer?.cancel();
      Navigator.of(context).pop(true);
    } else if (_status == 'CANCELLED') {
      _pollTimer?.cancel();
    }
  }

  Future<void> _simulate() async {
    setState(() => _simulating = true);
    try {
      _apply(await Repos.auth.simulateTopup(_orderCode));
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _simulating = false);
    }
  }

  Future<void> _openCheckout() async {
    final url = _order['checkoutUrl']?.toString() ?? '';
    if (url.isEmpty) return;
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không mở được trang thanh toán.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cancelled = _status == 'CANCELLED';
    final qrData = _order['qrCodeData']?.toString() ?? '';
    final qrSize = (MediaQuery.sizeOf(context).width - 120).clamp(180.0, 260.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Quét mã để nạp tiền', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Mở ứng dụng ngân hàng, quét mã VietQR bên dưới. Tiền vào Ví ngay khi PayOS xác nhận.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: qrData.isEmpty
                  ? SizedBox(width: qrSize, height: qrSize)
                  : QrImageView(data: qrData, version: QrVersions.auto, size: qrSize, backgroundColor: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(UiFmt.vnd(_amount),
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
          ),
          const SizedBox(height: 4),
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                Clipboard.setData(ClipboardData(text: '$_orderCode'));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã sao chép mã đơn.')));
              },
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Text('Mã đơn: $_orderCode', style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cancelled ? cs.errorContainer : cs.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                if (cancelled)
                  Icon(Icons.error_outline, color: cs.onErrorContainer)
                else
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    cancelled
                        ? 'Đơn nạp đã hủy hoặc hết hạn. Vui lòng tạo đơn mới.'
                        : 'Đang chờ thanh toán… Mã có hiệu lực ${_order['expireMinutes'] ?? 15} phút.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cancelled ? cs.onErrorContainer : cs.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_live && !cancelled) ...[
            PrimaryButton(
              label: 'Mở trang thanh toán PayOS',
              icon: Icons.open_in_new,
              onPressed: _openCheckout,
            ),
            const SizedBox(height: 8),
          ],
          if (_canSimulate && !cancelled) ...[
            PrimaryButton(
              label: 'Giả lập đã thanh toán (demo)',
              icon: Icons.science_outlined,
              tonal: true,
              loading: _simulating,
              onPressed: _simulating ? null : _simulate,
            ),
            const SizedBox(height: 8),
          ],
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelled ? 'Đóng' : 'Để sau'),
          ),
        ],
      ),
    );
  }
}
