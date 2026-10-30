import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S11: PayOS VietQR Payment Screen (Module 3)
// Thiết kế lại: mã QR là trọng tâm, số tiền lớn, nội dung chuyển khoản có
// nút sao chép, trạng thái "đang chờ" dùng vòng xoay thay cho emoji,
// hướng dẫn 3 bước; nút giả lập webhook tách riêng, ghi rõ là demo.
class S11PayosQrScreen extends StatefulWidget {
  final AppState appState;
  const S11PayosQrScreen({super.key, required this.appState});

  @override
  State<S11PayosQrScreen> createState() => _S11PayosQrScreenState();
}

class _S11PayosQrScreenState extends State<S11PayosQrScreen> {
  bool _simulating = false;

  AppState get appState => widget.appState;

  Future<void> _simulatePayosWebhook(BuildContext context) async {
    if (_simulating) return;
    setState(() => _simulating = true);
    final b = appState.selectedBooking ?? appState.bookings.first;
    final p = appState.activePayosPayment;
    if (p != null && p['payosOrderCode'] != null) {
      try {
        await ApiService.post('/payments/simulate-webhook/${p['payosOrderCode']}', {});
      } catch (_) {}
    }

    b['status'] = 'CONFIRMED';
    b['paymentMethod'] = 'PAYOS_QR';
    appState.bookings.removeWhere((item) => item['bookingCode'] == b['bookingCode']);
    appState.bookings.insert(0, b);

    if (!context.mounted) return;
    appState.pushNotification(
      title: 'Thanh toán VietQR thành công',
      body: 'Đơn #${b['bookingCode']} (${b['courtName']}, ${b['startTime']}-${b['endTime']}) đã được xác nhận.',
      type: 'PAYMENT',
      targetScreen: 'S13',
      context: context,
    );
    // Kết thúc luồng đặt sân: Back từ vé không quay lại màn quét QR
    appState.justPaidBookingCode = b['bookingCode']?.toString();
    appState.completeFlow('S13');
  }

  void _copy(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã sao chép $label'), duration: const Duration(seconds: 2)),
    );
  }

  Widget _copyRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Sao chép $label',
            onPressed: () => _copy(context, label.toLowerCase(), value),
            icon: Icon(Icons.copy_rounded, size: 18, color: cs.primary),
          ),
        ],
      ),
    );
  }

  Widget _stepHint(ThemeData theme, int n, String text) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: cs.secondaryContainer, shape: BoxShape.circle),
            child: Text(
              '$n',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final b = appState.selectedBooking ?? appState.bookings.first;
    final p = appState.activePayosPayment ??
        {'payosOrderCode': 902841, 'qrCodeData': 'VIETQR-PAYOS-${b['bookingCode']}'};
    final total = UiFmt.toNum(b['totalPrice'], 0);

    return ResponsiveCenter(
      maxWidth: Responsive.defaultFormMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context),
        children: [
          const BookingSteps(current: 1),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // [Responsive] Kích thước QR co giãn theo chiều rộng thẻ
                final qrSize = math.min(constraints.maxWidth * 0.62, 220.0).clamp(140.0, 220.0);
                return Column(
                  children: [
                    Text(
                      'Quét mã để thanh toán',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dùng app ngân hàng hoặc ví hỗ trợ VietQR',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        // Nền QR luôn trắng để máy quét đọc được
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.primary, width: 2),
                      ),
                      child: QrImageView(
                        data: p['qrCodeData'].toString(),
                        version: QrVersions.auto,
                        size: qrSize,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Số tiền',
                        style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                    Text(
                      UiFmt.vnd(total),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _copyRow(context, 'Nội dung CK', b['bookingCode'].toString()),
                    const SizedBox(height: 8),
                    _copyRow(context, 'Mã đơn PayOS', '#${p['payosOrderCode']}'),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'Đang chờ xác nhận thanh toán...',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Text('Hướng dẫn',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _stepHint(theme, 1, 'Mở app ngân hàng, chọn Quét mã QR.'),
          _stepHint(theme, 2, 'Quét mã phía trên, giữ nguyên số tiền và nội dung chuyển khoản.'),
          _stepHint(theme, 3, 'Giữ màn hình này mở. Vé sẽ tự hiện khi thanh toán thành công.'),
          const SizedBox(height: 20),

          // Khu vực demo: tách riêng để không nhầm với luồng thật
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.science_outlined, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      'Chế độ demo',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _simulating ? null : () => _simulatePayosWebhook(context),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  icon: _simulating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bolt),
                  label: const Text('Giả lập Webhook PayOS thành công'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
