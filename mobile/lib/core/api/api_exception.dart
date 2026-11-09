/// Loại lỗi khi gọi API, để màn hình quyết định cách xử lý
/// (VD: lỗi mạng thì cho thử lại, 409 thì chọn khung giờ khác).
enum ApiErrorKind {
  /// Không kết nối được máy chủ (backend chưa chạy, mất mạng, sai địa chỉ).
  network,

  /// Máy chủ phản hồi quá lâu.
  timeout,

  /// 400 - dữ liệu gửi lên không hợp lệ hoặc vi phạm nghiệp vụ.
  badRequest,

  /// 401 - chưa đăng nhập hoặc phiên đã hết hạn.
  unauthorized,

  /// 403 - không có quyền (VD tài khoản bị khóa).
  forbidden,

  /// 404 - không tìm thấy dữ liệu.
  notFound,

  /// 409 - xung đột dữ liệu (VD khung giờ vừa có người đặt).
  conflict,

  /// 429 - gửi quá nhiều yêu cầu.
  tooManyRequests,

  /// 5xx - lỗi phía máy chủ.
  server,

  /// Máy chủ trả về dữ liệu không đọc được.
  invalidResponse,
}

/// Lỗi thống nhất cho mọi lời gọi API. [message] luôn là câu tiếng Việt
/// hiển thị được ngay cho người dùng.
class ApiException implements Exception {
  const ApiException(this.kind, this.message, {this.statusCode});

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;

  /// Lỗi do không tới được máy chủ (khác với máy chủ từ chối yêu cầu).
  bool get isConnectivity => kind == ApiErrorKind.network || kind == ApiErrorKind.timeout;

  static const _networkMessage =
      'Không kết nối được máy chủ. Hãy kiểm tra backend đã chạy và kết nối mạng.';
  static const _timeoutMessage = 'Máy chủ phản hồi quá lâu, vui lòng thử lại.';

  factory ApiException.network() =>
      const ApiException(ApiErrorKind.network, _networkMessage);

  factory ApiException.timeout() =>
      const ApiException(ApiErrorKind.timeout, _timeoutMessage);

  factory ApiException.invalidResponse([int? statusCode]) => ApiException(
        ApiErrorKind.invalidResponse,
        'Máy chủ trả về dữ liệu không hợp lệ.',
        statusCode: statusCode,
      );

  /// Tạo lỗi từ mã HTTP. Ưu tiên câu báo lỗi do backend gửi về (trường "error").
  factory ApiException.fromStatus(int statusCode, String? serverMessage) {
    final kind = switch (statusCode) {
      400 || 422 => ApiErrorKind.badRequest,
      401 => ApiErrorKind.unauthorized,
      403 => ApiErrorKind.forbidden,
      404 => ApiErrorKind.notFound,
      409 => ApiErrorKind.conflict,
      429 => ApiErrorKind.tooManyRequests,
      >= 500 => ApiErrorKind.server,
      _ => ApiErrorKind.badRequest,
    };
    final fallback = switch (kind) {
      ApiErrorKind.unauthorized => 'Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.',
      ApiErrorKind.forbidden => 'Bạn không có quyền thực hiện thao tác này.',
      ApiErrorKind.notFound => 'Không tìm thấy dữ liệu yêu cầu.',
      ApiErrorKind.conflict => 'Dữ liệu vừa thay đổi, vui lòng tải lại và thử lại.',
      ApiErrorKind.tooManyRequests => 'Bạn thao tác quá nhanh, vui lòng thử lại sau ít phút.',
      ApiErrorKind.server => 'Máy chủ đang gặp lỗi, vui lòng thử lại sau.',
      _ => 'Yêu cầu không hợp lệ.',
    };
    final msg = serverMessage?.trim();
    // Câu mặc định của Spring ("Internal Server Error", "Not Found"...) không có ích cho người dùng
    final useServer = msg != null && msg.isNotEmpty && !_springDefaults.contains(msg);
    return ApiException(kind, useServer ? msg : fallback, statusCode: statusCode);
  }

  static const _springDefaults = {
    'Bad Request',
    'Unauthorized',
    'Forbidden',
    'Not Found',
    'Conflict',
    'Internal Server Error',
  };

  /// Câu báo lỗi hiển thị được cho mọi loại lỗi (kể cả lỗi không phải ApiException).
  static String messageOf(Object error,
          [String fallback = 'Đã có lỗi xảy ra, vui lòng thử lại.']) =>
      error is ApiException ? error.message : fallback;

  @override
  String toString() => 'ApiException(${statusCode ?? kind.name}): $message';
}
