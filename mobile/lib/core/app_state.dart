import 'package:flutter/material.dart';
import 'api_service.dart';

class AppState extends ChangeNotifier {
  String currentScreen = 'S01';
  final List<String> history = ['S01'];

  // Current User Session
  int userId = 1;
  String fullName = 'Nguyễn Hữu Đạt (Customer)';
  String email = 'customer@badminton.vn';
  String phone = '0909123456';
  String role = 'CUSTOMER'; // CUSTOMER | COURT_OWNER | ADMIN
  String skillLevel = 'TB_YEU';
  double walletBalance = 350000;
  String lastOtpEmail = 'customer@badminton.vn';
  String lastOtpPurpose = 'REGISTER';
  String lastDemoOtp = '123456';

  // Active selection context across screens
  Map<String, dynamic>? selectedVenue;
  Map<String, dynamic>? selectedBooking;
  Map<String, dynamic>? activePayosPayment;
  Map<String, dynamic>? pendingPayoutDraft;
  /// Yêu cầu rút tiền Ví đang chờ xác thực OTP (tạo ở S27, xử lý ở S03).
  Map<String, dynamic>? pendingWithdrawDraft;

  // Data caches (synced from Spring Boot SQLite API, with rich initial fallback)
  List<Map<String, dynamic>> venues = [
    {
      'id': 1,
      'ownerId': 2,
      'ownerName': 'Trần Chủ Sân',
      'name': 'Sân CLB TDTT ĐH Thể Dục Thể Thao TP.HCM',
      'address': 'Khuôn viên ĐH Thể Dục Thể Thao, KP.6, P. Linh Trung, TP. Thủ Đức',
      'latitude': 10.8682,
      'longitude': 106.7975,
      'distanceKm': 0.8,
      'description': 'Nhà thi đấu trường ĐH TDTT, 6 sân thảm Yonex tiêu chuẩn thi đấu, trần cao 12m, thông gió tự nhiên, bãi đỗ xe rộng rãi.',
      'imageUrl': 'https://images.unsplash.com/photo-1541534741688-6078c6bfb5c5?w=800',
      'openTime': '05:00',
      'closeTime': '23:00',
      'status': 'APPROVED',
      'rating': 4.9,
      'totalCourts': 6,
      'basePricePerHour': 60000.0,
      'peakPricePerHour': 100000.0,
    },
    {
      'id': 2,
      'ownerId': 2,
      'ownerName': 'Trần Chủ Sân',
      'name': 'Sân Cầu Lông TPT Sport Làng Đại Học',
      'address': 'Đường Tôn Thất Tùng, P. Đông Hòa, TP. Dĩ An (Cạnh KTX Khu B)',
      'latitude': 10.8805,
      'longitude': 106.7925,
      'distanceKm': 1.0,
      'description': 'Điểm hẹn cầu lông sinh viên quen thuộc nhất Làng ĐH. 6 sân thảm đệm êm, ánh sáng chuẩn chống chói, giá cực kỳ ưu đãi.',
      'imageUrl': 'https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?w=800',
      'openTime': '05:00',
      'closeTime': '23:00',
      'status': 'APPROVED',
      'rating': 4.8,
      'totalCourts': 6,
      'basePricePerHour': 50000.0,
      'peakPricePerHour': 90000.0,
    },
    {
      'id': 3,
      'ownerId': 2,
      'ownerName': 'Trần Chủ Sân',
      'name': 'Sân Cầu Lông ĐH Nông Lâm TP.HCM',
      'address': 'Khuôn viên ĐH Nông Lâm, Quốc lộ 1A, P. Linh Trung, TP. Thủ Đức',
      'latitude': 10.8702,
      'longitude': 106.7891,
      'distanceKm': 1.3,
      'description': 'Cụm sân trong nhà thoáng mát, sàn thi đấu đạt chuẩn thể thao học đường, phục vụ sinh viên và cán bộ giảng viên.',
      'imageUrl': 'https://images.unsplash.com/photo-1574629810360-7efbbe195018?w=800',
      'openTime': '05:00',
      'closeTime': '23:00',
      'status': 'APPROVED',
      'rating': 4.7,
      'totalCourts': 4,
      'basePricePerHour': 55000.0,
      'peakPricePerHour': 95000.0,
    },
    {
      'id': 4,
      'ownerId': 2,
      'ownerName': 'Trần Chủ Sân',
      'name': 'Sân Cầu Lông KTX Khu B ĐHQG',
      'address': 'Đường Tô Vĩnh Diện, P. Đông Hòa, TP. Dĩ An, Bình Dương',
      'latitude': 10.8832,
      'longitude': 106.7820,
      'distanceKm': 2.1,
      'description': 'Khu thể thao đa năng KTX Khu B, không gian trẻ trung sôi động, chuyên tổ chức các giải đấu phong trào sinh viên.',
      'imageUrl': 'https://images.unsplash.com/photo-1521537634581-0dced2fee2ef?w=800',
      'openTime': '05:00',
      'closeTime': '23:00',
      'status': 'APPROVED',
      'rating': 4.7,
      'totalCourts': 4,
      'basePricePerHour': 45000.0,
      'peakPricePerHour': 80000.0,
    },
    {
      'id': 5,
      'ownerId': 2,
      'ownerName': 'Trần Chủ Sân',
      'name': 'Sân Cầu Lông Ao An (Bình An)',
      'address': '1015 Mỹ Phước - Tân Vạn, P. Bình An, TP. Dĩ An, Bình Dương',
      'latitude': 10.8872,
      'longitude': 106.8123,
      'distanceKm': 1.9,
      'description': '5 sân thảm mới tinh, sạch sẽ, bãi đỗ xe máy & ô tô thuận tiện ngay mặt tiền đường lớn.',
      'imageUrl': 'https://images.unsplash.com/photo-1613918108466-292b78a8ef95?w=800',
      'openTime': '05:00',
      'closeTime': '23:00',
      'status': 'APPROVED',
      'rating': 4.8,
      'totalCourts': 5,
      'basePricePerHour': 60000.0,
      'peakPricePerHour': 100000.0,
    },
    {
      'id': 6,
      'ownerId': 2,
      'ownerName': 'Trần Chủ Sân',
      'name': 'Sân Cầu Lông Aurora Sport Linh Trung',
      'address': '158 Đường số 17, P. Linh Trung, TP. Thủ Đức',
      'latitude': 10.8641,
      'longitude': 106.7832,
      'distanceKm': 2.2,
      'description': 'Tổ hợp thể thao hiện đại, 6 sân thảm cao cấp có khán đài mini, phòng tắm nóng lạnh và quầy nước giải khát tiện nghi.',
      'imageUrl': 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800',
      'openTime': '05:00',
      'closeTime': '23:00',
      'status': 'APPROVED',
      'rating': 4.9,
      'totalCourts': 6,
      'basePricePerHour': 70000.0,
      'peakPricePerHour': 110000.0,
    },
    {
      'id': 7,
      'ownerId': 2,
      'ownerName': 'Trần Chủ Sân',
      'name': 'Sân Cầu Lông Lan Anh Linh Trung',
      'address': '119 Đường số 7, P. Linh Trung, TP. Thủ Đức',
      'latitude': 10.8622,
      'longitude': 106.7815,
      'distanceKm': 2.5,
      'description': '6 sân thảm Yonex chống trượt, trần cao không gian thoáng mát, chuyên mở các lớp hướng dẫn kỹ thuật cầu lông.',
      'imageUrl': 'https://images.unsplash.com/photo-1517649763962-0c623266ddc0?w=800',
      'openTime': '05:00',
      'closeTime': '23:00',
      'status': 'APPROVED',
      'rating': 4.8,
      'totalCourts': 6,
      'basePricePerHour': 65000.0,
      'peakPricePerHour': 105000.0,
    },
    {
      'id': 8,
      'ownerId': 2,
      'ownerName': 'Trần Chủ Sân',
      'name': 'Sân Cầu Lông TH Badminton',
      'address': '166 Võ Thị Sáu, KP. Tây A, P. Đông Hòa, TP. Dĩ An',
      'latitude': 10.8924,
      'longitude': 106.7786,
      'distanceKm': 2.8,
      'description': 'Sân mới đầu tư hiện đại bậc nhất giáp ranh Làng ĐH. Thảm chống trượt BWF, trần cao thoáng đãng, hệ thống đèn LED bảo vệ mắt.',
      'imageUrl': 'https://images.unsplash.com/photo-1587280501635-68a0e82cd5ff?w=800',
      'openTime': '05:00',
      'closeTime': '23:00',
      'status': 'APPROVED',
      'rating': 4.9,
      'totalCourts': 8,
      'basePricePerHour': 60000.0,
      'peakPricePerHour': 110000.0,
    },
    {
      'id': 9,
      'ownerId': 2,
      'ownerName': 'Trần Chủ Sân',
      'name': 'Sân Cầu Lông Gia Hân Dĩ An',
      'address': '80 Võ Thị Sáu, P. Đông Hòa, TP. Dĩ An, Bình Dương',
      'latitude': 10.8906,
      'longitude': 106.7822,
      'distanceKm': 2.4,
      'description': 'Đại cụm 15 sân quy mô lớn nhất khu vực Dĩ An - Làng ĐH. Thảm thi đấu tiêu chuẩn quốc gia, mở cửa linh hoạt 24/7.',
      'imageUrl': 'https://images.unsplash.com/photo-1612872087720-bb876e2e67d1?w=800',
      'openTime': '05:00',
      'closeTime': '23:00',
      'status': 'APPROVED',
      'rating': 4.9,
      'totalCourts': 15,
      'basePricePerHour': 50000.0,
      'peakPricePerHour': 90000.0,
    },
    {
      'id': 10,
      'ownerId': 2,
      'ownerName': 'Trần Chủ Sân',
      'name': 'Sân Cầu Lông SHB Badminton',
      'address': '127 Lê Văn Chí, P. Linh Trung, TP. Thủ Đức',
      'latitude': 10.8584,
      'longitude': 106.7721,
      'distanceKm': 3.6,
      'description': 'Hệ thống thể thao quy mô khủng 18 sân đạt chuẩn, gần Ngã tư Thủ Đức, tổ chức nhiều giải đấu quy mô sinh viên.',
      'imageUrl': 'https://images.unsplash.com/photo-1574629810360-7efbbe195018?w=800',
      'openTime': '05:00',
      'closeTime': '23:00',
      'status': 'APPROVED',
      'rating': 4.9,
      'totalCourts': 12,
      'basePricePerHour': 65000.0,
      'peakPricePerHour': 120000.0,
    },
  ];

