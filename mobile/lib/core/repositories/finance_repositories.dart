import '../api/api_client.dart';
import '../api/json.dart';

/// Ví Cầu Lông của người chơi (`/api/wallet`).
class WalletRepository {
  WalletRepository([ApiClient? api]) : _api = api ?? ApiClient.instance;
  final ApiClient _api;

  /// Rút tiền về ngân hàng. Không đủ số dư -> ApiException 400.
  Future<Json> withdraw({
    required int userId,
    required num amount,
    required String bankName,
    required String bankAccountNumber,
    required String bankAccountHolder,
  }) async =>
      asJson(await _api.post('/wallet/withdraw', {
        'userId': userId,
        'amount': amount,
        'bankName': bankName,
        'bankAccountNumber': bankAccountNumber,
        'bankAccountHolder': bankAccountHolder,
      }));
}

/// Chủ sân: tổng quan doanh thu và giải ngân (`/api/owner`).
class OwnerRepository {
  OwnerRepository([ApiClient? api]) : _api = api ?? ApiClient.instance;
  final ApiClient _api;

  /// `{venues, totalGrossRevenue, netRevenue, availableNetPayout, recentBookings, payoutRequests, ...}`.
  Future<Json> dashboard(int ownerId) async => asJson(await _api.get('/owner/$ownerId/dashboard'));

  /// Gửi yêu cầu giải ngân (có xác thực OTP). Trả về PayoutRequest đã lưu.
  Future<Json> createPayoutRequest({
    required int ownerId,
    required Object venueId,
    required num grossAmount,
    required String bankName,
    required String bankAccountNumber,
    required String bankAccountHolder,
    required String otpCode,
  }) async =>
      asJson(await _api.post('/owner/payout-requests', {
        'ownerId': ownerId,
        'venueId': venueId,
        'grossAmount': grossAmount,
        'bankName': bankName,
        'bankAccountNumber': bankAccountNumber,
        'bankAccountHolder': bankAccountHolder,
        'otpCode': otpCode,
      }));
}

/// Quản trị nền tảng (`/api/admin`).
class AdminRepository {
  AdminRepository([ApiClient? api]) : _api = api ?? ApiClient.instance;
  final ApiClient _api;

  /// `{totalGmv, platformCommission, venues, users, payoutRequests, recentPayments, ...}`.
  Future<Json> dashboard() async => asJson(await _api.get('/admin/dashboard'));

  /// Duyệt (APPROVED) / từ chối (REJECTED) cơ sở. Trả về Venue đã cập nhật.
  Future<Json> moderateVenue(Object venueId, String status) async =>
      asJson(await _api.patch('/admin/venues/$venueId/status', {'status': status}));

  Future<Json> toggleUserActive(Object userId) async =>
      asJson(await _api.patch('/admin/users/$userId/toggle-active'));

  /// PAID (đã chuyển khoản) / REJECTED. Trả về PayoutRequest đã cập nhật.
  Future<Json> updatePayoutStatus(Object payoutId, String status) async =>
      asJson(await _api.patch('/admin/payout-requests/$payoutId/status', {'status': status}));
}
