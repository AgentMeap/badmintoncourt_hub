import '../api/api_client.dart';
import '../api/json.dart';

/// Tìm đường theo đường phố (`/api/routes`): A* trên bản đồ OpenStreetMap TP.HCM ở backend.
class RouteRepository {
  RouteRepository([ApiClient? api]) : _api = api ?? ApiClient.instance;
  final ApiClient _api;

  /// `{mode, distanceMeters, durationSeconds, geometry:[[lat,lng]...], steps:[...], approximate}`.
  /// 503: bản đồ đường đang chuẩn bị; 422: ngoài vùng; 404: không có đường.
  /// [mode]: `motorbike` | `car` | `walk`.
  Future<Json> route({
    required double fromLat,
    required double fromLng,
    required Object venueId,
    required String mode,
  }) async =>
      asJson(await _api.get('/routes', query: {
        'fromLat': fromLat.toStringAsFixed(6),
        'fromLng': fromLng.toStringAsFixed(6),
        'venueId': venueId,
        'mode': mode,
      }));

  /// `{state, ready, progress, message, ...}`.
  Future<Json> status() async => asJson(await _api.get('/routes/status'));
}
