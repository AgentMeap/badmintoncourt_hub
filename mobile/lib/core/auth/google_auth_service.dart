import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Cấu hình Firebase đọc lúc build bằng `--dart-define-from-file=config/firebase.json`
/// (xem mobile/config/README_FIREBASE.md). Không cần google-services.json hay plugin Gradle.
class FirebaseConfig {
  FirebaseConfig._();

  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  /// OAuth client loại "Web application" (client_type 3) của project, dùng làm serverClientId
  /// để Google trả về ID token mà Firebase chấp nhận.
  static const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// Đủ cấu hình để khởi tạo Firebase (thông báo đẩy), chưa cần Web client ID của đăng nhập Google.
  static bool get hasCoreOptions =>
      apiKey.isNotEmpty && appId.isNotEmpty && messagingSenderId.isNotEmpty && projectId.isNotEmpty;

  static bool get isComplete =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty &&
      webClientId.isNotEmpty;
}

/// Lỗi đăng nhập Google có câu báo tiếng Việt cho người dùng.
class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Đăng nhập Google -> Firebase Auth -> lấy Firebase ID token để gửi cho backend
/// (POST /api/auth/google). Backend kiểm tra token rồi cấp JWT riêng của app.
class GoogleAuthService {
  GoogleAuthService._();

  static Future<void>? _initializing;

  /// Chỉ hỗ trợ ứng dụng Android (phạm vi đồ án).
  static bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isAvailable => isSupportedPlatform && FirebaseConfig.isComplete;

  static Future<void> _ensureInitialized() => _initializing ??= _initialize();

  static Future<void> _initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: FirebaseConfig.apiKey,
            appId: FirebaseConfig.appId,
            messagingSenderId: FirebaseConfig.messagingSenderId,
            projectId: FirebaseConfig.projectId,
          ),
        );
      }
      await GoogleSignIn.instance.initialize(serverClientId: FirebaseConfig.webClientId);
    } catch (e) {
      _initializing = null; // cho phép thử lại lần sau
      rethrow;
    }
  }

  /// Mở hộp chọn tài khoản Google. Trả về Firebase ID token, hoặc null nếu người dùng hủy.
  static Future<String?> signInAndGetIdToken() async {
    if (!isSupportedPlatform) {
      throw const GoogleAuthException('Đăng nhập Google hiện chỉ hỗ trợ trên ứng dụng Android.');
    }
    if (!FirebaseConfig.isComplete) {
      throw const GoogleAuthException(
          'Ứng dụng chưa được cấu hình Firebase. Xem hướng dẫn trong mobile/config/README_FIREBASE.md.');
    }
    try {
      await _ensureInitialized();
      final account = await GoogleSignIn.instance.authenticate();
      final googleIdToken = account.authentication.idToken;
      if (googleIdToken == null) {
        throw const GoogleAuthException('Google không trả về mã xác thực. Vui lòng thử lại.');
      }
      final credential = GoogleAuthProvider.credential(idToken: googleIdToken);
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      final idToken = await result.user?.getIdToken();
      if (idToken == null) {
        throw const GoogleAuthException('Không lấy được phiên đăng nhập Firebase. Vui lòng thử lại.');
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      // Lưu ý: SHA-1 / Web client ID cấu hình sai trên Android cũng báo về dạng "canceled"
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      debugPrint('[GoogleAuth] ${e.code}: ${e.description}');
      throw const GoogleAuthException(
          'Không đăng nhập được bằng Google. Kiểm tra kết nối mạng và cấu hình SHA-1 / Web client ID.');
    } on FirebaseAuthException catch (e) {
      debugPrint('[GoogleAuth] Firebase ${e.code}: ${e.message}');
      throw GoogleAuthException(e.code == 'network-request-failed'
          ? 'Không có kết nối mạng, vui lòng thử lại.'
          : 'Firebase từ chối đăng nhập (${e.code}).');
    } on GoogleAuthException {
      rethrow;
    } catch (e) {
      debugPrint('[GoogleAuth] $e');
      throw const GoogleAuthException('Không đăng nhập được bằng Google, vui lòng thử lại.');
    }
  }

  /// Đăng xuất khỏi Firebase + Google (để lần sau được chọn lại tài khoản).
  static Future<void> signOut() async {
    if (_initializing == null) return;
    try {
      await _initializing;
      await FirebaseAuth.instance.signOut();
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      debugPrint('[GoogleAuth] signOut: $e');
    }
  }
}
