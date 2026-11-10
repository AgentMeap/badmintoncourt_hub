import 'package:flutter/material.dart';
import 'package:badminton_v2_mobile/core/repositories/repositories.dart';
import 'package:badminton_v2_mobile/core/app_state.dart';
import 'package:badminton_v2_mobile/core/responsive.dart';
import 'package:badminton_v2_mobile/core/ui_kit.dart';
import 'package:badminton_v2_mobile/screens/owner/s19_owner_dashboard_screen.dart' show venueStatusChip;

// S25: Admin Venue & User Moderation Screen (Luồng 3)
// - Tab "Cơ sở": duyệt / từ chối hồ sơ cơ sở mới. Từ chối bắt buộc nhập lý do (máy chủ gửi
//   cho chủ sân trong thông báo).
// - Tab "Tài khoản": tìm theo tên / email / SĐT, lọc theo vai trò, khóa / mở khóa tài khoản
//   (PATCH /admin/users/{id}/toggle-active). Không khóa được tài khoản Admin.
class S25AdminModerationScreen extends StatefulWidget {
  final AppState appState;
  const S25AdminModerationScreen({super.key, required this.appState});

  @override
  State<S25AdminModerationScreen> createState() => _S25AdminModerationScreenState();
}

class _S25AdminModerationScreenState extends State<S25AdminModerationScreen> {
  final Set<String> _busy = {};
  final _searchCtrl = TextEditingController();
  late int _tab;
  String _roleFilter = 'ALL';

  AppState get _app => widget.appState;

  @override
  void initState() {
    super.initState();
    _tab = _app.adminModerationTab;
    _app.adminModerationTab = 0;
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await _app.refreshAdminDashboard();
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  /// Hộp thoại nhập lý do (bắt buộc). Trả về null nếu hủy.
  Future<String?> _askReason({required String title, required String hint, required String confirmLabel}) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 300,
            minLines: 2,
            maxLines: 4,
            onChanged: (_) => setLocal(() {}),
            decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: ctrl.text.trim().isEmpty ? null : () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return result;
  }

  // ------------------------------------------------------------------ Cơ sở

