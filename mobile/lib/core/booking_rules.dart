/// Quy tắc nghiệp vụ đặt sân dùng chung cho S09 (chọn giờ), S10 (thanh toán),
/// S14 (hủy / đổi lịch). Toàn bộ là hàm thuần, không phụ thuộc giao diện,
/// để mọi màn hình tính giá, kiểm tra trùng lịch và hoàn tiền giống nhau.
class BookingRules {
  BookingRules._();

  /// Thời gian giữ chỗ (HELD) chờ thanh toán.
  static const int holdMinutes = 5;

  /// Từ giờ này trở đi tính giá giờ vàng (thứ 2 - thứ 6). Cuối tuần luôn là giờ vàng.
  static const int peakStartHour = 17;

  /// Chính sách hủy: >= 24h hoàn 100%, 6h - 24h hoàn 50%, < 6h không hoàn.
  static const int fullRefundHours = 24;
  static const int halfRefundHours = 6;

  /// Đổi lịch: tối đa 1 lần, phải trước giờ chơi ít nhất 6 tiếng.
  static const int maxReschedules = 1;
  static const int rescheduleCutoffHours = 6;

  static const _inactiveStatuses = {'CANCELLED', 'REFUNDED'};
  static const _paidStatuses = {'CONFIRMED', 'PAID'};
  static const _usedStatuses = {'CHECKED_IN', 'COMPLETED'};

  // ---------------------------------------------------------------- Thời gian

  static int hourOf(String time) => int.tryParse(time.split(':').first) ?? 0;

  static String hourLabel(int h) => '${h.toString().padLeft(2, '0')}:00';

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// DateTime -> "2026-10-30"
  static String dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// "2026-10-30" + "18:00" -> DateTime
  static DateTime startOf(String playDate, String time) {
    final d = DateTime.tryParse(playDate) ?? dateOnly(DateTime.now());
    final parts = time.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(d.year, d.month, d.day, h, m);
  }

  /// Khung giờ đã bắt đầu (không cho đặt nữa).
  static bool isPast(DateTime date, String hour, {DateTime? now}) =>
      !startOf(dateKey(date), hour).isAfter(now ?? DateTime.now());

  // ---------------------------------------------------------------- Cơ sở

  static num _num(dynamic v, num fallback) =>
      v is num ? v : (num.tryParse('$v') ?? fallback);

  /// Các khung 1 giờ trong giờ mở cửa. Mở 05:00, đóng 23:00 -> 05:00 ... 22:00.
  static List<String> operatingHours(Map<String, dynamic> venue) {
    final open = hourOf(venue['openTime']?.toString() ?? '05:00');
    var close = hourOf(venue['closeTime']?.toString() ?? '23:00');
    if (close <= open) close = 24;
    return [for (var h = open; h < close; h++) hourLabel(h)];
  }

  static int courtCount(Map<String, dynamic> venue) =>
      _num(venue['totalCourts'], 4).toInt().clamp(1, 30).toInt();

  // ---------------------------------------------------------------- Giá

  static bool isPeak(DateTime date, String hour) =>
      date.weekday >= DateTime.saturday || hourOf(hour) >= peakStartHour;

  static num priceOf(Map<String, dynamic> venue, DateTime date, String hour) {
    final base = _num(venue['basePricePerHour'], 0);
    final peak = _num(venue['peakPricePerHour'], base);
    return isPeak(date, hour) ? peak : base;
  }

  static num priceOfRange(Map<String, dynamic> venue, DateTime date, Iterable<String> hours) =>
      hours.fold<num>(0, (sum, h) => sum + priceOf(venue, date, h));

  /// Chi tiết tiền sân theo từng mức giá: [(nhãn, số giờ, đơn giá)].
  static List<(String, int, num)> priceBreakdown(
      Map<String, dynamic> venue, DateTime date, Iterable<String> hours) {
    var normal = 0, peak = 0;
    for (final h in hours) {
      isPeak(date, h) ? peak++ : normal++;
    }
    final base = _num(venue['basePricePerHour'], 0);
    final peakPrice = _num(venue['peakPricePerHour'], base);
    return [
      if (normal > 0) ('Giờ thường', normal, base),
      if (peak > 0) ('Giờ vàng', peak, peakPrice),
    ];
  }

  /// "18:00","21:00" -> ["18:00","19:00","20:00"]
  static List<String> hoursOfRange(String start, String end) {
    final s = hourOf(start), e = hourOf(end);
    return [for (var h = s; h < e; h++) hourLabel(h)];
  }

  // ---------------------------------------------------------------- Lịch sân

  /// Booking còn chiếm sân không (bỏ qua vé đã hủy và giữ chỗ đã hết hạn).
  static bool occupiesCourt(Map<String, dynamic> b, {DateTime? now}) {
    final status = b['status']?.toString() ?? '';
    if (_inactiveStatuses.contains(status)) return false;
    if (status == 'HELD') {
      final exp = b['holdExpiresAt'];
      if (exp is int) {
        return exp > (now ?? DateTime.now()).millisecondsSinceEpoch;
      }
    }
    return true;
  }

  /// Giờ -> 'MAINTENANCE' | 'BOOKED' của một sân trong một ngày.
  static Map<String, String> occupancy(
    List<Map<String, dynamic>> bookings, {
    required dynamic venueId,
    required int courtId,
    required String playDate,
    String? excludeBookingCode,
    DateTime? now,
  }) {
    final result = <String, String>{};
    for (final b in bookings) {
      if ('${b['venueId']}' != '$venueId') continue;
      if (_num(b['courtId'], -1).toInt() != courtId) continue;
      if (b['playDate']?.toString() != playDate) continue;
      if (excludeBookingCode != null && b['bookingCode'] == excludeBookingCode) continue;
      if (!occupiesCourt(b, now: now)) continue;
      final type = b['bookingType'] == 'MAINTENANCE' ? 'MAINTENANCE' : 'BOOKED';
      for (final h in hoursOfRange(
          b['startTime']?.toString() ?? '00:00', b['endTime']?.toString() ?? '00:00')) {
        result[h] = type;
      }
    }
    return result;
  }

