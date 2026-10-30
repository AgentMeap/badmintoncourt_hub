import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S07: OpenStreetMap Discovery Screen (Module 2)
// Giao diện theo design system: ghim sân và vị trí dùng màu Theme + icon (không emoji),
// khoảng cách tính THẬT từ vị trí người dùng tới tọa độ sân (latlong2),
// thẻ thông tin sân dạng bottom sheet / panel bên, có ghi công OpenStreetMap
// (bắt buộc theo chính sách sử dụng tile của OSM).
class S07MapDiscoveryScreen extends StatefulWidget {
  final AppState appState;
  const S07MapDiscoveryScreen({super.key, required this.appState});

  @override
  State<S07MapDiscoveryScreen> createState() => _S07MapDiscoveryScreenState();
}

class _S07MapDiscoveryScreenState extends State<S07MapDiscoveryScreen> {
  // Tọa độ GPS mặc định: Nhà Văn Hóa Sinh Viên ĐHQG TP.HCM (Làng Đại học)
  final LatLng _userGps = const LatLng(10.8753, 106.8000);
  static final _distance = Distance();
  Map<String, dynamic>? _focusedVenue;
  bool _showRoute = false;

  @override
  void initState() {
    super.initState();
    if (widget.appState.venues.isNotEmpty) {
      _focusedVenue = widget.appState.venues.first;
    }
  }

  LatLng _posOf(Map<String, dynamic> v) => LatLng(
        UiFmt.toNum(v['latitude'], 0).toDouble(),
        UiFmt.toNum(v['longitude'], 0).toDouble(),
      );

  /// Khoảng cách đường chim bay (km) từ vị trí người dùng.
  String _kmTo(Map<String, dynamic> v) {
    final km = _distance.as(LengthUnit.Meter, _userGps, _posOf(v)) / 1000;
    return '${km.toStringAsFixed(1)} km';
  }

  Widget _buildMapWidget(Map<String, dynamic> selected) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dest = _posOf(selected);

    return FlutterMap(
      options: MapOptions(initialCenter: _userGps, initialZoom: 13.8),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.badminton.badminton_v2_mobile',
        ),
        if (_showRoute)
          PolylineLayer(
            polylines: [
              Polyline(points: [_userGps, dest], strokeWidth: 4.5, color: cs.tertiary),
            ],
          ),
        MarkerLayer(
          markers: [
            // Vị trí người dùng
            Marker(
              point: _userGps,
              width: 36,
              height: 36,
              child: Semantics(
                label: 'Vị trí của bạn',
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.tertiary.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: cs.tertiary,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.surface, width: 3),
                    ),
                  ),
                ),
              ),
            ),
            // Ghim các sân
            ...widget.appState.venues.map((v) {
              final isFocused = '${selected['id']}' == '${v['id']}';
              return Marker(
                point: _posOf(v),
                width: 96,
                height: 64,
                alignment: Alignment.topCenter,
                child: Semantics(
                  button: true,
                  label: '${v['name']}, ${_kmTo(v)}',
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _focusedVenue = v;
                      _showRoute = true;
                    }),
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
        SimpleAttributionWidget(source: const Text('OpenStreetMap contributors')),
      ],
    );
  }

  Widget _buildVenueInfoCard(Map<String, dynamic> selected, {bool isSidePanel = false}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    void openVenue() {
      widget.appState.selectedVenue = selected;
      widget.appState.goTo('S08');
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
                _chip(theme, Icons.near_me_outlined, _kmTo(selected)),
                _chip(theme, Icons.star_rounded, '${selected['rating'] ?? '-'}', iconColor: Colors.amber.shade700),
                _chip(theme, Icons.payments_outlined,
                    'từ ${UiFmt.k(UiFmt.toNum(selected['basePricePerHour'], 0))}/giờ'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _showRoute = !_showRoute),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    icon: Icon(_showRoute ? Icons.route : Icons.directions_outlined, size: 18),
                    label: Text(_showRoute ? 'Ẩn đường đi' : 'Chỉ đường',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (widget.appState.venues.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: EmptyState(icon: Icons.map_outlined, title: 'Chưa có cơ sở nào trên bản đồ'),
      );
    }
    final selected = _focusedVenue ?? widget.appState.venues.first;

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
                  '${widget.appState.venues.length} cơ sở quanh bạn. Chạm vào ghim để xem chi tiết.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                avatar: const Icon(Icons.route, size: 16),
                label: const Text('Đường đi'),
                selected: _showRoute,
                showCheckmark: false,
                onSelected: (v) => setState(() => _showRoute = v),
              ),
            ],
          ),
        ),
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
                      _buildVenueInfoCard(selected),
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
