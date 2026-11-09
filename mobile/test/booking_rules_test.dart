import 'package:flutter_test/flutter_test.dart';
import 'package:badminton_v2_mobile/core/booking_rules.dart';

/// Luật đặt sân dùng chung cho S09 - S14, S21 (hàm thuần, truyền `now` cố định để test ổn định).
void main() {
  // 09/11/2026 là thứ 2, 14/11/2026 là thứ 7
  final monday = DateTime(2026, 11, 9);
  final saturday = DateTime(2026, 11, 14);
  final venue = <String, dynamic>{
    'openTime': '05:00',
    'closeTime': '23:00',
    'totalCourts': 6,
    'basePricePerHour': 60000,
    'peakPricePerHour': 100000,
  };

  group('Thời gian', () {
    test('hourOf / hourLabel / dateKey', () {
      expect(BookingRules.hourOf('18:30'), 18);
      expect(BookingRules.hourOf('abc'), 0);
      expect(BookingRules.hourLabel(7), '07:00');
      expect(BookingRules.dateKey(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('hoursOfRange chia khung 1 giờ', () {
      expect(BookingRules.hoursOfRange('18:00', '21:00'), ['18:00', '19:00', '20:00']);
      expect(BookingRules.hoursOfRange('18:00', '18:00'), isEmpty);
    });

    test('isPast: khung giờ đã bắt đầu thì không đặt được', () {
      expect(BookingRules.isPast(monday, '18:00', now: DateTime(2026, 11, 9, 18)), isTrue);
      expect(BookingRules.isPast(monday, '18:00', now: DateTime(2026, 11, 9, 17, 59)), isFalse);
    });
  });

  group('Cơ sở & giá', () {
    test('operatingHours theo giờ mở / đóng cửa', () {
      final hours = BookingRules.operatingHours(venue);
      expect(hours.length, 18);
      expect(hours.first, '05:00');
      expect(hours.last, '22:00');
      // Đóng cửa 00:00 nghĩa là mở tới nửa đêm
      expect(BookingRules.operatingHours({'openTime': '06:00', 'closeTime': '00:00'}).last, '23:00');
    });

    test('courtCount mặc định 4, giới hạn 1..30', () {
      expect(BookingRules.courtCount(venue), 6);
      expect(BookingRules.courtCount({}), 4);
      expect(BookingRules.courtCount({'totalCourts': 99}), 30);
    });

    test('giờ vàng: từ 17h ngày thường, cả ngày cuối tuần', () {
      expect(BookingRules.isPeak(monday, '16:00'), isFalse);
      expect(BookingRules.isPeak(monday, '17:00'), isTrue);
      expect(BookingRules.isPeak(saturday, '08:00'), isTrue);
    });

    test('priceOfRange và priceBreakdown', () {
      expect(BookingRules.priceOfRange(venue, monday, ['16:00', '17:00']), 160000);
      expect(BookingRules.priceOfRange(venue, saturday, ['08:00', '09:00']), 200000);
      expect(BookingRules.priceBreakdown(venue, monday, ['15:00', '16:00', '17:00']), [
        ('Giờ thường', 2, 60000),
        ('Giờ vàng', 1, 100000),
      ]);
    });
  });

  group('Lịch sân', () {
    final now = DateTime(2026, 11, 9, 10);

    test('holdExpiryMs đọc được millis và chuỗi máy chủ', () {
      expect(BookingRules.holdExpiryMs(123), 123);
      expect(BookingRules.holdExpiryMs('2026-11-09 18:05:00'),
          DateTime(2026, 11, 9, 18, 5).millisecondsSinceEpoch);
      expect(BookingRules.holdExpiryMs('khong-hop-le'), isNull);
      expect(BookingRules.holdExpiryMs(null), isNull);
    });

    test('occupiesCourt bỏ qua vé hủy và giữ chỗ hết hạn', () {
      expect(BookingRules.occupiesCourt({'status': 'CONFIRMED'}, now: now), isTrue);
      expect(BookingRules.occupiesCourt({'status': 'CANCELLED'}, now: now), isFalse);
      expect(
          BookingRules.occupiesCourt({'status': 'HELD', 'holdExpiresAt': '2026-11-09 10:03:00'}, now: now), isTrue);
      expect(
          BookingRules.occupiesCourt({'status': 'HELD', 'holdExpiresAt': '2026-11-09 09:59:00'}, now: now), isFalse);
    });

    test('occupancy: đúng sân, đúng ngày, phân biệt bảo trì', () {
      final bookings = [
        {'venueId': 1, 'courtId': 7, 'playDate': '2026-11-09', 'startTime': '18:00', 'endTime': '20:00', 'status': 'CONFIRMED'},
        {'venueId': 1, 'courtId': 7, 'playDate': '2026-11-09', 'startTime': '20:00', 'endTime': '21:00', 'status': 'CONFIRMED', 'bookingType': 'MAINTENANCE'},
        {'venueId': 1, 'courtId': 7, 'playDate': '2026-11-09', 'startTime': '06:00', 'endTime': '07:00', 'status': 'CANCELLED'},
        {'venueId': 1, 'courtId': 8, 'playDate': '2026-11-09', 'startTime': '09:00', 'endTime': '10:00', 'status': 'CONFIRMED'},
        {'venueId': 1, 'courtId': 7, 'playDate': '2026-11-10', 'startTime': '09:00', 'endTime': '10:00', 'status': 'CONFIRMED'},
      ];
      expect(
        BookingRules.occupancy(bookings, venueId: 1, courtId: 7, playDate: '2026-11-09', now: now),
        {'18:00': 'BOOKED', '19:00': 'BOOKED', '20:00': 'MAINTENANCE'},
      );
    });
  });

  group('Hủy / đổi lịch', () {
    final paid = {'status': 'CONFIRMED', 'playDate': '2026-11-11', 'startTime': '18:00', 'totalPrice': 240000};

    test('refundPercent: >=24h 100%, 6-24h 50%, <6h 0%, chưa trả tiền 0%', () {
      expect(BookingRules.refundPercent(paid, now: DateTime(2026, 11, 9, 18)), 100);
      expect(BookingRules.refundPercent(paid, now: DateTime(2026, 11, 11, 8)), 50);
      expect(BookingRules.refundPercent(paid, now: DateTime(2026, 11, 11, 15)), 0);
      expect(BookingRules.refundPercent({...paid, 'status': 'HELD'}, now: DateTime(2026, 11, 9)), 0);
      expect(BookingRules.refundAmount(paid, now: DateTime(2026, 11, 11, 8)), 120000);
    });

    test('cancelBlockReason', () {
      final now = DateTime(2026, 11, 9, 12);
      expect(BookingRules.cancelBlockReason(paid, now: now), isNull);
      expect(BookingRules.cancelBlockReason({...paid, 'status': 'CANCELLED'}, now: now), isNotNull);
      expect(BookingRules.cancelBlockReason({...paid, 'status': 'CHECKED_IN'}, now: now), isNotNull);
      expect(BookingRules.cancelBlockReason(paid, now: DateTime(2026, 11, 11, 18, 30)), isNotNull);
    });

    test('rescheduleBlockReason: 1 lần, trước 6 tiếng, phải đã thanh toán', () {
      final now = DateTime(2026, 11, 9, 12);
      expect(BookingRules.rescheduleBlockReason(paid, now: now), isNull);
      expect(BookingRules.rescheduleBlockReason({...paid, 'rescheduledCount': 1}, now: now), isNotNull);
      expect(BookingRules.rescheduleBlockReason({...paid, 'status': 'HELD'}, now: now), isNotNull);
      expect(BookingRules.rescheduleBlockReason(paid, now: DateTime(2026, 11, 11, 13)), isNotNull);
    });
  });

  group('OwnerFinance', () {
    final bookings = [
      {'venueId': 1, 'playDate': '2026-11-09', 'status': 'CONFIRMED', 'bookingType': 'ONLINE', 'paymentMethod': 'WALLET', 'totalPrice': 200000},
      {'venueId': 1, 'playDate': '2026-11-09', 'status': 'CHECKED_IN', 'bookingType': 'WALK_IN', 'paymentMethod': 'CASH', 'totalPrice': 120000},
      {'venueId': 1, 'playDate': '2026-11-09', 'status': 'CONFIRMED', 'bookingType': 'MAINTENANCE', 'paymentMethod': 'NONE', 'totalPrice': 0},
      {'venueId': 1, 'playDate': '2026-11-09', 'status': 'CANCELLED', 'bookingType': 'ONLINE', 'paymentMethod': 'PAYOS_QR', 'totalPrice': 300000},
      {'venueId': 2, 'playDate': '2026-11-09', 'status': 'CONFIRMED', 'bookingType': 'ONLINE', 'paymentMethod': 'PAYOS_QR', 'totalPrice': 150000},
      {'venueId': 1, 'playDate': '2026-11-08', 'status': 'COMPLETED', 'bookingType': 'ONLINE', 'paymentMethod': 'PAYOS_QR', 'totalPrice': 90000, 'payoutCode': 'PO-1'},
    ];

    test('phí 5% và thực nhận', () {
      expect(OwnerFinance.commissionOf(100000), 5000);
      expect(OwnerFinance.netOf(100000), 95000);
    });

    test('sessionsOn: chỉ ca có doanh thu của cơ sở trong ngày (bỏ bảo trì, vé hủy)', () {
      final s = OwnerFinance.sessionsOn(bookings, {'1'}, '2026-11-09');
      expect(s.length, 2);
      expect(OwnerFinance.revenueOf(s), 320000);
    });

    test('settleable: chỉ vé online đã thu hộ, chưa nằm trong yêu cầu giải ngân', () {
      final s = OwnerFinance.settleable(bookings, {'1', '2'});
      expect(OwnerFinance.revenueOf(s), 350000);
    });

    test('platformGmv tính vé online đã thanh toán', () {
      expect(OwnerFinance.platformGmv(bookings), 440000);
    });
  });
}