  // ---------------------------------------------------------------- Hủy / đổi lịch

  static bool isPaid(Map<String, dynamic> b) => _paidStatuses.contains(b['status']?.toString());

  static Duration timeUntilStart(Map<String, dynamic> b, {DateTime? now}) =>
      startOf(b['playDate']?.toString() ?? '', b['startTime']?.toString() ?? '00:00')
          .difference(now ?? DateTime.now());

  /// % hoàn tiền khi hủy. Vé chưa thanh toán -> 0 (không có gì để hoàn).
  static int refundPercent(Map<String, dynamic> b, {DateTime? now}) {
    if (!isPaid(b)) return 0;
    final left = timeUntilStart(b, now: now);
    if (left >= const Duration(hours: fullRefundHours)) return 100;
    if (left >= const Duration(hours: halfRefundHours)) return 50;
    return 0;
  }

  static num refundAmount(Map<String, dynamic> b, {DateTime? now}) =>
      (_num(b['totalPrice'], 0) * refundPercent(b, now: now) / 100).round();

  /// Lý do không được hủy, null nếu được hủy.
  static String? cancelBlockReason(Map<String, dynamic> b, {DateTime? now}) {
    final status = b['status']?.toString() ?? '';
    if (_inactiveStatuses.contains(status)) return 'Vé này đã được hủy trước đó.';
    if (_usedStatuses.contains(status)) return 'Vé đã sử dụng, không thể hủy.';
    if (timeUntilStart(b, now: now) <= Duration.zero) return 'Đã đến giờ chơi, không thể hủy.';
    return null;
  }

  /// Lý do không được đổi lịch, null nếu được đổi.
  static String? rescheduleBlockReason(Map<String, dynamic> b, {DateTime? now}) {
    final cancel = cancelBlockReason(b, now: now);
    if (cancel != null) return cancel;
    if (!isPaid(b)) return 'Vé chưa thanh toán, không thể đổi lịch.';
    if (_num(b['rescheduledCount'], 0) >= maxReschedules) {
      return 'Mỗi vé chỉ được đổi lịch $maxReschedules lần.';
    }
    if (timeUntilStart(b, now: now) < const Duration(hours: rescheduleCutoffHours)) {
      return 'Chỉ được đổi lịch trước giờ chơi ít nhất $rescheduleCutoffHours tiếng.';
    }
    return null;
  }
}

/// Số liệu tài chính của chủ sân, tính từ dữ liệu đặt sân thật (S19, S23).
class OwnerFinance {
  OwnerFinance._();

  /// Phí hoa hồng nền tảng trên doanh thu thu hộ online.
  static const double commissionRate = 0.05;

  static const _revenueStatuses = {'CONFIRMED', 'PAID', 'CHECKED_IN', 'COMPLETED'};
  static const _onlinePaymentMethods = {'PAYOS_QR', 'WALLET'};

  static num _num(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);

  /// Các cơ sở của chủ sân hiện tại (dữ liệu demo: nếu không khớp ownerId thì lấy tất cả).
  static List<Map<String, dynamic>> ownerVenues(List<Map<String, dynamic>> venues, int userId) {
    final mine = venues.where((v) => '${v['ownerId']}' == '$userId').toList();
    return mine.isEmpty ? venues : mine;
  }

  static Set<String> idsOf(List<Map<String, dynamic>> venues) => {for (final v in venues) '${v['id']}'};

  static bool _isRevenue(Map<String, dynamic> b) =>
      b['bookingType'] != 'MAINTENANCE' && _revenueStatuses.contains(b['status']?.toString());

  /// Ca đặt (online + vãng lai) có doanh thu của các cơ sở trong một ngày.
  static List<Map<String, dynamic>> sessionsOn(
          List<Map<String, dynamic>> bookings, Set<String> venueIds, String playDate) =>
      bookings
          .where((b) =>
              venueIds.contains('${b['venueId']}') && b['playDate'] == playDate && _isRevenue(b))
          .toList();

  static num revenueOf(Iterable<Map<String, dynamic>> bookings) =>
      bookings.fold<num>(0, (s, b) => s + _num(b['totalPrice']));

  /// Vé online đã thu hộ qua PayOS / Ví, chưa nằm trong yêu cầu giải ngân nào.
  static List<Map<String, dynamic>> settleable(
          List<Map<String, dynamic>> bookings, Set<String> venueIds) =>
      bookings
          .where((b) =>
              venueIds.contains('${b['venueId']}') &&
              b['bookingType'] == 'ONLINE' &&
              _onlinePaymentMethods.contains(b['paymentMethod']?.toString()) &&
              _isRevenue(b) &&
              b['payoutCode'] == null)
          .toList();

  /// Tổng giá trị giao dịch online (GMV) toàn sàn: vé online đã thanh toán qua PayOS / Ví.
  static num platformGmv(List<Map<String, dynamic>> bookings) => revenueOf(bookings.where((b) =>
      b['bookingType'] == 'ONLINE' &&
      _onlinePaymentMethods.contains(b['paymentMethod']?.toString()) &&
      _isRevenue(b)));

  static num commissionOf(num gross) => (gross * commissionRate).round();

  static num netOf(num gross) => gross - commissionOf(gross);
}
