import 'auth_repository.dart';
import 'booking_repository.dart';
import 'finance_repositories.dart';
import 'social_repositories.dart';
import 'venue_repository.dart';

export '../api/api_client.dart';
export '../api/api_exception.dart';
export '../api/api_feedback.dart';
export '../api/json.dart';
export 'auth_repository.dart';
export 'booking_repository.dart';
export 'finance_repositories.dart';
export 'social_repositories.dart';
export 'venue_repository.dart';

/// Điểm truy cập các repository dùng chung (đều dùng [ApiClient.instance]).
/// Màn hình gọi API qua đây, VD: `await Repos.booking.hold(...)`.
class Repos {
  Repos._();

  static final auth = AuthRepository();
  static final venue = VenueRepository();
  static final booking = BookingRepository();
  static final wallet = WalletRepository();
  static final match = MatchRepository();
  static final notification = NotificationRepository();
  static final review = ReviewRepository();
  static final owner = OwnerRepository();
  static final admin = AdminRepository();
  static final ai = AiRepository();
}