  Future<void> _moderateVenue(Json v, String decision) async {
    final key = 'v${v['id']}';
    if (_busy.contains(key)) return;
    final approve = decision == 'APPROVED';
    String? reason;
    if (approve) {
      final ok = await confirmAction(
        context,
        title: 'Phê duyệt cơ sở?',
        message: '"${v['name']}" sẽ hiển thị trên Trang chủ và Bản đồ cho người chơi.',
        confirmLabel: 'Phê duyệt',
      );
      if (!ok) return;
    } else {
      reason = await _askReason(
        title: 'Từ chối "${v['name']}"?',
        hint: 'Lý do (VD: địa chỉ chưa chính xác, thiếu bảng giá...)',
        confirmLabel: 'Từ chối',
      );
      if (reason == null) return;
    }
    if (!mounted) return;

    setState(() => _busy.add(key));
    final Json saved;
    try {
      saved = await Repos.admin.moderateVenue(v['id'], decision, reason: reason);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(key));
      showApiError(context, e);
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy.remove(key);
      v.addAll(saved);
      v['status'] = decision;
      if (approve) _app.venues.insert(0, v);
      _app.adminPendingVenues.remove(v);
    });
    _app.pushNotification(
      title: approve ? 'Đã duyệt cơ sở "${v['name']}"' : 'Đã từ chối cơ sở "${v['name']}"',
      body: approve ? 'Cơ sở đã hiển thị trên Bản đồ và Trang chủ.' : 'Đã gửi lý do từ chối cho chủ sân.',
      type: 'SYSTEM',
      targetScreen: approve ? 'S06' : 'S25',
      context: context,
    );
    _app.refreshAdminDashboard().catchError((Object e) => debugPrint('[S25] $e'));
  }

  Widget _line(ThemeData theme, IconData icon, String text) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
        ],
      ),
    );
  }

  List<Widget> _venueTab(ThemeData theme) {
    final cs = theme.colorScheme;
    final pending = _app.adminPendingVenues.where((v) => v['status'] == 'PENDING').toList();
    if (pending.isEmpty) {
      return const [
        EmptyState(
          icon: Icons.task_alt,
          title: 'Đã xử lý hết hồ sơ',
          message: 'Hồ sơ cơ sở mới từ chủ sân sẽ hiện ở đây.',
        ),
      ];
    }
    return [
      for (final v in pending)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: venueCoverColors(cs, v)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.sports_tennis, color: cs.onPrimary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${v['name']}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          Text('Chủ sân: ${v['ownerName'] ?? '-'}',
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    venueStatusChip(theme, v['status']?.toString()),
                  ],
                ),
                const SizedBox(height: 4),
                _line(theme, Icons.place_outlined, '${v['address']}'),
                _line(theme, Icons.my_location,
                    '${UiFmt.toNum(v['latitude'], 0).toStringAsFixed(4)}, ${UiFmt.toNum(v['longitude'], 0).toStringAsFixed(4)}'),
                _line(theme, Icons.grid_view_rounded,
                    '${v['totalCourts'] ?? '-'} sân • ${v['openTime'] ?? '05:00'} - ${v['closeTime'] ?? '23:00'}'),
                _line(theme, Icons.payments_outlined,
                    '${UiFmt.vnd(UiFmt.toNum(v['basePricePerHour'], 0))} - ${UiFmt.vnd(UiFmt.toNum(v['peakPricePerHour'], 0))}/giờ'),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy.contains('v${v['id']}') ? null : () => _moderateVenue(v, 'REJECTED'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          foregroundColor: cs.error,
                          side: BorderSide(color: cs.error.withValues(alpha: 0.6)),
                        ),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Từ chối'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy.contains('v${v['id']}') ? null : () => _moderateVenue(v, 'APPROVED'),
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Phê duyệt'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ];
  }

  // --------------------------------------------------------------- Tài khoản

  static bool _isActive(Json u) => u['active'] != false && u['isActive'] != false;

  static String _roleLabel(String? role) => switch (role) {
        'COURT_OWNER' => 'Chủ sân',
        'ADMIN' => 'Quản trị viên',
        _ => 'Người chơi',
      };

  Future<void> _toggleUser(Json u) async {
    final key = 'u${u['id']}';
    if (_busy.contains(key)) return;
    final active = _isActive(u);
    final ok = await confirmAction(
      context,
      title: active ? 'Khóa tài khoản?' : 'Mở khóa tài khoản?',
      message: active
          ? '${u['fullName']} (${u['email']}) sẽ bị đăng xuất và không thể đăng nhập cho tới khi được mở khóa.'
          : '${u['fullName']} (${u['email']}) có thể đăng nhập và sử dụng ứng dụng trở lại.',
      confirmLabel: active ? 'Khóa' : 'Mở khóa',
      destructive: active,
    );
    if (!ok || !mounted) return;
    setState(() => _busy.add(key));
    final Json saved;
    try {
      saved = await Repos.admin.toggleUserActive(u['id']);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(key));
      showApiError(context, e);
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy.remove(key);
      u.addAll(saved);
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(_isActive(u) ? 'Đã mở khóa ${u['fullName']}' : 'Đã khóa ${u['fullName']}'),
      ));
    _app.refreshAdminDashboard().catchError((Object e) => debugPrint('[S25] $e'));
  }

  List<Widget> _userTab(ThemeData theme) {
    final cs = theme.colorScheme;
    final q = _searchCtrl.text.trim().toLowerCase();
    final users = _app.adminUsers.where((u) {
      if (_roleFilter == 'LOCKED' && _isActive(u)) return false;
      if (_roleFilter != 'ALL' && _roleFilter != 'LOCKED' && u['role'] != _roleFilter) return false;
      if (q.isEmpty) return true;
      return '${u['fullName']} ${u['email']} ${u['phone']}'.toLowerCase().contains(q);
    }).toList();

    return [
      TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Tìm theo tên, email, số điện thoại',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: q.isEmpty
              ? null
              : IconButton(tooltip: 'Xóa', onPressed: _searchCtrl.clear, icon: const Icon(Icons.close)),
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (value, label) in const [
              ('ALL', 'Tất cả'),
              ('CUSTOMER', 'Người chơi'),
              ('COURT_OWNER', 'Chủ sân'),
              ('ADMIN', 'Quản trị'),
              ('LOCKED', 'Đang khóa'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: _roleFilter == value,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _roleFilter = value),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (users.isEmpty)
        const EmptyState(icon: Icons.person_search_outlined, title: 'Không có tài khoản phù hợp')
      else
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < users.length; i++) ...[
                if (i > 0) Divider(height: 1, color: cs.outlineVariant),
                Builder(builder: (_) {
                  final u = users[i];
                  final active = _isActive(u);
                  final isAdmin = u['role'] == 'ADMIN' || '${u['id']}' == '${_app.userId}';
                  final busy = _busy.contains('u${u['id']}');
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: active ? cs.secondaryContainer : cs.errorContainer,
                      child: Icon(
                        active ? Icons.person_outline : Icons.lock_outline,
                        color: active ? cs.onSecondaryContainer : cs.onErrorContainer,
                      ),
                    ),
                    title: Text('${u['fullName'] ?? '-'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${_roleLabel(u['role']?.toString())} • ${u['email'] ?? ''}${active ? '' : ' • Đang khóa'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isAdmin
                        ? null
                        : busy
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : active
                                ? OutlinedButton(
                                    onPressed: () => _toggleUser(u),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 40),
                                      foregroundColor: cs.error,
                                    ),
                                    child: const Text('Khóa'),
                                  )
                                : FilledButton.tonal(
                                    onPressed: () => _toggleUser(u),
                                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                                    child: const Text('Mở khóa'),
                                  ),
                  );
                }),
              ],
            ],
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pendingCount = _app.adminPendingVenues.where((v) => v['status'] == 'PENDING').length;

    return ResponsiveCenter(
      maxWidth: Responsive.defaultContentMaxWidth,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: Responsive.screenPadding(context),
          children: [
            Text('Kiểm duyệt', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: [
                  ButtonSegment(
                      value: 0, icon: const Icon(Icons.storefront_outlined), label: Text('Cơ sở ($pendingCount)')),
                  ButtonSegment(
                      value: 1,
                      icon: const Icon(Icons.people_outline),
                      label: Text('Tài khoản (${_app.adminUsers.length})')),
                ],
                selected: {_tab},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
            ),
            const SizedBox(height: 16),
            ...(_tab == 0 ? _venueTab(theme) : _userTab(theme)),
          ],
        ),
      ),
    );
  }
}