  List<Map<String, dynamic>> bookings = [
    {
      'id': 1,
      'bookingCode': 'BK-202610',
      'venueId': 1,
      'venueName': 'Sân CLB TDTT ĐH Thể Dục Thể Thao TP.HCM',
      'courtId': 2,
      'courtName': 'Sân 2',
      'customerId': 1,
      'customerName': 'Nguyễn Hữu Đạt',
      'customerPhone': '0909123456',
      'bookingType': 'ONLINE',
      'playDate': '2026-10-30',
      'startTime': '18:00',
      'endTime': '20:00',
      'totalPrice': 200000.0,
      'status': 'CONFIRMED',
      'rescheduledCount': 0,
      'qrCheckInToken': 'QR-BK-202610',
      'paymentMethod': 'PAYOS_QR',
    },
    {
      'id': 2,
      'bookingCode': 'WI-889012',
      'venueId': 1,
      'venueName': 'Sân CLB TDTT ĐH Thể Dục Thể Thao TP.HCM',
      'courtId': 1,
      'courtName': 'Sân 1',
      'customerName': 'Khách vãng lai: Anh Tuấn',
      'customerPhone': '0912333444',
      'bookingType': 'WALK_IN',
      'playDate': '2026-10-30',
      'startTime': '17:00',
      'endTime': '19:00',
      'totalPrice': 240000.0,
      'status': 'CONFIRMED',
      'qrCheckInToken': 'QR-WI-889012',
      'paymentMethod': 'CASH',
    },
    {
      'id': 3,
      'bookingCode': 'MT-550123',
      'venueId': 1,
      'venueName': 'Sân CLB TDTT ĐH Thể Dục Thể Thao TP.HCM',
      'courtId': 4,
      'courtName': 'Sân 4',
      'customerName': 'Bảo trì thay lưới & vệ sinh thảm',
      'customerPhone': '-',
      'bookingType': 'MAINTENANCE',
      'playDate': '2026-10-30',
      'startTime': '18:00',
      'endTime': '20:00',
      'totalPrice': 0.0,
      'status': 'CONFIRMED',
      'qrCheckInToken': 'QR-MT-550123',
      'paymentMethod': 'NONE',
    },
  ];

