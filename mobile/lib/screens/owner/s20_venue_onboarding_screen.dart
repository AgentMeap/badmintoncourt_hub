import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:badminton_v2_mobile/core/api_service.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';

// S20: Venue Onboarding, Map Picker & Pricing Setup (Luồng 3 + Module 2)
// Giao diện theo design system + sửa logic: số sân và giờ mở/đóng cửa nhập được
// (trước đây gán cứng 4 sân, không có giờ mở cửa nên lưới S09 không đúng),
// kiểm tra giá giờ vàng >= giá thường, ghi công OpenStreetMap trên bản đồ.
class S20VenueOnboardingScreen extends StatefulWidget {
  final AppState appState;
  const S20VenueOnboardingScreen({super.key, required this.appState});

  @override
  State<S20VenueOnboardingScreen> createState() => _S20VenueOnboardingScreenState();
}

class _S20VenueOnboardingScreenState extends State<S20VenueOnboardingScreen> {
  final _nameCtrl = TextEditingController(text: 'Sân Cầu Lông TH Badminton Cơ sở 3 (Thủ Đức)');
  final _addrCtrl = TextEditingController(text: 'Đường Võ Văn Ngân, P. Linh Chiểu, TP. Thủ Đức');
  final _basePriceCtrl = TextEditingController(text: '60000');
  final _peakPriceCtrl = TextEditingController(text: '100000');
  LatLng _pickedLocation = const LatLng(10.8505, 106.7720);
  int _courts = 4;
  int _openHour = 5;
  int _closeHour = 23;
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    _basePriceCtrl.dispose();
    _peakPriceCtrl.dispose();
    super.dispose();
  }

  String _hh(int h) => '${h.toString().padLeft(2, '0')}:00';

  Future<void> _submitVenue() async {
    if (_loading) return;
    final base = double.tryParse(_basePriceCtrl.text);
    final peak = double.tryParse(_peakPriceCtrl.text);
    String? error;
    if (_nameCtrl.text.trim().length < 5) {
      error = 'Tên cơ sở cần ít nhất 5 ký tự.';
    } else if (_addrCtrl.text.trim().isEmpty) {
      error = 'Vui lòng nhập địa chỉ.';
    } else if (base == null || base <= 0 || peak == null || peak <= 0) {
      error = 'Giá thuê chưa hợp lệ.';
    } else if (peak < base) {
      error = 'Giá giờ vàng phải lớn hơn hoặc bằng giá thường.';
    } else if (_closeHour <= _openHour) {
      error = 'Giờ đóng cửa phải sau giờ mở cửa.';
    }
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _loading = true);

    final newVenue = {
      'id': DateTime.now().millisecondsSinceEpoch % 10000,
      'ownerId': widget.appState.userId,
      'ownerName': widget.appState.fullName.split('(').first.trim(),
      'name': _nameCtrl.text.trim(),
      'address': _addrCtrl.text.trim(),
      'latitude': _pickedLocation.latitude,
      'longitude': _pickedLocation.longitude,
      'totalCourts': _courts,
      'openTime': _hh(_openHour),
      'closeTime': _hh(_closeHour),
      'basePricePerHour': base,
      'peakPricePerHour': peak,
      'status': 'PENDING',
    };

    try {
      await ApiService.post('/venues/owner', newVenue);
    } catch (_) {}

    widget.appState.adminPendingVenues.insert(0, newVenue);
    if (!mounted) return;
    setState(() => _loading = false);
    widget.appState.pushNotification(
      title: 'Đã gửi hồ sơ đăng ký cơ sở mới',
      body: 'Cơ sở "${newVenue['name']}" đang chờ Admin kiểm duyệt.',
      type: 'SYSTEM',
      targetScreen: 'S19',
      context: context,
    );
    widget.appState.goToTab('S19', 'S19');
  }

  Widget _hourDropdown(String label, int value, ValueChanged<int> onChanged) {
    return DropdownButtonFormField<int>(
      isExpanded: true,
      initialValue: value,
      items: [for (var h = 0; h <= 24; h++) DropdownMenuItem(value: h, child: Text(_hh(h)))],
      onChanged: (v) => onChanged(v ?? value),
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mapHeight = Responsive.isMobile(context) ? 200.0 : 260.0;

    return ResponsiveCenter(
      maxWidth: Responsive.defaultFormMaxWidth,
      child: ListView(
        padding: Responsive.screenPadding(context),
        children: [
          Text('Đăng ký cơ sở mới',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Hồ sơ sẽ được Admin kiểm duyệt trước khi hiển thị cho người chơi.',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 20),

          const SectionHeader('Thông tin cơ sở'),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Tên cơ sở',
              prefixIcon: Icon(Icons.storefront_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addrCtrl,
            decoration: const InputDecoration(
              labelText: 'Địa chỉ',
              prefixIcon: Icon(Icons.place_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text('Số sân', style: theme.textTheme.bodyMedium)),
              IconButton.outlined(
                tooltip: 'Bớt 1 sân',
                onPressed: _courts > 1 ? () => setState(() => _courts--) : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 44,
                child: Text('$_courts',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
              ),
              IconButton.outlined(
                tooltip: 'Thêm 1 sân',
                onPressed: _courts < 30 ? () => setState(() => _courts++) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _hourDropdown('Mở cửa', _openHour, (v) => setState(() => _openHour = v))),
              const SizedBox(width: 10),
              Expanded(child: _hourDropdown('Đóng cửa', _closeHour, (v) => setState(() => _closeHour = v))),
            ],
          ),
          const SizedBox(height: 24),

          const SectionHeader('Vị trí trên bản đồ'),
          Text('Chạm vào bản đồ để ghim đúng vị trí cơ sở.',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          SizedBox(
            height: mapHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: _pickedLocation,
                  initialZoom: 13.5,
                  onTap: (_, latlng) => setState(() => _pickedLocation = latlng),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.badminton.badminton_v2_mobile',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _pickedLocation,
                        width: 48,
                        height: 48,
                        alignment: Alignment.topCenter,
                        child: Icon(Icons.location_on, color: cs.primary, size: 40),
                      ),
                    ],
                  ),
                  SimpleAttributionWidget(source: const Text('OpenStreetMap contributors')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.my_location, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                '${_pickedLocation.latitude.toStringAsFixed(4)}, ${_pickedLocation.longitude.toStringAsFixed(4)}',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 24),

          const SectionHeader('Bảng giá'),
          LayoutBuilder(
            builder: (context, c) {
              final base = TextField(
                controller: _basePriceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Giờ thường',
                  helperText: 'Trước 17:00, thứ 2 - 6',
                  suffixText: 'đ/giờ',
                  border: OutlineInputBorder(),
                ),
              );
              final peak = TextField(
                controller: _peakPriceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Giờ vàng',
                  helperText: 'Từ 17:00 & cuối tuần',
                  suffixText: 'đ/giờ',
                  border: OutlineInputBorder(),
                ),
              );
              if (c.maxWidth < 380) {
                return Column(children: [base, const SizedBox(height: 12), peak]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: base), const SizedBox(width: 10), Expanded(child: peak)],
              );
            },
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Gửi hồ sơ kiểm duyệt',
            icon: Icons.send_outlined,
            loading: _loading,
            onPressed: _submitVenue,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
