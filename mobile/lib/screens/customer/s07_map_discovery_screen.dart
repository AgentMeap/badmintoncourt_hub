import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/directions.dart';
import 'package:badminton_v2_mobile/core/location_service.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/route_plan.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S07: OpenStreetMap Discovery Screen (Module 2)
// - Vị trí người dùng lấy từ GPS thật (geolocator); chưa có quyền / tắt GPS thì dùng
//   Làng Đại học và báo rõ trên màn hình kèm nút "Bật vị trí".
// - Khoảng cách và lọc bán kính tính từ vị trí đó (đường chim bay, latlong2).
// - Tuyến theo đường phố: backend tìm đường bằng A* trên bản đồ OpenStreetMap TP.HCM
//   (GET /api/routes), vẽ nét liền + quãng đường, thời gian, danh sách chỗ rẽ.
//   Bản đồ đường chưa sẵn sàng / ngoài vùng / mất mạng -> nét đứt hướng chim bay.
// - "Dẫn đường" mở Google Maps vào thẳng chế độ dẫn đường (xe máy / ô tô / đi bộ).
// - Có ghi công OpenStreetMap (bắt buộc theo chính sách sử dụng tile của OSM).
class S07MapDiscoveryScreen extends StatefulWidget {
  final AppState appState;
  const S07MapDiscoveryScreen({super.key, required this.appState});

  @override
  State<S07MapDiscoveryScreen> createState() => _S07MapDiscoveryScreenState();
}

class _S07MapDiscoveryScreenState extends State<S07MapDiscoveryScreen> {
  static final _distance = Distance();
  final _map = MapController();
  bool _mapReady = false;
  Map<String, dynamic>? _focusedVenue;
  bool _showRoute = false;
  bool _locating = false;

  // Tuyến theo đường phố
  TravelMode _mode = TravelMode.motorbike;
  RoutePlan? _plan;
  String? _planKey;
  String? _planError;
  bool _planLoading = false;
  int _planSeq = 0;

  /// Bán kính lọc (km); vô cực = tất cả.
  double _maxRadiusKm = double.infinity;

  AppState get _app => widget.appState;
  LatLng get _userGps => LatLng(_app.userLatitude, _app.userLongitude);
  bool get _filtered => _maxRadiusKm.isFinite;