  List<Map<String, dynamic>> matches = [
    {
      'post': {
        'id': 1,
        'hostId': 1,
        'hostName': 'Nguyễn Hữu Đạt',
        'hostSkill': 'TB_YEU',
        'bookingId': 1,
        'venueId': 1,
        'venueName': 'Sân CLB TDTT ĐH Thể Dục Thể Thao TP.HCM',
        'venueAddress': 'Đường Nội Bộ ĐHQG, P. Linh Trung, TP. Thủ Đức',
        'courtName': 'Sân 2',
        'title': 'Giao lưu vui vẻ tối nay - Tuyển thêm 2 bạn nam/nữ đánh đôi',
        'playDate': '2026-10-30',
        'startTime': '18:00',
        'endTime': '20:00',
        'requiredSkill': 'TB_YEU',
        'maxPlayers': 6,
        'currentPlayers': 4,
        'feePerPlayer': 65000.0,
        'status': 'OPEN',
      },
      'participants': [
        {
          'id': 1,
          'matchId': 1,
          'userId': 4,
          'userName': 'Lê Minh Hoàng',
          'userSkill': 'TRUNG_BINH',
          'userPhone': '0903222333',
          'status': 'PENDING',
        }
      ],
    },
    {
      'post': {
        'id': 2,
        'hostId': 4,
        'hostName': 'Lê Minh Hoàng',
        'hostSkill': 'TRUNG_BINH',
        'venueId': 2,
        'venueName': 'Sân Cầu Lông TPT Sport Làng Đại Học',
        'venueAddress': 'Đường A2, Khu Đô Thị ĐHQG TP.HCM, P. Đông Hòa, Dĩ An',
        'courtName': 'Sân 3',
        'title': 'Kèo trình độ Trung Bình - Cầu Hải Yến S70',
        'playDate': '2026-10-30',
        'startTime': '19:00',
        'endTime': '21:00',
        'requiredSkill': 'TRUNG_BINH',
        'maxPlayers': 8,
        'currentPlayers': 5,
        'feePerPlayer': 75000.0,
        'status': 'OPEN',
      },
      'participants': [],
    },
  ];

