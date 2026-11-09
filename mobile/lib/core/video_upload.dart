import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'api/api_client.dart';
import 'video_link.dart';
import 'video_source_io.dart' if (dart.library.js_interop) 'video_source_web.dart';

/// Giới hạn video tải từ máy (cách A: quá dài thì hướng dẫn người dùng tự cắt bằng app Ảnh).
class VideoUploadRules {
  VideoUploadRules._();

  /// Giới hạn cứng theo dung lượng (quyết định thời gian upload & chỗ lưu trên máy chủ).
  static const int maxBytes = 100 * 1024 * 1024;

  /// Trên mức này vẫn cho tải nhưng nhắc có thể lâu nếu dùng 4G.
  static const int warnBytes = 50 * 1024 * 1024;

  /// Thời lượng tối đa; cho dư 1 giây do làm tròn khi đọc thời lượng.
  static const int maxSeconds = 60;

  static String formatSize(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).toStringAsFixed(0)} KB';

  static String formatDuration(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}

/// Kết quả kiểm tra video vừa chọn.
class PickedVideo {
  final XFile file;
  final int bytes;
  final Duration duration;
  const PickedVideo(this.file, this.bytes, this.duration);

  bool get tooLarge => bytes > VideoUploadRules.maxBytes;
  bool get tooLong => duration.inSeconds > VideoUploadRules.maxSeconds + 1;
  bool get heavy => bytes > VideoUploadRules.warnBytes;
}

class VideoUploadException implements Exception {
  final String message;
  const VideoUploadException(this.message);
  @override
  String toString() => message;
}

class VideoUploadService {
  VideoUploadService._();

  /// Mở thư viện ảnh/video của điện thoại. Trả null nếu người dùng bỏ chọn.
  static Future<XFile?> pickFromGallery() => ImagePicker().pickVideo(source: ImageSource.gallery);

  /// Đọc dung lượng + thời lượng để kiểm tra giới hạn trước khi upload.
  static Future<PickedVideo> inspect(XFile file) async {
    final bytes = await file.length();
    final VideoPlayerController c = controllerFromLocalPath(file.path);
    try {
      await c.initialize();
      return PickedVideo(file, bytes, c.value.duration);
    } catch (_) {
      throw const VideoUploadException('Không đọc được video này. Hãy chọn video định dạng MP4 hoặc MOV.');
    } finally {
      await c.dispose();
    }
  }

  /// Chuỗi lưu cho bản demo khi chưa có backend (chỉ xem được trên máy này).
  static String localValue(XFile file) => '${VideoLink.localPrefix}${file.path}';
}

/// Một lần upload, có tiến trình và hủy được.
/// Máy chủ: `POST {baseUrl}/media/videos` (multipart, field `file`)
/// trả `{"url": "/uploads/videos/<tên file>"}` (chấp nhận cả `videoUrl` hoặc URL https đầy đủ).
class VideoUploadTask {
  final XFile file;
  final int bytes;
  final void Function(double progress)? onProgress;
  final http.Client _client = http.Client();
  bool _cancelled = false;

  VideoUploadTask(this.file, this.bytes, {this.onProgress});

  void cancel() {
    _cancelled = true;
    _client.close(); // ngắt kết nối đang gửi
  }

  Future<String> start() async {
    final uri = ApiClient.instance.uri('/media/videos');
    final multipart = http.MultipartRequest('POST', uri)
      ..files.add(http.MultipartFile('file', file.openRead(), bytes, filename: _fileName()));

    // Bọc body để đếm số byte đã gửi -> thanh tiến trình
    final body = multipart.finalize();
    final total = multipart.contentLength;
    final req = http.StreamedRequest('POST', uri)
      ..headers.addAll(ApiClient.instance.headers())
      ..headers.addAll(multipart.headers)
      ..contentLength = total;
    var sent = 0;
    unawaited(body
        .map((chunk) {
          sent += chunk.length;
          if (total > 0) onProgress?.call((sent / total).clamp(0.0, 1.0));
          return chunk;
        })
        .pipe(req.sink)
        .catchError((_) {}));

    try {
      final res = await http.Response.fromStream(
        await _client.send(req).timeout(const Duration(minutes: 3)),
      );
      if (res.statusCode == 413) {
        throw const VideoUploadException('Máy chủ từ chối: video quá lớn.');
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw VideoUploadException('Máy chủ báo lỗi (${res.statusCode}).');
      }
      final json = jsonDecode(res.body);
      final url = json is Map ? (json['url'] ?? json['videoUrl'])?.toString() : null;
      if (url == null || VideoLink.tryParse(url) == null) {
        throw const VideoUploadException('Máy chủ trả về địa chỉ video không hợp lệ.');
      }
      return url;
    } on VideoUploadException {
      rethrow;
    } on TimeoutException {
      throw const VideoUploadException('Tải lên quá lâu, hãy thử lại với mạng ổn định hơn.');
    } catch (_) {
      if (_cancelled) throw const VideoUploadException('Đã hủy tải lên.');
      throw const VideoUploadException('Không kết nối được máy chủ.');
    } finally {
      _client.close();
    }
  }

  String _fileName() {
    final name = file.name.trim();
    if (name.isNotEmpty && name.contains('.')) return name;
    return 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
  }
}
