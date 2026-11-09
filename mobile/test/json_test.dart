import 'package:flutter_test/flutter_test.dart';
import 'package:badminton_v2_mobile/core/api/json.dart';

void main() {
  test('asJson / asJsonList / asNum chịu được dữ liệu sai kiểu', () {
    expect(asJson(null), isEmpty);
    expect(asJson('x'), isEmpty);
    expect(asJson({'a': 1})['a'], 1);
    expect(asJsonList([{'a': 1}, 2, null]).length, 1);
    expect(asJsonList('x'), isEmpty);
    expect(asNum(12), 12);
    expect(asNum('12.5'), 12.5);
    expect(asNum('abc'), isNull);
    expect(asNum(null), isNull);
  });

  test('asJson tạo bản sao (sửa bản sao không đổi dữ liệu gốc)', () {
    final source = {'status': 'HELD'};
    final copy = asJson(source)..['status'] = 'CANCELLED';
    expect(source['status'], 'HELD');
    expect(copy['status'], 'CANCELLED');
  });
}
