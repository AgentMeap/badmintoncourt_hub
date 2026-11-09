import '../api/api_client.dart';
import '../api/json.dart';

/// Đặt sân, thanh toán, đổi lịch, hủy vé, check-in (`/api/bookings`, `/api/payments`, `/api/owner/bookings`).
class BookingRepository {
  BookingRepository([ApiClient? api]) : _api = api ?? ApiClient.instance;
  final ApiClient _api;

  /// Giữ chỗ 5 phút (HELD). Trùng giờ -> ApiException 409.
  Future<Json> hold({
    required Object venueId,
    required Object courtId,
    required int customerId,
    required String playDate,
    required String startTime,
    required String endTime,
    required num totalPrice,
  }) async =>
      asJson(await _api.post('/bookings/hold', {
        'venueId': venueId,
        'courtId': courtId,
        'customerId': customerId,
        'playDate': playDate,
        'startTime': startTime,
        'endTime': endTime,
        'totalPrice': totalPrice,
      }));

  Future<List<Json>> customerBookings(int customerId) async =>
      asJsonList(await _api.get('/bookings/customer/$customerId'));

  /// `{booking, payment, refunds}`.
  Future<Json> detail(Object bookingId) async => asJson(await _api.get('/bookings/$bookingId'));

  /// Đổi lịch. [totalPrice] = giá khung giờ mới để máy chủ bù/hoàn chênh lệch vào Ví.
  /// Trả về `{booking, walletBalance, priceDifference}`.
  Future<Json> reschedule(
    Object bookingId, {
    required String playDate,
    required String startTime,
    required String endTime,
    Object? courtId,
    num? totalPrice,
  }) async =>
      asJson(await _api.post('/bookings/$bookingId/reschedule', {
        'playDate': playDate,
        'startTime': startTime,
        'endTime': endTime,
        if (courtId != null) 'courtId': courtId,
        if (totalPrice != null) 'totalPrice': totalPrice,
      }));

  /// Hủy vé, máy chủ tự tính % hoàn tiền. Trả về `{booking, refund, walletBalance, message}`.
  Future<Json> cancel(Object bookingId, {String? reason}) async =>
      asJson(await _api.post('/bookings/$bookingId/cancel', {
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      }));

  /// Tạo mã VietQR PayOS cho vé đang giữ chỗ. Trả về `{payment, booking}`.
  Future<Json> createPayos(Object bookingId) async =>
      asJson(await _api.post('/payments/create-payos', {'bookingId': bookingId}));

  /// Giả lập PayOS gọi webhook báo đã thanh toán (dùng khi demo).
  Future<Json> simulatePayosWebhook(Object orderCode) async =>
      asJson(await _api.post('/payments/simulate-webhook/$orderCode'));

  /// Trả bằng Ví nội bộ. Trả về `{booking, walletBalance}`.
  Future<Json> payWithWallet({required Object bookingId, required int userId}) async =>
      asJson(await _api.post('/payments/pay-with-wallet', {'bookingId': bookingId, 'userId': userId}));

  /// Chủ sân ghi nhận khách vãng lai (WALK_IN) hoặc khóa sân bảo trì (MAINTENANCE).
  Future<Json> createWalkIn(Json entry) async =>
      asJson(await _api.post('/owner/bookings/walk-in', entry));

  /// Check-in bằng mã vé hoặc token QR. Trả về `{message, booking}`.
  Future<Json> checkIn(String code) async =>
      asJson(await _api.post('/owner/bookings/check-in', {'code': code}));
}
