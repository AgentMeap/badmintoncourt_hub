import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/booking_rules.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S22: Owner QR Check-in Scanner Screen (Luồng 2)
// Giao diện theo design system + sửa logic: trước đây nhập mã BẤT KỲ cũng báo
// "check-in thành công". Giờ mã được tra trong danh sách vé, kiểm tra trạng thái
// (đã hủy / đã check-in / chưa thanh toán / không đúng ngày) và hiện kết quả rõ ràng.
class S22QrCheckInScannerScreen extends StatefulWidget {
  final AppState appState;
  const S22QrCheckInScannerScreen({super.key, required this.appState});

  @override
  State<S22QrCheckInScannerScreen> createState() => _S22QrCheckInScannerScreenState();
}

class _S22QrCheckInScannerScreenState extends State<S22QrCheckInScannerScreen> {
  final _codeCtrl = TextEditingController(text: 'QR-BK-202610');
  Map<String, dynamic>? _found;
  String? _error;
  bool _busy = false;

  AppState get _app => widget.appState;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _lookup(String code) {
    final c = code.trim().toUpperCase();
    for (final b in _app.bookings) {
      if ('${b['qrCheckInToken']}'.toUpperCase() == c || '${b['bookingCode']}'.toUpperCase() == c) {
        return b;
      }
    }
    return null;
  }

  /// Lý do không thể check-in, null nếu hợp lệ.
  String? _invalidReason(Map<String, dynamic> b) {
    final status = b['status']?.toString();
    if (b['bookingType'] == 'MAINTENANCE') return 'Đây là lịch bảo trì, không phải vé của khách.';
    if (status == 'CANCELLED' || status == 'REFUNDED') return 'Vé đã bị hủy.';
    if (status == 'CHECKED_IN') return 'Vé này đã check-in trước đó.';
    if (!BookingRules.isPaid(b)) return 'Vé chưa được thanh toán.';
    if (b['playDate'] != BookingRules.dateKey(DateTime.now())) {
      return 'Vé dành cho ngày ${UiDate.full(b['playDate']?.toString() ?? '')}, không phải hôm nay.';
    }
    return null;
  }

  void _verify() {
    final b = _lookup(_codeCtrl.text);
    setState(() {
      _found = b;
      _error = b == null ? 'Không tìm thấy vé với mã "${_codeCtrl.text.trim()}".' : _invalidReason(b);
    });
  }

  Future<void> _confirmCheckIn() async {
    final b = _found;
    if (b == null || _error != null || _busy) return;
    setState(() => _busy = true);
    try {
      await ApiService.post('/owner/bookings/check-in', {'code': _codeCtrl.text.trim()});
    } catch (_) {}
    b['status'] = 'CHECKED_IN';

    if (!mounted) return;
    setState(() => _busy = false);
    _app.pushNotification(
      title: 'Check-in nhận sân thành công',
      body: 'Vé #${b['bookingCode']} (${b['courtName']}, ${b['startTime']} - ${b['endTime']}) đã nhận sân.',
      type: 'BOOKING',
      targetScreen: 'S21',
      context: context,
    );
    _app.goTo('S21');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final b = _found;

    return ResponsiveCenter(
      maxWidth: Responsive.defaultFormMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context),
        children: [
          Text('Check-in khách',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          // Khung quét (mô phỏng camera)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.inverseSurface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: cs.primary, width: 3),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_scanner, color: cs.inversePrimary, size: 64),
                      const SizedBox(height: 10),
                      Text(
                        'Đưa mã QR trên vé của khách vào khung',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onInverseSurface),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _codeCtrl,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _verify(),
            onChanged: (_) {
              if (_found != null || _error != null) {
                setState(() {
                  _found = null;
                  _error = null;
                });
              }
            },
            decoration: InputDecoration(
              labelText: 'Mã QR hoặc mã vé',
              prefixIcon: const Icon(Icons.confirmation_number_outlined),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Kiểm tra mã',
                onPressed: _verify,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 12),

          if (_error != null)
            NoteBox(_error!, tone: NoteTone.error)
          else if (b != null)
            SurfaceCard(
              borderColor: cs.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_outlined, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Vé hợp lệ',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
                      ),
                      StatusBadge(status: b['status']?.toString()),
                    ],
                  ),
                  const SizedBox(height: 8),
                  InfoRow(icon: Icons.person_outline, label: 'Khách', value: '${b['customerName'] ?? '-'}'),
                  InfoRow(
                      icon: Icons.schedule,
                      label: 'Giờ',
                      value: '${b['courtName']} • ${b['startTime']} - ${b['endTime']}'),
                  InfoRow(icon: Icons.tag, label: 'Mã vé', value: '#${b['bookingCode']}'),
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (b != null && _error == null)
            PrimaryButton(
              label: 'Xác nhận nhận sân',
              icon: Icons.how_to_reg_outlined,
              loading: _busy,
              onPressed: _confirmCheckIn,
            )
          else
            PrimaryButton(
              label: 'Kiểm tra mã',
              icon: Icons.search,
              tonal: true,
              onPressed: _verify,
            ),
        ],
      ),
    );
  }
}
