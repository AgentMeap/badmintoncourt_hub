/// Tiện ích chuyển dữ liệu JSON động sang kiểu dùng trong app.
typedef Json = Map<String, dynamic>;

/// Map JSON, hoặc Map rỗng nếu không phải Map.
Json asJson(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

/// Danh sách Map JSON (bỏ qua phần tử không phải Map).
List<Json> asJsonList(dynamic value) => value is List
    ? [for (final e in value) if (e is Map) Map<String, dynamic>.from(e)]
    : <Json>[];

/// Số từ JSON (chấp nhận cả chuỗi số).
num? asNum(dynamic value) => value is num ? value : num.tryParse('${value ?? ''}');
