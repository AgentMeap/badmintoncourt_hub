import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'api/api_client.dart';

class ImageUploadException implements Exception {
  final String message;
  const ImageUploadException(this.message);
  @override
  String toString() => message;
}

/// Ảnh cơ sở: chọn từ thư viện (đã thu nhỏ về ~1600px để tải nhanh) và tải lên máy chủ.
/// Máy chủ: `POST {baseUrl}/media/images` (multipart, field `file`) trả `{"url": "/uploads/venues/<tên file>"}`.
class ImageUploadService {
  ImageUploadService._();

  /// Số ảnh tối đa cho một cơ sở.
  static const maxImages = 5;

  /// Chọn nhiều ảnh từ thư viện. Trả về danh sách rỗng nếu người dùng bỏ chọn.
  static Future<List<XFile>> pickImages({int limit = maxImages}) async {
    if (limit <= 0) return const [];
    final files = await ImagePicker().pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    return files.take(limit).toList();
  }

  /// Tải một ảnh lên, trả về đường dẫn trên máy chủ.
  static Future<String> upload(XFile file) async {
    final bytes = await file.readAsBytes();
    final name = file.name.isNotEmpty ? file.name : 'image.jpg';
    final req = http.MultipartRequest('POST', ApiClient.instance.uri('/media/images'))
      ..headers.addAll(ApiClient.instance.headers())
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: name));
    try {
      final res = await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 1)));
      final body = res.body.isEmpty ? null : jsonDecode(res.body);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = body is Map ? body['error']?.toString() : null;
        throw ImageUploadException(msg ?? 'Máy chủ báo lỗi (${res.statusCode}).');
      }
      final url = body is Map ? body['url']?.toString() : null;
      if (url == null || url.isEmpty) throw const ImageUploadException('Máy chủ trả về địa chỉ ảnh không hợp lệ.');
      return url;
    } on ImageUploadException {
      rethrow;
    } on TimeoutException {
      throw const ImageUploadException('Tải ảnh quá lâu, hãy thử lại.');
    } catch (_) {
      throw const ImageUploadException('Không kết nối được máy chủ.');
    }
  }
}