  List<Map<String, dynamic>> notifications = [
    {
      'id': 1,
      'title': 'Thanh toán PayOS VietQR thành công (#BK-202610)',
      'body': 'Vé đặt Sân 2 (18:00-20:00) tại Sân CLB TDTT ĐH Thể Dục Thể Thao TP.HCM đã sẵn sàng. Bấm để mở mã QR Check-in.',
      'type': 'PAYMENT',
      'targetScreen': 'S13',
      'isRead': false,
      'createdAt': 'Vừa xong',
    },
    {
      'id': 2,
      'title': 'Có người xin tham gia Kèo giao lưu của bạn!',
      'body': 'Lê Minh Hoàng (Trình độ: TRUNG_BINH) vừa gửi yêu cầu tham gia kèo tối nay của bạn.',
      'type': 'MATCHMAKING',
      'targetScreen': 'S15',
      'isRead': false,
      'createdAt': '15 phút trước',
    },
    {
      'id': 3,
      'title': 'Hoàn tiền hủy sân +240.000đ vào Ví Cầu Lông',
      'body': 'Đã hoàn 100% giá trị vé #BK-202601 vào Ví nội bộ của bạn.',
      'type': 'BOOKING',
      'targetScreen': 'S18',
      'isRead': true,
      'createdAt': 'Hôm qua',
    },
  ];

  /// Đánh giá sân của người chơi (S28 tạo, S08 hiển thị).
  List<Map<String, dynamic>> reviews = [];

