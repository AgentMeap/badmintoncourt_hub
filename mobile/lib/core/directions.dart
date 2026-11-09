import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

/// Phương tiện khi mở Google Maps dẫn đường.
enum TravelMode {
  motorbike('l', 'two-wheeler', 'Xe máy', Icons.two_wheeler),
  car('d', 'driving', 'Ô tô', Icons.directions_car_outlined),
  walk('w', 'walking', 'Đi bộ', Icons.directions_walk);

  const TravelMode(this.androidCode, this.webMode, this.label, this.icon);

  /// Tham số `mode` của intent `google.navigation:` trên Android.
  final String androidCode;

  /// Tham số `travelmode` của Google Maps URL (iOS / web / máy không có app Google Maps).
  final String webMode;
  final String label;
  final IconData icon;

  /// Tên phương tiện cho API tìm đường của backend (`/api/routes?mode=`).
  String get apiName => switch (this) {
        TravelMode.motorbike => 'motorbike',
        TravelMode.car => 'car',
        TravelMode.walk => 'walk',
      };
}

/// Mở Google Maps để dẫn đường từng ngã rẽ (có giọng nói, tự tìm lại đường khi đi sai).
/// App không tự làm phần này; trong app chỉ xem trước vị trí / tuyến.
class Directions {
  Directions._();

  /// Android có app Google Maps: vào thẳng chế độ dẫn đường (không phải bấm "Bắt đầu").
  /// Nơi khác: mở trang chỉ đường của Google Maps (điểm đi = vị trí hiện tại).
  static Future<bool> startNavigation(double lat, double lng, TravelMode mode) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final nav = Uri.parse('google.navigation:q=$lat,$lng&mode=${mode.androidCode}');
      try {
        if (await launchUrl(nav, mode: LaunchMode.externalApplication)) return true;
      } catch (e) {
        debugPrint('[directions] $e');
      }
    }
    final web = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '$lat,$lng',
      'travelmode': mode.webMode,
      'dir_action': 'navigate',
    });
    return _launch(web);
  }

  /// Xem vị trí sân trên Google Maps (ảnh, đánh giá, giờ mở cửa của Google).
  static Future<bool> showOnMap(double lat, double lng) =>
      _launch(Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '$lat,$lng'}));

  static Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[directions] $e');
      return false;
    }
  }
}

/// Bottom sheet "Dẫn đường tới sân": chọn phương tiện rồi mở Google Maps.
/// [distanceKm]: khoảng cách đường thẳng (để người dùng ước lượng), có thể null.
Future<void> showDirectionsSheet(BuildContext context, Map<String, dynamic> venue, {double? distanceKm}) {
  final lat = UiFmt.toNum(venue['latitude'], 0).toDouble();
  final lng = UiFmt.toNum(venue['longitude'], 0).toDouble();
  final messenger = ScaffoldMessenger.of(context);

  Future<void> run(BuildContext sheetContext, Future<bool> Function() action) async {
    Navigator.pop(sheetContext);
    final ok = await action();
    if (!ok) {
      messenger.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Không mở được Google Maps. Hãy cài hoặc cập nhật ứng dụng Google Maps.'),
      ));
    }
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final cs = theme.colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Dẫn đường tới', style: theme.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
              Text('${venue['name'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                [
                  if ('${venue['address'] ?? ''}'.isNotEmpty) '${venue['address']}',
                  if (distanceKm != null) 'khoảng ${distanceKm.toStringAsFixed(1)} km đường thẳng',
                ].join(' • '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              for (final mode in TravelMode.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: mode == TravelMode.motorbike
                      ? FilledButton.icon(
                          onPressed: () => run(sheetContext, () => Directions.startNavigation(lat, lng, mode)),
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                          icon: Icon(mode.icon),
                          label: Text('Bắt đầu dẫn đường • ${mode.label}'),
                        )
                      : OutlinedButton.icon(
                          onPressed: () => run(sheetContext, () => Directions.startNavigation(lat, lng, mode)),
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                          icon: Icon(mode.icon),
                          label: Text(mode.label),
                        ),
                ),
              TextButton.icon(
                onPressed: () => run(sheetContext, () => Directions.showOnMap(lat, lng)),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Xem vị trí sân trên Google Maps'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
