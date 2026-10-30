import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static String get baseUrl {
    if (kIsWeb) return 'http://localhost:8080/api';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080/api';
    }
    return 'http://localhost:8080/api';
  }

  static Future<dynamic> get(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await http.get(uri, headers: {'Accept': 'application/json'}).timeout(
      const Duration(seconds: 4),
    );
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      throw Exception(decoded is Map ? (decoded['error'] ?? 'Lỗi kết nối API') : 'Lỗi API');
    }
    return decoded;
  }

  static Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 6));
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      throw Exception(decoded is Map ? (decoded['error'] ?? 'Lỗi xử lý yêu cầu') : 'Lỗi API');
    }
    return decoded;
  }

  static Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$path');
    final res = await http
        .patch(
          uri,
          headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 6));
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      throw Exception(decoded is Map ? (decoded['error'] ?? 'Lỗi cập nhật dữ liệu') : 'Lỗi API');
    }
    return decoded;
  }
}