  List<Map<String, dynamic>> walletTransactions = [
    {
      'title': 'Hoàn tiền 100% hủy vé #BK-202601 (Trước 24h)',
      'amount': 240000.0,
      'type': 'REFUND',
      'createdAt': '2026-10-29 14:20',
    },
    {
      'title': 'Nạp tiền khởi tạo Ví Cầu Lông',
      'amount': 110000.0,
      'type': 'TOPUP',
      'createdAt': '2026-10-28 09:00',
    },
  ];

  List<Map<String, dynamic>> adminPendingVenues = [
    {
      'id': 21,
      'ownerId': 2,
      'ownerName': 'Trần Chủ Sân',
      'name': 'Sân Cầu Lông TH Badminton Cơ sở 2 (Làng ĐH)',
      'address': 'Số 10 Đường Vành Đai ĐHQG, Đông Hòa, Dĩ An, Bình Dương',
      'latitude': 10.8790,
      'longitude': 106.8045,
      'totalCourts': 6,
      'basePricePerHour': 60000.0,
      'peakPricePerHour': 100000.0,
      'status': 'PENDING',
    }
  ];

  List<Map<String, dynamic>> payoutRequests = [
    {
      'id': 1,
      'payoutCode': 'PO-202689',
      'venueId': 1,
      'venueName': 'Sân CLB TDTT ĐH Thể Dục Thể Thao TP.HCM',
      'ownerName': 'Trần Chủ Sân',
      'grossAmount': 2000000.0,
      'commissionFee': 100000.0,
      'netPayoutAmount': 1900000.0,
      'bankName': 'Vietcombank',
      'bankAccountNumber': '0071001234567',
      'bankAccountHolder': 'TRAN CHU SAN',
      'status': 'PENDING',
      'createdAt': '2026-10-30 08:30',
    }
  ];

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
      _setScreen(history.last);
    }
  }

  bool get canGoBack => history.length > 1;

  /// Xóa lịch sử và bắt đầu lại từ [screenCode] (sau đăng nhập, đăng xuất, đổi vai trò):
  /// nút Back không quay về màn đăng nhập nữa.
  void resetTo(String screenCode) {
    history
      ..clear()
      ..add(screenCode);
    _setScreen(screenCode);
  }

  /// Chuyển tab ở thanh điều hướng: lịch sử chỉ còn [home] (+ [tab] nếu khác home),
  /// nên bấm qua lại giữa các tab không làm lịch sử dài ra, Back từ tab bất kỳ về tab chính.
  void goToTab(String tab, String home) {
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

  void switchDemoRole(String targetRole) {
    role = targetRole;
    if (targetRole == 'CUSTOMER') {
      userId = 1;
      fullName = 'Nguyễn Hữu Đạt (Customer)';
      email = 'customer@badminton.vn';
      skillLevel = 'TB_YEU';
      resetTo('S06');
    } else if (targetRole == 'COURT_OWNER') {
      userId = 2;
      fullName = 'Trần Chủ Sân (Court Owner)';
      email = 'owner@badminton.vn';
      skillLevel = 'KHA';
      resetTo('S19');
    } else if (targetRole == 'ADMIN') {
      userId = 3;
      fullName = 'Quản Trị Viên (Admin)';
      email = 'admin@badminton.vn';
      skillLevel = 'KHA';
      resetTo('S24');
    }
    syncFromBackend();
  }

  Future<void> syncFromBackend() async {
    try {
      final vList = await ApiService.get('/venues');
      if (vList is List && vList.isNotEmpty) {
        venues = List<Map<String, dynamic>>.from(vList);
      }
      final bList = await ApiService.get('/bookings/customer/$userId');
      if (bList is List && bList.isNotEmpty) {
        bookings = List<Map<String, dynamic>>.from(bList);
      }
      final mList = await ApiService.get('/matches');
      if (mList is List && mList.isNotEmpty) {
        matches = List<Map<String, dynamic>>.from(mList);
      }
      final nRes = await ApiService.get('/notifications/user/$userId');
      if (nRes is Map && nRes['items'] is List) {
        notifications = List<Map<String, dynamic>>.from(nRes['items']);
      }
      notifyListeners();
    } catch (_) {
      // Uses built-in state if backend is offline
    }
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
    ApiService.post('/notifications/user/$userId/read-all', {}).ignore();
  }
}
