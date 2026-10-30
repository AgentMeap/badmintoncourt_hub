import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../screens/screens.dart';

/// Thông tin một màn hình: mã, tiêu đề đầy đủ (dùng trong menu demo) và cách tạo widget.
class ScreenEntry {
  final String code;
  final String fullTitle;
  final Widget Function(AppState appState) builder;
  const ScreenEntry(this.code, this.fullTitle, this.builder);

  /// Tiêu đề cho thanh AppBar: bỏ mã "S06 • " và "(Module x)".
  String get shortTitle {
    final raw = fullTitle.contains(' • ') ? fullTitle.substring(fullTitle.indexOf(' • ') + 3) : fullTitle;
    return raw.replaceAll(RegExp(r'\s*\(Module \d+\)'), '').trim();
  }
}

/// BẢNG DUY NHẤT khai báo 26 màn hình.
/// Thêm màn mới: chỉ cần thêm 1 dòng ở đây (và export file màn hình trong screens.dart).
class ScreenRegistry {
  ScreenRegistry._();

  static final List<ScreenEntry> all = [
    ScreenEntry('S01', 'S01 • Đăng nhập hệ thống', (s) => S01LoginScreen(appState: s)),
    ScreenEntry('S02', 'S02 • Đăng ký tài khoản', (s) => S02RegisterScreen(appState: s)),
    ScreenEntry('S03', 'S03 • Xác thực OTP 6 số (Module 4)', (s) => S03OtpVerificationScreen(appState: s)),
    ScreenEntry('S04', 'S04 • Quên mật khẩu OTP', (s) => S04ForgotPasswordScreen(appState: s)),
    ScreenEntry('S05', 'S05 • Trung tâm Thông báo (Module 5)', (s) => S05NotificationsScreen(appState: s)),
    ScreenEntry('S06', 'S06 • Trang chủ & Tìm sân', (s) => S06CustomerHomeScreen(appState: s)),
    ScreenEntry('S07', 'S07 • Bản đồ OpenStreetMap (Module 2)', (s) => S07MapDiscoveryScreen(appState: s)),
    ScreenEntry('S08', 'S08 • Chi tiết Cơ sở cầu lông', (s) => S08VenueDetailScreen(appState: s)),
    ScreenEntry('S09', 'S09 • Lưới chọn Sân & Khung giờ', (s) => S09TimeSlotGridScreen(appState: s)),
    ScreenEntry('S10', 'S10 • Xác nhận & Chọn Thanh toán', (s) => S10CheckoutScreen(appState: s)),
    ScreenEntry('S11', 'S11 • Quét mã VietQR PayOS (Module 3)', (s) => S11PayosQrScreen(appState: s)),
    ScreenEntry('S12', 'S12 • Lịch đặt sân của tôi', (s) => S12MyBookingsScreen(appState: s)),
    ScreenEntry('S13', 'S13 • Vé đặt sân & Mã QR Check-in', (s) => S13BookingDetailQrScreen(appState: s)),
    ScreenEntry('S14', 'S14 • Đổi lịch / Hủy & Hoàn tiền Ví', (s) => S14CancelRescheduleScreen(appState: s)),
    ScreenEntry('S15', 'S15 • Bảng tin Tìm Kèo & Ghép Đội', (s) => S15MatchmakingFeedScreen(appState: s)),
    ScreenEntry('S16', 'S16 • Đăng Kèo Giao Lưu mới', (s) => S16CreateMatchPostScreen(appState: s)),
    ScreenEntry('S17', 'S17 • Trợ lý Chat AI Gemini (Module 6)', (s) => S17AiAssistantChatScreen(appState: s)),
    ScreenEntry('S18', 'S18 • Hồ sơ & Ví Cầu Lông nội bộ', (s) => S18ProfileWalletScreen(appState: s)),
    ScreenEntry('S19', 'S19 • Owner Dashboard & Doanh thu', (s) => S19OwnerDashboardScreen(appState: s)),
    ScreenEntry('S20', 'S20 • Đăng ký Cơ sở & Ghim Map', (s) => S20VenueOnboardingScreen(appState: s)),
    ScreenEntry('S21', 'S21 • Lịch biểu & Khách vãng lai (Walk-in)', (s) => S21OwnerMasterScheduleScreen(appState: s)),
    ScreenEntry('S22', 'S22 • Quét mã QR Check-in khách', (s) => S22QrCheckInScannerScreen(appState: s)),
    ScreenEntry('S23', 'S23 • Đối soát & Yêu cầu Giải ngân', (s) => S23OwnerPayoutScreen(appState: s)),
    ScreenEntry('S24', 'S24 • Admin Platform Dashboard', (s) => S24AdminDashboardScreen(appState: s)),
    ScreenEntry('S25', 'S25 • Kiểm duyệt Cơ sở & Người dùng', (s) => S25AdminModerationScreen(appState: s)),
    ScreenEntry('S26', 'S26 • Đối soát PayOS & Duyệt Payout', (s) => S26AdminPayoutReconciliationScreen(appState: s)),
    ScreenEntry('S27', 'S27 • Rút tiền Ví về Ngân hàng', (s) => S27WalletWithdrawScreen(appState: s)),
    ScreenEntry('S28', 'S28 • Đánh giá sân sau khi chơi', (s) => S28VenueReviewScreen(appState: s)),
    ScreenEntry('S29', 'S29 • Sửa hồ sơ & Đổi mật khẩu', (s) => S29EditProfileScreen(appState: s)),
    ScreenEntry('S30', 'S30 • Chi tiết kèo & Video', (s) => S30MatchDetailScreen(appState: s)),
  ];

  static final Map<String, ScreenEntry> _byCode = {for (final e in all) e.code: e};

  static bool has(String code) => _byCode.containsKey(code);

  /// Màn hình theo mã; mã lạ thì về Trang chủ (S06) như trước đây.
  static ScreenEntry of(String code) => _byCode[code] ?? _byCode['S06']!;

  /// Tiêu đề AppBar; mã lạ thì hiện chính mã đó (giữ nguyên hành vi cũ).
  static String titleOf(String code) => has(code) ? of(code).shortTitle : code;
}
