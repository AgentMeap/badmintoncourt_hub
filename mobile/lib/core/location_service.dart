import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Trạng thái lấy vị trí GPS của người dùng.
enum LocationStatus {
  /// Chưa thử lấy vị trí.
  unknown,

  /// Đã có vị trí thật.
  available,

  /// Điện thoại đang tắt dịch vụ vị trí (GPS).
  serviceDisabled,

  /// Người dùng từ chối quyền vị trí (lần sau vẫn hỏi lại được).
  denied,

  /// Người dùng chọn "Không hỏi lại": phải mở Cài đặt để cấp quyền.
  deniedForever,

  /// Có quyền nhưng không đọc được vị trí (hết thời gian chờ, thiết bị không hỗ trợ...).
  unavailable,
}

class LocationResult {
  const LocationResult(this.status, {this.latitude, this.longitude});
  final LocationStatus status;
  final double? latitude;
  final double? longitude;
}

/// Lấy vị trí GPS hiện tại (package geolocator). Không bao giờ ném lỗi:
/// mọi trường hợp không có vị trí đều trả về [LocationResult] với trạng thái tương ứng.
class LocationService {
  LocationService._();

  /// Vị trí mặc định khi chưa có GPS: Nhà Văn hóa Sinh viên ĐHQG TP.HCM (Làng Đại học).
  static const double defaultLatitude = 10.8753;
  static const double defaultLongitude = 106.8000;

  static Future<LocationResult> current({bool askPermission = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(LocationStatus.serviceDisabled);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && askPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult(LocationStatus.deniedForever);
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.unableToDetermine) {
        return const LocationResult(LocationStatus.denied);
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } catch (e) {
        debugPrint('[location] $e');
        // Hết thời gian chờ (trong nhà, GPS yếu): dùng vị trí gần nhất máy còn nhớ
        if (!kIsWeb) position = await Geolocator.getLastKnownPosition();
      }
      if (position == null) return const LocationResult(LocationStatus.unavailable);
      return LocationResult(LocationStatus.available,
          latitude: position.latitude, longitude: position.longitude);
    } catch (e) {
      // Thiết bị / nền tảng không hỗ trợ (VD chạy test, desktop chưa cấu hình)
      debugPrint('[location] $e');
      return const LocationResult(LocationStatus.unavailable);
    }
  }

  /// Mở đúng màn Cài đặt để người dùng bật GPS hoặc cấp lại quyền.
  static Future<void> openSettings(LocationStatus status) async {
    try {
      if (status == LocationStatus.serviceDisabled) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (e) {
      debugPrint('[location] $e');
    }
  }

  /// Câu giải thích ngắn cho từng trạng thái (hiện trên bản đồ / trang chủ).
  static String describe(LocationStatus status) => switch (status) {
        LocationStatus.available => 'Đang dùng vị trí của bạn',
        LocationStatus.serviceDisabled => 'GPS đang tắt. Đang tính khoảng cách từ Làng Đại học.',
        LocationStatus.denied ||
        LocationStatus.deniedForever =>
          'Chưa cấp quyền vị trí. Đang tính khoảng cách từ Làng Đại học.',
        LocationStatus.unavailable => 'Chưa xác định được vị trí. Đang tính từ Làng Đại học.',
        LocationStatus.unknown => 'Đang xác định vị trí...',
      };
}
