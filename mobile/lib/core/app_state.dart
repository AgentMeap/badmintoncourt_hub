import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth/google_auth_service.dart';
import 'demo_seed.dart';
import 'repositories/repositories.dart';

class AppState extends ChangeNotifier {
  AppState() {
    // Máy chủ báo phiên hết hạn (401) -> đăng xuất về màn đăng nhập
    ApiClient.instance.onUnauthorized = () {
      if (currentScreen != 'S01') logout();
    };
  }

  String currentScreen = 'S01';
  final List<String> history = ['S01'];

  // Current User Session
  int userId = 1;
  String fullName = 'Nguyễn Hữu Đạt (Customer)';
  String email = 'customer@badminton.vn';
  String phone = '0909123456';
  String role = 'CUSTOMER'; // CUSTOMER | COURT_OWNER | ADMIN
  String skillLevel = 'TB_YEU';
  // Link video giới thiệu trình độ (YouTube / .mp4), sửa ở S29; trống = chưa có
  String introVideoUrl = '';
  /// Ảnh đại diện (từ tài khoản Google); trống = hiện chữ cái đầu của tên.
  String avatarUrl = '';
  /// false = tài khoản tạo bằng Google, chưa đặt mật khẩu riêng (S29 ẩn phần đổi mật khẩu).
  bool hasPassword = true;
  /// Máy chủ đang bật chế độ demo (cho phép nạp tiền Ví trực tiếp ở S18).
  bool serverDemoMode = true;
  double walletBalance = 350000;
  String lastOtpEmail = 'customer@badminton.vn';
  String lastOtpPurpose = 'REGISTER';
  String lastDemoOtp = '123456';

  // Active selection context across screens
  Map<String, dynamic>? selectedVenue;
  Map<String, dynamic>? selectedBooking;
  // Kèo đang xem ở S30 (chọn từ thẻ kèo ở S15)
  Map<String, dynamic>? selectedMatch;
  Map<String, dynamic>? activePayosPayment;
  Map<String, dynamic>? pendingPayoutDraft;
  /// Yêu cầu rút tiền Ví đang chờ xác thực OTP (tạo ở S27, xử lý ở S03).
  Map<String, dynamic>? pendingWithdrawDraft;
  /// Mật khẩu mới nhập ở S04, gửi kèm OTP ở S03 (luồng quên mật khẩu).
  String? pendingResetPassword;

  /// Danh sách ID sân yêu thích (lưu trữ cục bộ SharedPreferences trên điện thoại).
  Set<int> favoriteVenueIds = {1, 2};

  /// Lịch sử các từ khóa tìm kiếm gần đây (lưu trữ cục bộ trên máy).
  List<String> searchHistory = ['Linh Trung', 'KTX Khu B', 'TPT Sport'];

  bool isFavorite(int venueId) => favoriteVenueIds.contains(venueId);

