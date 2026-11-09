import '../api/api_client.dart';
import '../api/json.dart';

/// Cơ sở cầu lông (`/api/venues/...`).
class VenueRepository {
  VenueRepository([ApiClient? api]) : _api = api ?? ApiClient.instance;
  final ApiClient _api;

  /// Cơ sở đã duyệt, sắp theo khoảng cách tới ([lat], [lng]).
  Future<List<Json>> list({String? keyword, double? lat, double? lng, double? maxRadiusKm}) async =>
      asJsonList(await _api.get('/venues', query: {
        'keyword': keyword,
        'lat': lat,
        'lng': lng,
        'maxRadiusKm': maxRadiusKm,
      }));

  /// Chi tiết cơ sở kèm `courts`, `pricingRules`, `bookingsOnDate`, `openMatches` của ngày [playDate].
  Future<Json> detail(Object venueId, {String? playDate}) async =>
      asJson(await _api.get('/venues/$venueId', query: {'playDate': playDate}));

  /// Mọi cơ sở của chủ sân (kể cả đang chờ duyệt).
  Future<List<Json>> ownerVenues(int ownerId) async =>
      asJsonList(await _api.get('/venues/owner/$ownerId'));

  /// Chủ sân gửi hồ sơ cơ sở mới (trạng thái PENDING).
  Future<Json> create(Json venue) async => asJson(await _api.post('/venues/owner', venue));
}
