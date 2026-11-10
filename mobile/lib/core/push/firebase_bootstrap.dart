import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../auth/google_auth_service.dart';

/// Khởi tạo Firebase dùng chung (thông báo đẩy + đăng nhập Google), chỉ trên Android.
/// Ưu tiên cấu hình native từ android/app/google-services.json (plugin Gradle google-services);
/// không có thì dùng tham số `--dart-define-from-file=config/firebase.json`.
class FirebaseBootstrap {
  FirebaseBootstrap._();

  static Future<FirebaseApp?>? _initializing;

  static bool get isSupportedPlatform => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Trả về app Firebase mặc định, hoặc null nếu máy / bản build không có cấu hình Firebase.
  static Future<FirebaseApp?> ensure() => _initializing ??= _initialize();

  static Future<FirebaseApp?> _initialize() async {
    if (!isSupportedPlatform) return null;
    if (Firebase.apps.isNotEmpty) return Firebase.app();
    try {
      return await Firebase.initializeApp(); // cấu hình native (google-services.json)
    } catch (_) {
      // Không có google-services.json -> dùng dart-define
    }
    if (!FirebaseConfig.hasCoreOptions) return null;
    try {
      return await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: FirebaseConfig.apiKey,
          appId: FirebaseConfig.appId,
          messagingSenderId: FirebaseConfig.messagingSenderId,
          projectId: FirebaseConfig.projectId,
        ),
      );
    } catch (e) {
      debugPrint('[firebase] $e');
      _initializing = null; // cho phép thử lại
      return null;
    }
  }
}
