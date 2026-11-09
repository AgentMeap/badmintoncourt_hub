import '../api/api_client.dart';
import '../api/json.dart';

/// Đăng nhập, đăng ký, OTP, hồ sơ và ví của người dùng (`/api/auth/...`).
class AuthRepository {
  AuthRepository([ApiClient? api]) : _api = api ?? ApiClient.instance;
  final ApiClient _api;

  /// Trả về phiên đăng nhập: token, id, fullName, email, role, walletBalance...
  Future<Json> login(String email, String password) async =>
      asJson(await _api.post('/auth/login', {'email': email, 'password': password}));

  /// Đăng nhập bằng Firebase ID token (sau khi chọn tài khoản Google). Trả về phiên như [login]
  /// kèm `newUser` = true nếu tài khoản vừa được tạo.
  Future<Json> loginWithGoogle(String firebaseIdToken) async =>
      asJson(await _api.post('/auth/google', {'idToken': firebaseIdToken}));

  /// Tạo tài khoản và gửi OTP xác thực email. Trả về id, email (+ demoOtp khi máy chủ bật chế độ demo).
  /// Chưa có token đăng nhập cho tới khi xác thực OTP.
  Future<Json> register({
    required String fullName,
    required String email,
    required String phone,
    required String password,
    required String role,
    required String skillLevel,
  }) async =>
      asJson(await _api.post('/auth/register', {
        'fullName': fullName,
        'email': email,
        'phone': phone,
        'password': password,
        'role': role,
        'skillLevel': skillLevel,
      }));

  /// Gửi mã OTP. Với WITHDRAW_WALLET / PAYOUT máy chủ gửi tới email của tài khoản đang đăng nhập.
  Future<Json> sendOtp(String email, String purpose) async =>
      asJson(await _api.post('/auth/send-otp', {'email': email, 'purpose': purpose}));

  /// Xác thực email sau đăng ký. Hợp lệ: trả về phiên đăng nhập (có token). Sai mã: ApiException 400.
  Future<Json> verifyRegistrationOtp(String email, String otpCode) async =>
      asJson(await _api.post('/auth/verify-otp', {'email': email, 'otpCode': otpCode}));

  Future<Json> resetPassword({
    required String email,
    required String otpCode,
    required String newPassword,
  }) async =>
      asJson(await _api.post('/auth/reset-password', {
        'email': email,
        'otpCode': otpCode,
        'newPassword': newPassword,
      }));

  /// Hồ sơ + số dư + lịch sử giao dịch Ví (`walletTransactions`).
  Future<Json> profile(int userId) async => asJson(await _api.get('/auth/profile/$userId'));

  Future<Json> updateProfile(int userId, Json changes) async =>
      asJson(await _api.patch('/auth/profile/$userId', changes));

  Future<void> changePassword({
    required int userId,
    required String currentPassword,
    required String newPassword,
  }) =>
      _api.post('/auth/change-password', {
        'userId': userId,
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      });

  Future<Json> topUpWallet(int userId, num amount) async =>
      asJson(await _api.post('/auth/wallet/$userId/topup', {'amount': amount}));
}