  Future<void> toggleFavorite(int venueId) async {
    if (favoriteVenueIds.contains(venueId)) {
      favoriteVenueIds.remove(venueId);
    } else {
      favoriteVenueIds.add(venueId);
    }
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('favorite_venues', favoriteVenueIds.map((e) => '$e').toList());
    } catch (_) {}
  }

  Future<void> addSearchQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    searchHistory.removeWhere((e) => e.toLowerCase() == trimmed.toLowerCase());
    searchHistory.insert(0, trimmed);
    if (searchHistory.length > 8) searchHistory = searchHistory.sublist(0, 8);
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('search_history', searchHistory);
    } catch (_) {}
  }

  Future<void> removeSearchQuery(String query) async {
    searchHistory.removeWhere((e) => e == query);
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('search_history', searchHistory);
    } catch (_) {}
  }

  Future<void> clearSearchHistory() async {
    searchHistory.clear();
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('search_history');
    } catch (_) {}
  }

  // Dữ liệu đồng bộ từ backend Spring Boot. Giá trị ban đầu là dữ liệu mẫu (DemoSeed),
  // chỉ còn được giữ lại khi không kết nối được máy chủ.
  List<Map<String, dynamic>> venues = DemoSeed.venues();

  List<Map<String, dynamic>> bookings = DemoSeed.bookings();

  List<Map<String, dynamic>> matches = DemoSeed.matches();

  List<Map<String, dynamic>> notifications = DemoSeed.notifications();

  /// Đánh giá sân của người chơi (S28 tạo, S08 hiển thị).
  List<Map<String, dynamic>> reviews = [];

  List<Map<String, dynamic>> walletTransactions = DemoSeed.walletTransactions();

  List<Map<String, dynamic>> adminPendingVenues = DemoSeed.adminPendingVenues();

  List<Map<String, dynamic>> payoutRequests = DemoSeed.payoutRequests();

  /// Tổng quan chủ sân từ máy chủ (S19, S23): today, last7Days, venueStats, availablePayoutGross...
  Json ownerDashboard = {};

  /// Mọi cơ sở của chủ sân, kể cả đang chờ duyệt / bị từ chối / tạm ngưng.
  List<Map<String, dynamic>> ownerVenueList = [];

  /// Tổng quan nền tảng từ máy chủ (S24): gmvLast7Days, usersByRole, bookingsToday...
  Json adminDashboard = {};

  /// Tài khoản toàn hệ thống (S25 - khóa / mở khóa).
  List<Map<String, dynamic>> adminUsers = [];

  /// Tab mở sẵn khi vào S25: 0 = duyệt cơ sở, 1 = tài khoản.
  int adminModerationTab = 0;

  int get unreadNotificationCount =>
      notifications.where((n) => n['isRead'] == false).length;

  /// Mã vé vừa thanh toán xong, để S13 hiện "Đặt sân thành công".
  /// Tự xóa khi rời màn S13.
  String? justPaidBookingCode;

  static const int _maxHistory = 40;

  /// Chế độ giao diện: theo hệ thống / sáng / tối (chọn trong menu Drawer).
  ThemeMode themeMode = ThemeMode.system;

  void setThemeMode(ThemeMode mode) {
    if (themeMode == mode) return;
    themeMode = mode;
    notifyListeners();
  }

  void _setScreen(String screenCode) {
    if (currentScreen == 'S13' && screenCode != 'S13') justPaidBookingCode = null;
    currentScreen = screenCode;
    notifyListeners();
  }

  void goTo(String screenCode) {
    if (currentScreen != screenCode) {
      history.add(screenCode);
      if (history.length > _maxHistory) {
        history.removeRange(0, history.length - _maxHistory);
      }
      _setScreen(screenCode);
    }
  }

  void goBack() {
    if (history.length > 1) {
      history.removeLast();
      _releaseAbandonedHold(history.last);
      _setScreen(history.last);
    }
  }

  bool get canGoBack => history.length > 1;

  /// Xóa lịch sử và bắt đầu lại từ [screenCode] (sau đăng nhập, đăng xuất, đổi vai trò):
  /// nút Back không quay về màn đăng nhập nữa.
  void resetTo(String screenCode) {
    _releaseAbandonedHold(screenCode);
    history
      ..clear()
      ..add(screenCode);
    _setScreen(screenCode);
  }

  /// Chuyển tab ở thanh điều hướng: lịch sử chỉ còn [home] (+ [tab] nếu khác home),
  /// nên bấm qua lại giữa các tab không làm lịch sử dài ra, Back từ tab bất kỳ về tab chính.
  void goToTab(String tab, String home) {
    _releaseAbandonedHold(tab);
    // Cập nhật số thông báo chưa đọc trên AppBar khi người dùng chuyển tab
    refreshNotifications(minInterval: const Duration(seconds: 30));
    history
      ..clear()
      ..add(home);
    if (tab != home) history.add(tab);
    _setScreen(tab);
  }

  /// Kết thúc luồng nhiều bước (VD đặt sân S09 -> S10 -> S11): bỏ các màn của luồng
  /// khỏi lịch sử rồi mở [target], để Back từ vé không quay lại màn quét QR / thanh toán.
  void completeFlow(String target, {String flowStart = 'S09'}) {
    final idx = history.lastIndexOf(flowStart);
    if (idx >= 0) history.removeRange(idx, history.length);
    if (history.isEmpty || history.last != target) history.add(target);
    _setScreen(target);
  }

  // ---------------------------------------------------------------- Phiên đăng nhập

  /// Tài khoản demo có sẵn trong DataSeeder của backend (mật khẩu 123456).
  static const demoAccounts = {
    'CUSTOMER': 'customer@badminton.vn',
    'COURT_OWNER': 'owner@badminton.vn',
    'ADMIN': 'admin@badminton.vn',
  };

  /// Kết quả kết nối máy chủ ở lần gọi gần nhất: null = chưa biết,
  /// false = không tới được máy chủ (đang hiển thị dữ liệu mẫu).
  bool? backendReachable;
  bool get isOfflineDemo => backendReachable == false;

  /// Màn hình chính theo vai trò.
  String get homeScreen => role == 'COURT_OWNER' ? 'S19' : (role == 'ADMIN' ? 'S24' : 'S06');

  /// Ghi phiên từ phản hồi đăng nhập / xác thực OTP của backend
  /// (token, id, fullName, email, phone, role, skillLevel, introVideoUrl, walletBalance).
  Future<void> applyAuthResponse(Map<String, dynamic> res) async {
    _applyUserFields(res);
    final token = res['token']?.toString();
    ApiClient.instance.token = token;
    backendReachable = true;
    notifyListeners();
    await saveSession(token: token);
  }

  void _applyUserFields(Map<String, dynamic> res) {
    final id = asNum(res['id']);
    if (id != null) userId = id.toInt();
    fullName = res['fullName']?.toString() ?? fullName;
    email = res['email']?.toString() ?? email;
    phone = res['phone']?.toString() ?? phone;
    role = res['role']?.toString() ?? role;
    skillLevel = res['skillLevel']?.toString() ?? skillLevel;
    if (res.containsKey('introVideoUrl')) introVideoUrl = res['introVideoUrl']?.toString() ?? '';
    if (res.containsKey('avatarUrl')) avatarUrl = res['avatarUrl']?.toString() ?? '';
    if (res['hasPassword'] is bool) hasPassword = res['hasPassword'] as bool;
    if (res['demoMode'] is bool) serverDemoMode = res['demoMode'] as bool;
    final balance = asNum(res['walletBalance']);
    if (balance != null) walletBalance = balance.toDouble();
  }

  /// Đăng nhập nhanh bằng tài khoản demo của vai trò [targetRole].
  /// Có máy chủ: đăng nhập thật (lấy token, số dư thật). Không tới được máy chủ:
  /// vào chế độ xem dữ liệu mẫu. Trả về câu báo lỗi nếu máy chủ từ chối, null nếu thành công.
  Future<String?> switchDemoRole(String targetRole) async {
    final demoEmail = demoAccounts[targetRole] ?? demoAccounts['CUSTOMER']!;
    try {
      await applyAuthResponse(await Repos.auth.login(demoEmail, '123456'));
    } on ApiException catch (e) {
      if (!e.isConnectivity) return e.message;
      _useOfflineDemoProfile(targetRole);
    }
    resetTo(homeScreen);
    syncFromBackend();
    return null;
  }

  void _useOfflineDemoProfile(String targetRole) {
    ApiClient.instance.token = null;
    backendReachable = false;
    role = targetRole;
    if (targetRole == 'COURT_OWNER') {
      userId = 2;
      fullName = 'Trần Chủ Sân (Court Owner)';
      email = 'owner@badminton.vn';
      skillLevel = 'KHA';
    } else if (targetRole == 'ADMIN') {
      userId = 3;
      fullName = 'Quản Trị Viên (Admin)';
      email = 'admin@badminton.vn';
      skillLevel = 'KHA';
    } else {
      role = 'CUSTOMER';
      userId = 1;
      fullName = 'Nguyễn Hữu Đạt (Customer)';
      email = 'customer@badminton.vn';
      skillLevel = 'TB_YEU';
    }
    _clearSavedToken();
    saveSession();
  }

  Future<void> _clearSavedToken() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('auth_token');
    } catch (_) {}
  }

  static const _sessionKeys = [
    'auth_token',
    'auth_user_id',
    'auth_full_name',
    'auth_email',
    'auth_phone',
    'auth_role',
    'auth_skill',
    'auth_intro_video',
    'auth_avatar',
    'auth_has_password',
  ];

  Future<void> saveSession({String? token}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (token != null) await sp.setString('auth_token', token);
      await sp.setInt('auth_user_id', userId);
      await sp.setString('auth_full_name', fullName);
      await sp.setString('auth_email', email);
      await sp.setString('auth_phone', phone);
      await sp.setString('auth_role', role);
      await sp.setString('auth_skill', skillLevel);
      await sp.setString('auth_intro_video', introVideoUrl);
      await sp.setString('auth_avatar', avatarUrl);
      await sp.setBool('auth_has_password', hasPassword);
    } catch (_) {}
  }

  Future<void> loadSavedSession() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final savedId = sp.getInt('auth_user_id');
      if (savedId != null) {
        userId = savedId;
        fullName = sp.getString('auth_full_name') ?? fullName;
        email = sp.getString('auth_email') ?? email;
        phone = sp.getString('auth_phone') ?? phone;
        role = sp.getString('auth_role') ?? role;
        skillLevel = sp.getString('auth_skill') ?? skillLevel;
        introVideoUrl = sp.getString('auth_intro_video') ?? introVideoUrl;
        avatarUrl = sp.getString('auth_avatar') ?? avatarUrl;
        hasPassword = sp.getBool('auth_has_password') ?? hasPassword;
        ApiClient.instance.token = sp.getString('auth_token');
        resetTo(homeScreen);
      }
      final favList = sp.getStringList('favorite_venues');
      if (favList != null) {
        favoriteVenueIds = favList.map((e) => int.tryParse(e)).whereType<int>().toSet();
      }
      final historyList = sp.getStringList('search_history');
      if (historyList != null && historyList.isNotEmpty) {
        searchHistory = List<String>.from(historyList);
      }
    } catch (_) {}
  }

  DateTime? _notificationsLoadedAt;

  /// Tải lại thông báo. [minInterval]: bỏ qua nếu vừa tải gần đây (dùng khi đổi tab).
  Future<void> refreshNotifications({Duration? minInterval}) async {
    final last = _notificationsLoadedAt;
    if (minInterval != null && last != null && DateTime.now().difference(last) < minInterval) return;
    _notificationsLoadedAt = DateTime.now();
    try {
      notifications = await Repos.notification.list(userId);
      notifyListeners();
    } catch (e) {
      debugPrint('[notifications] $e');
    }
  }

  /// Nạp tiền vào Ví (chỉ khi máy chủ bật chế độ demo). Lỗi -> ApiException.
  Future<void> topUpWallet(num amount) async {
    final res = await Repos.auth.topUpWallet(userId, amount);
    _applyUserFields(res);
    notifyListeners();
    await refreshWallet();
  }

  /// Gửi mã OTP tới email của tài khoản đang đăng nhập (rút ví WITHDRAW_WALLET, giải ngân PAYOUT)
  /// rồi ghi lại để màn S03 biết đang xác thực cho việc gì. Lỗi -> ApiException.
  Future<void> requestAccountOtp(String purpose) async {
    final res = await Repos.auth.sendOtp(email, purpose);
    lastOtpEmail = res['email']?.toString() ?? email;
    lastOtpPurpose = purpose;
    lastDemoOtp = res['demoOtp']?.toString() ?? '';
  }

  /// Đăng xuất: xóa phiên + token, giữ lại cài đặt trên máy (sân yêu thích, lịch sử tìm kiếm).
  Future<void> logout() async {
    _releaseAbandonedHold('S01');
    GoogleAuthService.signOut();
    ApiClient.instance.token = null;
    try {
      final sp = await SharedPreferences.getInstance();
      for (final key in _sessionKeys) {
        await sp.remove(key);
      }
    } catch (_) {}
    // Dữ liệu quản trị của tài khoản cũ không được còn lại cho tài khoản đăng nhập sau
    ownerDashboard = {};
    ownerVenueList = [];
    adminDashboard = {};
    adminUsers = [];
    resetTo('S01');
  }

  // ---------------------------------------------------------------- Đồng bộ dữ liệu

  bool _syncing = false;

  /// Tải dữ liệu thật từ backend theo vai trò. Mỗi nhóm dữ liệu tải độc lập:
  /// nhóm nào lỗi thì giữ dữ liệu cũ, nhóm khác vẫn cập nhật. Máy chủ trả danh sách rỗng
  /// thì hiển thị rỗng (không còn giữ dữ liệu mẫu như trước).
  Future<void> syncFromBackend() async {
    if (_syncing) return;
    _syncing = true;
    var reached = false;
    var unreachable = false;

    Future<void> load<T>(Future<T> Function() fetch, void Function(T data) apply) async {
      try {
        apply(await fetch());
        reached = true;
      } on ApiException catch (e) {
        if (e.isConnectivity) {
          unreachable = true;
        } else {
          reached = true;
          debugPrint('[sync] $e');
        }
      } catch (e) {
        debugPrint('[sync] $e');
      }
    }

    try {
      await Future.wait([
        load(() => Repos.venue.list(), (List<Json> v) => venues = v),
        load(() => Repos.match.list(), (List<Json> m) => matches = m),
        load(() => Repos.review.list(), (List<Json> r) => reviews = r),
        load(() => Repos.notification.list(userId), (List<Json> n) => notifications = n),
        load(() => Repos.auth.profile(userId), _applyProfile),
        if (role == 'CUSTOMER')
          load(() => Repos.booking.customerBookings(userId), (List<Json> b) => bookings = b),
        if (role == 'COURT_OWNER') load(() => Repos.owner.dashboard(userId), _applyOwnerDashboard),
        if (role == 'ADMIN') load(() => Repos.admin.dashboard(), _applyAdminDashboard),
      ]);
      if (reached) {
        backendReachable = true;
      } else if (unreachable) {
        backendReachable = false;
      }
    } finally {
      _syncing = false;
    }
    notifyListeners();
  }

  /// Chỉ tải lại số dư + lịch sử Ví (sau thanh toán, hoàn tiền, rút tiền).
  Future<void> refreshWallet() async {
    try {
      _applyProfile(await Repos.auth.profile(userId));
      notifyListeners();
    } catch (e) {
      debugPrint('[wallet] $e');
    }
  }

  void _applyProfile(Json profile) {
    if (profile.isEmpty) return;
    _applyUserFields(profile);
    walletTransactions = asJsonList(profile['walletTransactions']);
    saveSession();
  }

  void _applyOwnerDashboard(Json d) {
    ownerDashboard = d;
    ownerVenueList = asJsonList(d['venues']);
    adminPendingVenues = ownerVenueList.where((v) => v['status'] == 'PENDING').toList();
    // Vé của chủ sân: toàn bộ ca hôm nay (để quét check-in S22) + các vé gần nhất.
    // Lịch từng ngày ở S21 tải riêng qua Repos.owner.venueBookings.
    final merged = <String, Json>{};
    for (final b in [...asJsonList(d['todaySessions']), ...asJsonList(d['recentBookings'])]) {
      merged.putIfAbsent('${b['id'] ?? b['bookingCode']}', () => b);
    }
    bookings = merged.values.toList();
    payoutRequests = asJsonList(d['payoutRequests']);
  }

  void _applyAdminDashboard(Json d) {
    adminDashboard = d;
    adminUsers = asJsonList(d['users']);
    adminPendingVenues = asJsonList(d['venues']).where((v) => v['status'] == 'PENDING').toList();
    payoutRequests = asJsonList(d['payoutRequests']);
  }

  /// Tải lại tổng quan chủ sân (sau check-in, thêm vãng lai, gửi giải ngân...).
  /// Ném lỗi cho màn hình hiển thị (kéo để làm mới).
  Future<void> refreshOwnerDashboard() async {
    if (role != 'COURT_OWNER') return;
    _applyOwnerDashboard(await Repos.owner.dashboard(userId));
    notifyListeners();
  }

  /// Tải lại tổng quan nền tảng (sau duyệt cơ sở, khóa tài khoản, duyệt giải ngân...).
  Future<void> refreshAdminDashboard() async {
    if (role != 'ADMIN') return;
    _applyAdminDashboard(await Repos.admin.dashboard());
    notifyListeners();
  }

  // ---------------------------------------------------------------- Vé đặt sân

  static const _paymentScreens = {'S10', 'S11'};

  /// Rời luồng thanh toán (Back về chọn giờ, đổi tab, đăng xuất) khi vé còn đang giữ chỗ:
  /// báo máy chủ trả chỗ ngay cho người khác thay vì chờ hết 5 phút.
  /// Mở tạm màn khác (Thông báo, Trợ lý AI) bằng goTo thì vẫn giữ chỗ.
  void _releaseAbandonedHold(String target) {
    if (!_paymentScreens.contains(currentScreen)) return;
    if (_paymentScreens.contains(target) || target == 'S13') return;
    final b = selectedBooking;
    final id = b?['id'];
    if (b == null || id == null || b['status'] != 'HELD') return;
    b['status'] = 'CANCELLED';
    activePayosPayment = null;
    Repos.booking.release(id, customerId: userId).then((res) {
      final server = asJson(res['booking']);
      if (server.isNotEmpty) b.addAll(server);
      notifyListeners();
    }).catchError((Object e) {
      debugPrint('[release] $e');
      // Máy chủ từ chối (VD vé vừa được thanh toán): tải lại trạng thái thật
      refreshBookings();
    });
  }

  /// Tải lại danh sách vé của người dùng hiện tại.
  Future<void> refreshBookings() async {
    if (role != 'CUSTOMER') return syncFromBackend();
    try {
      bookings = await Repos.booking.customerBookings(userId);
      notifyListeners();
    } catch (e) {
      debugPrint('[bookings] $e');
    }
  }

  /// Tải lại một vé (trạng thái, giờ, giá...) và cập nhật tại chỗ để màn đang mở thấy ngay.
  Future<void> refreshBooking(Map<String, dynamic> booking) async {
    final id = booking['id'];
    if (id == null) return;
    try {
      final server = asJson((await Repos.booking.detail(id))['booking']);
      if (server.isEmpty) return;
      booking.addAll(server);
      upsertBooking(booking);
    } catch (e) {
      debugPrint('[booking] $e');
    }
  }

  /// Thay một vé trong danh sách bằng bản mới từ máy chủ (thêm lên đầu nếu chưa có).
  void upsertBooking(Map<String, dynamic> booking) {
    final code = booking['bookingCode'];
    bookings.removeWhere((b) =>
        (booking['id'] != null && '${b['id']}' == '${booking['id']}') ||
        (code != null && b['bookingCode'] == code));
    bookings.insert(0, booking);
    notifyListeners();
  }

  void pushNotification({
    required String title,
    required String body,
    required String type,
    required String targetScreen,
    BuildContext? context,
  }) {
    notifications.insert(0, {
      'id': DateTime.now().millisecondsSinceEpoch,
      'title': title,
      'body': body,
      'type': type,
      'targetScreen': targetScreen,
      'isRead': false,
      'createdAt': 'Vừa xong',
    });
    notifyListeners();

    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        // Màu mặc định của SnackBar theo Theme (inverseSurface), icon vector thay emoji
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                color: Theme.of(context).colorScheme.inversePrimary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Xem',
            onPressed: () => goTo(targetScreen),
          ),
        ),
      );
    }
  }

  void markAllNotificationsRead() {
    for (final n in notifications) {
      n['isRead'] = true;
    }
    notifyListeners();
    Repos.notification.markAllRead(userId).catchError((Object e) => debugPrint('[notify] $e'));
  }

  /// Đánh dấu một thông báo đã đọc (cả trên máy chủ).
  void markNotificationRead(Map<String, dynamic> n) {
    if (n['isRead'] == true) return;
    n['isRead'] = true;
    notifyListeners();
    final id = n['id'];
    if (id != null) {
      Repos.notification.markRead(id).catchError((Object e) => debugPrint('[notify] $e'));
    }
  }
}
