import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/booking_rules.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S22: Owner QR Check-in Scanner Screen (Luồng 2)
// Giao diện theo design system + sửa logic: trước đây nhập mã BẤT KỲ cũng báo
// "check-in thành công". Giờ mã được tra trong danh sách vé, kiểm tra trạng thái
// (đã hủy / đã check-in / chưa thanh toán / không đúng ngày) và hiện kết quả rõ ràng.
// Quét bằng camera (mobile_scanner) trên Android / iOS / macOS / Web; quét được thì tự kiểm tra mã.
// Máy không có camera (Windows, Linux) hoặc bị từ chối quyền: vẫn nhập mã tay như cũ.
class S22QrCheckInScannerScreen extends StatefulWidget {
  final AppState appState;
  const S22QrCheckInScannerScreen({super.key, required this.appState});

  @override
  State<S22QrCheckInScannerScreen> createState() => _S22QrCheckInScannerScreenState();
}

class _S22QrCheckInScannerScreenState extends State<S22QrCheckInScannerScreen> {
  final _codeCtrl = TextEditingController();
  Map<String, dynamic>? _found;
  String? _error;
  bool _busy = false;
  bool _checking = false;

  /// Camera chỉ có trên điện thoại, macOS và trình duyệt.
  static bool get _cameraSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  MobileScannerController? _scanner;
  bool _scanPaused = false;

  AppState get _app => widget.appState;

  @override
  void initState() {
    super.initState();
    if (_cameraSupported) {
      _scanner = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        formats: const [BarcodeFormat.qrCode],
      );
    }
  }

  @override
  void dispose() {
    _scanner?.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  /// Camera đọc được mã: dừng quét, điền mã và kiểm tra luôn.
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanPaused || _checking) return;
    final value = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (value.isEmpty) return;
    setState(() => _scanPaused = true);
    HapticFeedback.mediumImpact();
    await _scanner?.stop();
    _codeCtrl.text = value;
    await _verify();
  }

  /// Quét vé khác.
  Future<void> _scanAgain() async {
    setState(() {
      _scanPaused = false;
      _found = null;
      _error = null;
      _codeCtrl.clear();
    });
    await _scanner?.start();
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

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Hãy quét mã QR hoặc nhập mã vé.');
      return;
    }
    var b = _lookup(code);
    if (b == null) {
      // Vé vừa được đặt ở máy khác: tải lại danh sách vé của chủ sân rồi tìm lại
      setState(() => _checking = true);
      try {
        await _app.refreshOwnerDashboard();
      } catch (e) {
        debugPrint('[S22] $e');
      }
      if (!mounted) return;
      b = _lookup(code);
    }
    setState(() {
      _checking = false;
      _found = b;
      _error = b == null ? 'Không tìm thấy vé với mã "$code".' : _invalidReason(b);
    });
  }

  Widget _cameraBox(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final scanner = _scanner;

    Widget placeholder(IconData icon, String text) => Container(
          color: cs.inverseSurface,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: cs.inversePrimary, size: 56),
              const SizedBox(height: 10),
              Text(text,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onInverseSurface)),
            ],
          ),
        );

    final Widget content;
    if (scanner == null) {
      content = placeholder(Icons.qr_code_scanner, 'Máy này không có camera. Nhập mã vé bên dưới.');
    } else if (_scanPaused) {
      content = placeholder(Icons.check_circle_outline, 'Đã đọc mã. Bấm "Quét vé khác" để quét tiếp.');
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: scanner,
            onDetect: _onDetect,
            errorBuilder: (context, error) => placeholder(
              Icons.no_photography_outlined,
              error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'Chưa cấp quyền camera. Mở Cài đặt để cho phép, hoặc nhập mã bên dưới.'
                  : 'Không mở được camera. Nhập mã vé bên dưới.',
            ),
          ),
          // Khung ngắm
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.7,
              heightFactor: 0.7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Đèn flash',
                  color: Colors.white,
                  onPressed: () => scanner.toggleTorch(),
                  icon: ValueListenableBuilder<MobileScannerState>(
                    valueListenable: scanner,
                    builder: (_, state, __) =>
                        Icon(state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off),
                  ),
                ),
                IconButton(
                  tooltip: 'Đổi camera',
                  color: Colors.white,
                  onPressed: () => scanner.switchCamera(),
                  icon: const Icon(Icons.cameraswitch_outlined),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.primary, width: 3),
            ),
            clipBehavior: Clip.antiAlias,
            child: content,
          ),
        ),
      ),
    );
  }

  Future<void> _confirmCheckIn() async {
    final b = _found;
    if (b == null || _error != null || _busy) return;
    setState(() => _busy = true);
    final Json res;
    try {
      res = await Repos.booking.checkIn(_codeCtrl.text.trim());
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showApiError(context, e);
      return;
    }
    b.addAll(asJson(res['booking']));
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
          _cameraBox(context),
          if (_scanner != null && !_scanPaused)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Đưa mã QR trên vé của khách vào khung',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
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
              hintText: 'VD: QR-BK-202610',
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

          if (_checking)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
          else if (_error != null)
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
              onPressed: _checking ? null : _verify,
            ),
          if (_scanner != null && _scanPaused) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _scanAgain,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Quét vé khác'),
            ),
          ],
        ],
      ),
    );
  }
}
