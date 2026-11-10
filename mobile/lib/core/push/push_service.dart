import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../repositories/repositories.dart';
import 'firebase_bootstrap.dart';

/// Tin đến khi app đang chạy nền / đã đóng: Android tự hiện thông báo (khối "notification" của tin),
/// hàm này chỉ cần khởi tạo Firebase. Phải là hàm cấp cao nhất.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await FirebaseBootstrap.ensure();
}

/// Thông báo đẩy (Firebase Cloud Messaging) – chỉ Android.
/// - Sau khi đăng nhập: xin quyền thông báo (Android 13+), lấy mã thiết bị và gửi lên POST /api/devices.
/// - App đang mở: không hiện thông báo hệ thống, chỉ hỏi máy chủ ngay -> AppShell hiện banner như thường.
/// - Bấm thông báo (app ở nền / đã đóng): mở đúng màn hình qua [AppState.openNotification].
/// - Đăng xuất: bỏ mã thiết bị trên máy chủ để điện thoại không nhận thông báo của tài khoản cũ.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  static bool get isSupported => FirebaseBootstrap.isSupportedPlatform;

  /// Gọi trong main() trước runApp.
  static void registerBackgroundHandler() {
    if (isSupported) FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  }

  AppState? _app;
  bool _listening = false;
  String? _token;
  int? _registeredUserId;

  /// Thông báo được bấm lúc chưa đăng nhập xong (mở app từ trạng thái đã đóng) -> mở sau khi đăng nhập.
  Map<String, dynamic>? _pendingOpen;

  /// Gọi khi app khởi động / sau đăng nhập / mỗi lần hỏi thông báo. Chỉ đăng ký lại khi đổi tài khoản.
  Future<void> syncRegistration(AppState app) async {
    if (!isSupported) return;
    _app = app;
    try {
      final firebase = await FirebaseBootstrap.ensure();
      if (firebase == null) return;
      final messaging = FirebaseMessaging.instance;
      _listen(messaging);
      if (!ApiClient.instance.hasToken || app.currentScreen == 'S01') return;

      final pending = _pendingOpen;
      if (pending != null) {
        _pendingOpen = null;
        app.openNotification(pending);
      }
      if (_registeredUserId == app.userId && _token != null) return;

      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token == null) return;
      await Repos.device.register(token);
      _token = token;
      _registeredUserId = app.userId;
    } catch (e) {
      debugPrint('[push] $e');
    }
  }

  void _listen(FirebaseMessaging messaging) {
    if (_listening) return;
    _listening = true;
    messaging.onTokenRefresh.listen((t) async {
      _token = t;
      if (!ApiClient.instance.hasToken) return;
      try {
        await Repos.device.register(t);
      } catch (e) {
        debugPrint('[push] $e');
      }
    });
    // App đang mở: hỏi máy chủ ngay để AppShell hiện banner (không chờ tới lượt hỏi 30 giây)
    FirebaseMessaging.onMessage.listen((_) => _app?.pollNotifications());
    // Bấm thông báo khi app chạy nền
    FirebaseMessaging.onMessageOpenedApp.listen(_open);
    // Bấm thông báo khi app đã đóng
    messaging.getInitialMessage().then((m) {
      if (m != null) _open(m);
    });
  }

  void _open(RemoteMessage message) {
    final d = message.data;
    final n = <String, dynamic>{
      'id': int.tryParse('${d['id'] ?? ''}') ?? d['id'],
      'title': d['title'] ?? message.notification?.title,
      'body': d['body'] ?? message.notification?.body,
      'type': d['type'],
      'targetScreen': d['targetScreen'],
      'referenceId': int.tryParse('${d['referenceId'] ?? ''}'),
      'isRead': false,
    };
    final app = _app;
    if (app == null || !ApiClient.instance.hasToken || app.currentScreen == 'S01') {
      _pendingOpen = n; // mở sau khi đăng nhập xong
      return;
    }
    app.openNotification(n);
  }

  /// Bỏ mã thiết bị trên máy chủ (gọi khi đăng xuất, trước khi xoá token đăng nhập).
  Future<void> unregister() async {
    final token = _token;
    _token = null; // tránh gọi lại khi lệnh bỏ mã bị 401 (đăng xuất do hết phiên)
    _registeredUserId = null;
    if (!isSupported || token == null || !ApiClient.instance.hasToken) return;
    try {
      await Repos.device.unregister(token).timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[push] $e');
    }
  }
}