  @override
  void initState() {
    super.initState();
    _focusedVenue = _nearestVenue();
    // Sau khung hình đầu tiên (không gọi setState trong initState)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _locate();
    });
  }

  Map<String, dynamic>? _nearestVenue() {
    final venues = _app.venues;
    if (venues.isEmpty) return null;
    return venues.reduce((a, b) => _kmOf(a) <= _kmOf(b) ? a : b);
  }

  /// Lấy GPS rồi đưa bản đồ về vị trí người dùng.
  Future<void> _locate({bool force = false}) async {
    if (_locating) return;
    setState(() => _locating = true);
    final status = _app.locationStatus;
    if (force && (status == LocationStatus.serviceDisabled || status == LocationStatus.deniedForever)) {
      await LocationService.openSettings(status);
    }
    await _app.refreshLocation(force: force);
    if (!mounted) return;
    setState(() {
      _locating = false;
      // Danh sách sân đã được tải lại theo vị trí mới: giữ sân đang chọn nếu còn
      final id = '${_focusedVenue?['id']}';
      _focusedVenue = _app.venues.where((v) => '${v['id']}' == id).firstOrNull ?? _nearestVenue();
    });
    final f = _focusedVenue;
    if (_showRoute && f != null) {
      _loadRoute(f);
    } else if (_mapReady) {
      _map.move(_userGps, 14);
    }
  }

  void _fitRoute(Map<String, dynamic> venue) {
    if (!_mapReady) return;
    final plan = _plan;
    _map.fitCamera(CameraFit.coordinates(
      coordinates: plan != null && _planKey == _keyFor(venue) ? plan.points : [_userGps, _posOf(venue)],
      padding: const EdgeInsets.fromLTRB(48, 72, 48, 48),
      maxZoom: 16,
    ));
  }

  void _focus(Map<String, dynamic> v, {bool showRoute = true}) {
    setState(() {
      _focusedVenue = v;
      _showRoute = showRoute;
    });
    if (showRoute) {
      _fitRoute(v);
      _loadRoute(v);
    }
  }

  /// Khoá tuyến: cùng sân + phương tiện + vị trí (làm tròn ~100 m) thì không tải lại.
  String _keyFor(Map<String, dynamic> venue) =>
      '${venue['id']}|${_mode.apiName}|${_app.userLatitude.toStringAsFixed(3)},${_app.userLongitude.toStringAsFixed(3)}';

  /// Hỏi backend tuyến theo đường phố tới [venue]; lỗi thì giữ nét đứt chim bay.
  Future<void> _loadRoute(Map<String, dynamic> venue) async {
    final key = _keyFor(venue);
    if (key == _planKey && (_plan != null || _planLoading)) {
      _fitRoute(venue);
      return;
    }
    final seq = ++_planSeq;
    setState(() {
      _planKey = key;
      _plan = null;
      _planError = null;
      _planLoading = true;
    });
    try {
      final res = await Repos.route.route(
        fromLat: _app.userLatitude,
        fromLng: _app.userLongitude,
        venueId: venue['id'],
        mode: _mode.apiName,
      );
      if (!mounted || seq != _planSeq) return;
      final plan = RoutePlan.fromJson(res);
      setState(() {
        _plan = plan;
        _planLoading = false;
        _planError = plan == null ? 'Không đọc được dữ liệu tuyến đường.' : null;
      });
      _fitRoute(venue);
    } catch (e) {
      if (!mounted || seq != _planSeq) return;
      setState(() {
        _planLoading = false;
        _planKey = null; // cho phép thử lại
        _planError = _routeErrorText(e);
      });
    }
  }

  static String _routeErrorText(Object e) {
    if (e is ApiException) {
      if (e.statusCode == 503) return 'Máy chủ đang chuẩn bị bản đồ đường, tạm hiện hướng chim bay.';
      if (e.statusCode == 422 || e.statusCode == 404) return e.message;
      if (e.isConnectivity) return 'Không kết nối được máy chủ, tạm hiện hướng chim bay.';
      return e.message;
    }
    return 'Không tải được tuyến đường, tạm hiện hướng chim bay.';
  }

  void _setMode(TravelMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    final f = _focusedVenue;
    if (_showRoute && f != null) _loadRoute(f);
  }

  /// Danh sách chỉ dẫn từng chỗ rẽ; chạm một bước để xem vị trí trên bản đồ.
  void _showSteps(RoutePlan plan, Map<String, dynamic> venue) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final cs = theme.colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.92,
          builder: (_, controller) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${plan.durationLabel} • ${plan.distanceLabel}',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text('${_mode.label} tới ${venue['name']} • thời gian ước tính, chưa tính kẹt xe',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant),
              Expanded(
                child: ListView.separated(
                  controller: controller,
                  itemCount: plan.steps.length,
                  separatorBuilder: (_, _) => Divider(height: 1, indent: 64, color: cs.outlineVariant),
                  itemBuilder: (_, i) {
                    final step = plan.steps[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: step.type == 'ARRIVE' ? cs.primary : cs.secondaryContainer,
                        child: Icon(step.icon,
                            color: step.type == 'ARRIVE' ? cs.onPrimary : cs.onSecondaryContainer),
                      ),
                      title: Text(step.instruction),
                      subtitle: step.distanceMeters > 0 ? Text(RoutePlan.formatDistance(step.distanceMeters)) : null,
                      onTap: step.point == null || !_mapReady
                          ? null
                          : () {
                              Navigator.pop(sheetContext);
                              _map.move(step.point!, 17);
                            },
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      showDirectionsSheet(context, venue, distanceKm: _kmOf(venue));
                    },
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                    icon: const Icon(Icons.navigation_outlined),
                    label: const Text('Bắt đầu dẫn đường bằng Google Maps'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _visibleVenues() =>
      _app.venues.where((v) => !_filtered || _kmOf(v) <= _maxRadiusKm).toList();

  LatLng _posOf(Map<String, dynamic> v) => LatLng(
        UiFmt.toNum(v['latitude'], 0).toDouble(),
        UiFmt.toNum(v['longitude'], 0).toDouble(),
      );

  /// Khoảng cách đường chim bay (km) từ vị trí người dùng.
  double _kmOf(Map<String, dynamic> v) => _distance.as(LengthUnit.Meter, _userGps, _posOf(v)) / 1000;

  String _kmLabel(Map<String, dynamic> v) {
    final km = _kmOf(v);
    return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
  }

  Widget _buildMapWidget(Map<String, dynamic> selected) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dest = _posOf(selected);

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _userGps,
            initialZoom: 13.8,
            onMapReady: () {
              _mapReady = true;
              if (_showRoute) _fitRoute(selected);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.badminton.badminton_v2_mobile',
            ),
            if (_showRoute)
              PolylineLayer(
                polylines: [
                  if (_plan != null && _planKey == _keyFor(selected))
                    // Tuyến theo đường phố (A* trên bản đồ OSM)
                    Polyline(
                      points: _plan!.points,
                      strokeWidth: 5,
                      color: cs.primary,
                      borderStrokeWidth: 2,
                      borderColor: cs.surface,
                    )
                  else
                    // Nét đứt = hướng đường chim bay (chưa có / không lấy được tuyến)
                    Polyline(
                      points: [_userGps, dest],
                      strokeWidth: 4,
                      color: cs.tertiary,
                      pattern: StrokePattern.dashed(segments: [12, 8]),
                    ),
                ],
              ),
            MarkerLayer(
              markers: [
                // Vị trí người dùng (xám khi đang dùng vị trí mặc định)
                Marker(
                  point: _userGps,
                  width: 36,
                  height: 36,
                  child: Semantics(
                    label: _app.hasRealLocation ? 'Vị trí của bạn' : 'Vị trí mặc định Làng Đại học',
                    child: Container(
                      decoration: BoxDecoration(
                        color: (_app.hasRealLocation ? cs.tertiary : cs.outline).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: _app.hasRealLocation ? cs.tertiary : cs.outline,
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.surface, width: 3),
                        ),
                      ),
                    ),
                  ),
                ),
                // Ghim các sân (theo bán kính đã lọc)
                ..._visibleVenues().map((v) {
                  final isFocused = '${selected['id']}' == '${v['id']}';
                  return Marker(
                    point: _posOf(v),
                    width: 96,
                    height: 64,
                    alignment: Alignment.topCenter,
                    child: Semantics(
                      button: true,
                      label: '${v['name']}, ${_kmLabel(v)}',
                      child: GestureDetector(
                        onTap: () => _focus(v),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isFocused ? cs.primary : cs.surface,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: cs.primary, width: 1.5),
                                boxShadow: [
                                  BoxShadow(color: cs.shadow.withValues(alpha: 0.15), blurRadius: 4),
                                ],
                              ),
                              child: Text(
                                '${UiFmt.k(UiFmt.toNum(v['basePricePerHour'], 0))}/giờ',
                                maxLines: 1,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: isFocused ? cs.onPrimary : cs.primary,
                                ),
                              ),
                            ),
                            Icon(Icons.location_on, size: 30, color: isFocused ? cs.primary : cs.secondary),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Container(
                margin: const EdgeInsets.all(6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: cs.outlineVariant, width: 0.5),
                ),
                child: Text(
                  '© OpenStreetMap',
                  style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
        // Nút "Vị trí của tôi"
        Positioned(
          top: 10,
          right: 10,
          child: Material(
            color: cs.surface,
            elevation: 2,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Về vị trí của tôi',
              onPressed: _locating ? null : () => _locate(force: true),
              icon: _locating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_app.hasRealLocation ? Icons.my_location : Icons.location_searching, color: cs.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVenueInfoCard(Map<String, dynamic> selected, {bool isSidePanel = false}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    void openVenue() {
      _app.selectedVenue = selected;
      _app.goTo('S08');
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        border: isSidePanel
            ? Border(left: BorderSide(color: cs.outlineVariant))
            : Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected['name'].toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place_outlined, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    selected['address'].toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Tooltip(
                  message: 'Khoảng cách đường chim bay',
                  child: _chip(theme, Icons.near_me_outlined, _kmLabel(selected)),
                ),
                _chip(theme, Icons.star_rounded, '${selected['rating'] ?? '-'}', iconColor: Colors.amber.shade700),
                _chip(theme, Icons.payments_outlined,
                    'từ ${UiFmt.k(UiFmt.toNum(selected['basePricePerHour'], 0))}/giờ'),
              ],
            ),
            if (_showRoute) ...[
              const SizedBox(height: 10),
              _routePanel(theme, selected),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => showDirectionsSheet(context, selected, distanceKm: _kmOf(selected)),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    icon: const Icon(Icons.navigation_outlined, size: 18),
                    label: const Text('Dẫn đường', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: _showRoute ? 'Ẩn hướng đi' : 'Xem hướng đi trên bản đồ',
                  onPressed: () => _showRoute ? setState(() => _showRoute = false) : _focus(selected),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  isSelected: _showRoute,
                  icon: const Icon(Icons.alt_route_outlined),
                  selectedIcon: const Icon(Icons.route),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: openVenue,
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    icon: const Icon(Icons.event_available_outlined, size: 18),
                    label: const Text('Xem & đặt', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Chọn phương tiện + tóm tắt tuyến (quãng đường, thời gian, số chỗ rẽ).
  Widget _routePanel(ThemeData theme, Map<String, dynamic> selected) {
    final cs = theme.colorScheme;
    final plan = _plan != null && _planKey == _keyFor(selected) ? _plan : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<TravelMode>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            for (final m in TravelMode.values)
              ButtonSegment(value: m, icon: Icon(m.icon, size: 18), label: Text(m.label)),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => _setMode(s.first),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: _planLoading
              ? Row(
                  children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Text('Đang tìm đường...', style: theme.textTheme.bodyMedium),
                  ],
                )
              : plan != null
                  ? Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${plan.durationLabel} • ${plan.distanceLabel}',
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
                              Text('Theo đường phố • ${plan.turnCount} chỗ rẽ • ước tính',
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _showSteps(plan, selected),
                          icon: const Icon(Icons.format_list_numbered, size: 18),
                          label: const Text('Chỉ dẫn'),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _planError ?? 'Nét đứt là hướng đường chim bay.',
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                        if (_planError != null)
                          TextButton(onPressed: () => _loadRoute(selected), child: const Text('Thử lại')),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _chip(ThemeData theme, IconData icon, String label, {Color? iconColor}) {
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor ?? cs.primary),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  /// Dòng báo khi đang dùng vị trí mặc định (chưa cấp quyền / tắt GPS).
  Widget? _locationBanner(ThemeData theme) {
    final status = _app.locationStatus;
    if (_app.hasRealLocation || status == LocationStatus.unknown) return null;
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      color: WarningTone.container(cs),
      child: Row(
        children: [
          Icon(Icons.location_off_outlined, size: 18, color: WarningTone.onContainer(cs)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              LocationService.describe(status),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: WarningTone.onContainer(cs)),
            ),
          ),
          TextButton(
            onPressed: _locating ? null : () => _locate(force: true),
            child: Text(
              status == LocationStatus.serviceDisabled || status == LocationStatus.deniedForever
                  ? 'Mở cài đặt'
                  : 'Bật vị trí',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (_app.venues.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: EmptyState(icon: Icons.map_outlined, title: 'Chưa có cơ sở nào trên bản đồ'),
      );
    }
    final selected = _focusedVenue ?? _app.venues.first;
    final banner = _locationBanner(theme);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(bottom: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              Icon(Icons.touch_app_outlined, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${_visibleVenues().length}/${_app.venues.length} sân '
                  '(${_filtered ? "≤${_maxRadiusKm.toInt()}km" : "tất cả"}). Chạm ghim để chọn.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<double>(
                tooltip: 'Lọc theo bán kính',
                initialValue: _maxRadiusKm,
                onSelected: (r) => setState(() => _maxRadiusKm = r),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 2.0, child: Text('Bán kính ≤ 2 km')),
                  PopupMenuItem(value: 5.0, child: Text('Bán kính ≤ 5 km')),
                  PopupMenuItem(value: 10.0, child: Text('Bán kính ≤ 10 km')),
                  PopupMenuItem(value: 20.0, child: Text('Bán kính ≤ 20 km')),
                  PopupMenuItem(value: double.infinity, child: Text('Tất cả')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: _filtered ? cs.primaryContainer : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tune_outlined, size: 14, color: _filtered ? cs.onPrimaryContainer : cs.onSurface),
                      const SizedBox(width: 4),
                      Text(
                        _filtered ? '≤${_maxRadiusKm.toInt()}km' : 'Bán kính',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _filtered ? cs.onPrimaryContainer : cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (banner != null) banner,
        Expanded(
          child: OrientationBuilder(
            builder: (context, orientation) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final useSidePanel = constraints.maxWidth >= 600 &&
                      (orientation == Orientation.landscape || constraints.maxWidth >= 850);
                  if (useSidePanel) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: _buildMapWidget(selected)),
                        Expanded(flex: 2, child: _buildVenueInfoCard(selected, isSidePanel: true)),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Expanded(child: _buildMapWidget(selected)),
                      // Thẻ cao tối đa ~60% để bản đồ luôn còn chỗ; nội dung dài thì cuộn
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.6),
                        child: _buildVenueInfoCard(selected),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
