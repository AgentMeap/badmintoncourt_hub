import '../api/api_client.dart';
import '../api/json.dart';

/// Kèo giao lưu (`/api/matches`).
class MatchRepository {
  MatchRepository([ApiClient? api]) : _api = api ?? ApiClient.instance;
  final ApiClient _api;

  /// Mỗi phần tử: `{post, participants, pendingCount, isHost, myStatus}`.
  Future<List<Json>> list({String? skill}) async =>
      asJsonList(await _api.get('/matches', query: {'skill': skill}));

  /// Một kèo (mở từ thông báo / thẻ kèo). 404 nếu kèo đã bị xoá.
  Future<Json> detail(Object matchId) async => asJson(await _api.get('/matches/$matchId'));

  /// `{hosting: [...], joined: [...], pendingTotal}`: kèo tôi tổ chức và kèo tôi đã xin tham gia.
  Future<Json> mine() async => asJson(await _api.get('/matches/mine'));

  Future<Json> create(Json post) async => asJson(await _api.post('/matches', post));

  /// Gửi yêu cầu tham gia, trả về participant (status PENDING).
  Future<Json> join(Object matchId, int userId) async =>
      asJson(await _api.post('/matches/$matchId/join', {'userId': userId}));

  /// Chủ kèo duyệt (APPROVED) / từ chối (REJECTED, [reason] tuỳ chọn).
  /// Trả về `{post, participant, entry}` (entry = kèo sau khi cập nhật). 409 nếu đơn đã được xử lý.
  Future<Json> reviewParticipant(Object matchId, Object participantId, String status, {String? reason}) async =>
      asJson(await _api.patch('/matches/$matchId/participants/$participantId', {
        'status': status,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      }));

  /// Người đang đăng nhập rút khỏi kèo: hủy đơn đang chờ duyệt, hoặc rời kèo đã được duyệt.
  /// Trả về `{left: PENDING|APPROVED, entry}`.
  Future<Json> leave(Object matchId) async => asJson(await _api.post('/matches/$matchId/leave', const {}));

  /// Số tiền cọc được hoàn nếu hủy đơn / rời kèo ngay bây giờ: `{deposit, refundAmount, forfeitAmount, rule}`.
  Future<Json> leavePreview(Object matchId) async => asJson(await _api.get('/matches/$matchId/leave-preview'));

  /// Thành viên đã duyệt đánh giá chủ kèo sau khi kèo kết thúc (tạo mới hoặc sửa). Trả về `{review, entry}`.
  Future<Json> reviewHost(Object matchId,
          {required int rating, required String skillAccuracy, List<String> tags = const [], String? comment}) async =>
      asJson(await _api.post('/matches/$matchId/host-review', {
        'rating': rating,
        'skillAccuracy': skillAccuracy,
        'tags': tags,
        if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
      }));

  /// Hồ sơ uy tín chủ kèo: `{hostId, hostName, hostSkill, summary, reviews}`.
  Future<Json> hostProfile(Object hostId) async => asJson(await _api.get('/matches/hosts/$hostId/profile'));

  /// Chủ kèo hủy kèo ([reason] tuỳ chọn, gửi kèm thông báo). Trả về `{post, entry}`.
  Future<Json> cancel(Object matchId, {String? reason}) async =>
      asJson(await _api.post('/matches/$matchId/cancel', {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      }));

  /// Tin nhắn nhóm chat của kèo (cũ -> mới). Có [afterId] thì chỉ lấy tin mới hơn.
  /// Trả về `{items: [{id, userId, userName, content, createdAt, mine}], closed}`.
  Future<Json> messages(Object matchId, {Object? afterId}) async => asJson(await _api.get(
      '/matches/$matchId/messages',
      query: {if (afterId != null) 'afterId': '$afterId'}));

  /// Gửi tin nhắn vào nhóm chat, trả về tin vừa gửi.
  Future<Json> sendMessage(Object matchId, String content) async =>
      asJson(await _api.post('/matches/$matchId/messages', {'content': content}));

  /// Chủ kèo mời một thành viên đã duyệt ra khỏi kèo ([reason] tuỳ chọn). Trả về `{post, participant, entry}`.
  Future<Json> removeParticipant(Object matchId, Object participantId, {String? reason}) async =>
      asJson(await _api.post('/matches/$matchId/participants/$participantId/remove', {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      }));
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
  /// [lat]/[lng]: vị trí người dùng để gợi ý sân gần (không gửi thì máy chủ dùng Làng Đại học).
  Future<Json> chat(String message, {Object? sessionId, double? lat, double? lng}) async =>
      asJson(await _api.post('/ai/chat', {
        'message': message,
        if (sessionId != null) 'sessionId': sessionId,
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
      }));

  /// Phiên đang mở: `{sessionId, messages: [{role, content, cards, quickChips}], quota}`.
  Future<Json> currentSession() async => asJson(await _api.get('/ai/sessions/current'));

  /// Bắt đầu cuộc trò chuyện mới (đóng phiên cũ).
  Future<Json> newSession() async => asJson(await _api.post('/ai/sessions'));
}
