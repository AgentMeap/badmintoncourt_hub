import '../api/api_client.dart';
import '../api/json.dart';

/// Kèo giao lưu (`/api/matches`).
class MatchRepository {
  MatchRepository([ApiClient? api]) : _api = api ?? ApiClient.instance;
  final ApiClient _api;

  /// Mỗi phần tử: `{post, participants}`.
  Future<List<Json>> list({String? skill}) async =>
      asJsonList(await _api.get('/matches', query: {'skill': skill}));

  Future<Json> create(Json post) async => asJson(await _api.post('/matches', post));

  /// Gửi yêu cầu tham gia, trả về participant (status PENDING).
  Future<Json> join(Object matchId, int userId) async =>
      asJson(await _api.post('/matches/$matchId/join', {'userId': userId}));

  /// Chủ kèo duyệt / từ chối. Trả về `{post, participant}`.
  Future<Json> reviewParticipant(Object matchId, Object participantId, String status) async =>
      asJson(await _api.patch('/matches/$matchId/participants/$participantId', {'status': status}));
}

/// Thông báo (`/api/notifications`).
class NotificationRepository {
  NotificationRepository([ApiClient? api]) : _api = api ?? ApiClient.instance;
  final ApiClient _api;

  Future<List<Json>> list(int userId) async {
    final res = asJson(await _api.get('/notifications/user/$userId'));
    final items = asJsonList(res['items']);
    // Backend cũ trả khóa "read" thay vì "isRead"
    for (final n in items) {
      n['isRead'] ??= n['read'] ?? false;
    }
    return items;
  }

  Future<void> markRead(Object notificationId) => _api.patch('/notifications/$notificationId/read');

  Future<void> markAllRead(int userId) => _api.post('/notifications/user/$userId/read-all');
}

/// Đánh giá sân (`/api/reviews`).
class ReviewRepository {
  ReviewRepository([ApiClient? api]) : _api = api ?? ApiClient.instance;
  final ApiClient _api;

  Future<List<Json>> list() async => asJsonList(await _api.get('/reviews'));

  Future<List<Json>> byVenue(Object venueId) async =>
      asJsonList(await _api.get('/reviews/venue/$venueId'));

  Future<Json> create(Json review) async => asJson(await _api.post('/reviews', review));
}

/// Trợ lý AI cho người chơi (`/api/ai`).
class AiRepository {
  AiRepository([ApiClient? api]) : _api = api ?? ApiClient.instance;
  final ApiClient _api;

  /// Gửi câu hỏi. Trả về `{sessionId, reply, inScope, cards, quickChips, quota}`.
  /// Quá 300 ký tự -> 400; vượt 5 tin/phút hoặc 30 tin/ngày -> 429.
  Future<Json> chat(String message, {Object? sessionId}) async =>
      asJson(await _api.post('/ai/chat', {
        'message': message,
        if (sessionId != null) 'sessionId': sessionId,
      }));

  /// Phiên đang mở: `{sessionId, messages: [{role, content, cards, quickChips}], quota}`.
  Future<Json> currentSession() async => asJson(await _api.get('/ai/sessions/current'));

  /// Bắt đầu cuộc trò chuyện mới (đóng phiên cũ).
  Future<Json> newSession() async => asJson(await _api.post('/ai/sessions'));
}
