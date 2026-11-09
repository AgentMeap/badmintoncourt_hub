import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// Lớp gọi HTTP duy nhất của app:
/// - tự gắn `Authorization: Bearer <token>` khi đã đăng nhập,
/// - timeout thống nhất,
/// - chuyển mọi lỗi (mạng, timeout, 4xx, 5xx, dữ liệu hỏng) thành [ApiException],
/// - gọi [onUnauthorized] khi máy chủ báo phiên hết hạn (401) để app tự đăng xuất.
///
/// Màn hình không gọi trực tiếp lớp này mà đi qua các repository trong `core/repositories/`.
class ApiClient {
  ApiClient({http.Client? httpClient, this.timeout = const Duration(seconds: 10)})
      : _http = httpClient ?? http.Client();

  /// Dùng chung toàn app.
  static final ApiClient instance = ApiClient();

  final http.Client _http;
  final Duration timeout;

  String? _token;

  /// Gọi khi một request có token bị trả 401 (token hết hạn / bị thu hồi).
  VoidCallback? onUnauthorized;

  /// Địa chỉ API. Android emulator truy cập máy tính qua 10.0.2.2.
  static String get baseUrl {
    if (kIsWeb) return 'http://localhost:8080/api';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080/api';
    }
    return 'http://localhost:8080/api';
  }

  /// Gốc máy chủ (không có /api), dùng cho file tĩnh như video đã tải lên.
  static String get origin => baseUrl.replaceFirst(RegExp(r'/api/?$'), '');

  String? get token => _token;
  set token(String? value) => _token = (value == null || value.isEmpty) ? null : value;
  bool get hasToken => _token != null;

  /// Header chuẩn; [json] = có thân JSON.
  Map<String, String> headers({bool json = false}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json; charset=utf-8',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Uri uri(String path, [Map<String, Object?>? query]) {
    final base = Uri.parse('$baseUrl$path');
    final params = <String, String>{
      for (final e in (query ?? const <String, Object?>{}).entries)
        if (e.value != null) e.key: '${e.value}',
    };
    return params.isEmpty ? base : base.replace(queryParameters: {...base.queryParameters, ...params});
  }

  Future<dynamic> get(String path, {Map<String, Object?>? query}) =>
      send('GET', path, query: query);

  Future<dynamic> post(String path, [Object? body]) =>
      send('POST', path, body: body ?? const <String, dynamic>{});

  Future<dynamic> put(String path, [Object? body]) =>
      send('PUT', path, body: body ?? const <String, dynamic>{});

  Future<dynamic> patch(String path, [Object? body]) =>
      send('PATCH', path, body: body ?? const <String, dynamic>{});

  Future<dynamic> delete(String path, {Map<String, Object?>? query}) =>
      send('DELETE', path, query: query);

  static const _publicAuthPaths = {
    '/auth/login',
    '/auth/register',
    '/auth/google',
    '/auth/send-otp',
    '/auth/verify-otp',
    '/auth/reset-password',
  };

  /// Gửi request và trả về JSON đã giải mã (Map / List / null khi thân rỗng).
  Future<dynamic> send(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
  }) async {
    final request = http.Request(method, uri(path, query))
      ..headers.addAll(headers(json: body != null));
    if (body != null) request.body = jsonEncode(body);
    final sentWithToken = _token != null;

    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw ApiException.timeout();
    } catch (e) {
      // ClientException, SocketException, lỗi trình duyệt (CORS/mất mạng)...
      debugPrint('[ApiClient] $method $path -> $e');
      throw ApiException.network();
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return _decode(response, strict: true);
    }

    final decoded = _decode(response, strict: false);
    // 401 ở API cần đăng nhập = token hết hạn / bị thu hồi -> đăng xuất.
    // 401 ở API đăng nhập (sai mật khẩu, token Google sai) chỉ là báo lỗi.
    if (status == 401 && sentWithToken && !_publicAuthPaths.contains(path)) {
      onUnauthorized?.call();
    }
    throw ApiException.fromStatus(status, _errorMessageOf(decoded));
  }

  /// [strict]: phản hồi thành công mà không phải JSON hợp lệ -> lỗi invalidResponse.
  dynamic _decode(http.Response response, {required bool strict}) {
    try {
      final text = utf8.decode(response.bodyBytes);
      if (text.trim().isEmpty) return null;
      return jsonDecode(text);
    } on FormatException {
      if (strict) throw ApiException.invalidResponse(response.statusCode);
      return null;
    }
  }

  static String? _errorMessageOf(dynamic decoded) {
    if (decoded is Map) {
      for (final key in const ['error', 'message', 'detail']) {
        final v = decoded[key];
        if (v is String && v.trim().isNotEmpty) return v;
      }
    }
    if (decoded is String && decoded.trim().isNotEmpty && decoded.length < 300) return decoded;
    return null;
  }
}
