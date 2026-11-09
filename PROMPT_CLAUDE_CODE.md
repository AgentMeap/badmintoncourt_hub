# NHIỆM VỤ PHÁT TRIỂN: CHẾ ĐỘ SÁNG / TỐI (DARK / LIGHT / SYSTEM THEME) CHO BADMINTON HUB MOBILE

> **Dành cho**: Claude Code (hoặc AI Coding Assistant)  
> **Dự án**: Badminton Hub v2 - Flutter Mobile (PRM393)  
> **Thư mục làm việc**: `mobile/` (tại `d:\badminton_v2\mobile`)  
> **Mục tiêu**: Tích hợp bộ chọn giao diện Sáng / Tối / Hệ thống vào màn hình Hồ sơ & Cài đặt (`S18`), tự động lưu và khôi phục trạng thái bằng `SharedPreferences`. Đảm bảo 0 lỗi `flutter analyze` và 100% pass kiểm thử responsive trên 30 màn hình.

---

## 1. BỐI CẢNH & HIỆN TRẠNG KIẾN TRÚC

1. **State Management**: Dự án sử dụng `AppState` kế thừa `ChangeNotifier` (`mobile/lib/core/app_state.dart`). Toàn bộ app lắng nghe qua `ListenableBuilder(listenable: appState)`.
2. **Theme Configuration**: `mobile/lib/main.dart` đã cấu hình `theme: AppTheme.light`, `darkTheme: AppTheme.dark`, và `themeMode: _appState.themeMode`.
3. **Biến State hiện tại**: Trong `AppState` đã có sẵn:
   ```dart
   ThemeMode themeMode = ThemeMode.system;
   void setThemeMode(ThemeMode mode) {
     if (themeMode == mode) return;
     themeMode = mode;
     notifyListeners();
   }
   ```
4. **Vấn đề cần giải quyết**:
   - `themeMode` chưa được lưu xuống `SharedPreferences`, khi tắt app mở lại sẽ bị reset về `ThemeMode.system`.
   - Màn hình Hồ sơ `S18` (`mobile/lib/screens/customer/s18_profile_wallet_screen.dart`) chưa có UI cho người dùng chọn chế độ giao diện.

---

## 2. YÊU CẦU CHI TIẾT CẦN THỰC HIỆN

### Bước 1: Lưu & Khôi phục ThemeMode trong `mobile/lib/core/app_state.dart`
- **Khi đổi theme (`setThemeMode`)**: Lưu key `'theme_mode'` dạng `String` (`'system'`, `'light'`, `'dark'`) vào `SharedPreferences`.
  ```dart
  void setThemeMode(ThemeMode mode) {
    if (themeMode == mode) return;
    themeMode = mode;
    notifyListeners();
    SharedPreferences.getInstance().then((sp) {
      sp.setString('theme_mode', mode.name);
    }).catchError((_) {});
  }
  ```
- **Khi khởi động app (`loadSavedSession`)**:
  Đọc `'theme_mode'` từ `SharedPreferences`:
  ```dart
  final savedTheme = sp.getString('theme_mode');
  if (savedTheme != null) {
    if (savedTheme == 'light') {
      themeMode = ThemeMode.light;
    } else if (savedTheme == 'dark') {
      themeMode = ThemeMode.dark;
    } else {
      themeMode = ThemeMode.system;
    }
  }
  ```

---

### Bước 2: Thêm UI chọn Theme vào `mobile/lib/screens/customer/s18_profile_wallet_screen.dart`
- Đặt một section mới **"Giao diện & Ứng dụng"** trong `ListView` của `S18` (vị trí gợi ý: ngay trước nút "Đăng xuất / đổi vai trò" hoặc sau phần "Lịch sử giao dịch").
- Sử dụng `SectionHeader` và `SurfaceCard` tuân thủ đúng Design System của dự án (`ui_kit.dart`).
- **Lưu ý Responsive**: Thiết bị nhỏ nhất có chiều rộng 360px (padding hai bên 14px -> khả dụng ~332px). Để tránh lỗi RenderFlex overflow:
  - Hiển thị tiêu đề & mô tả ở hàng trên.
  - Đặt `SegmentedButton<ThemeMode>` ở hàng dưới (chiếm toàn bộ chiều rộng `double.infinity`) với 3 lựa chọn:
    1. **Hệ thống** (Icon `Icons.brightness_auto_outlined`, Label: `'Tự động'`)
    2. **Sáng** (Icon `Icons.light_mode_outlined`, Label: `'Sáng'`)
    3. **Tối** (Icon `Icons.dark_mode_outlined`, Label: `'Tối'`)

#### Mẫu Code gợi ý cho S18:
```dart
          const SizedBox(height: 24),
          const SectionHeader('Cài đặt giao diện'),
          SurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette_outlined, size: 20, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Chế độ hiển thị',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      appState.themeMode == ThemeMode.system
                          ? 'Theo máy'
                          : (appState.themeMode == ThemeMode.dark ? 'Nền tối' : 'Nền sáng'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Chọn giao diện sáng, tối hoặc tự động đồng bộ theo cài đặt thiết bị.',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_outlined, size: 16),
                        label: Text('Tự động', maxLines: 1),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined, size: 16),
                        label: Text('Sáng', maxLines: 1),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined, size: 16),
                        label: Text('Tối', maxLines: 1),
                      ),
                    ],
                    selected: {appState.themeMode},
                    onSelectionChanged: (newSelection) {
                      appState.setThemeMode(newSelection.first);
                    },
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
          ),
```

---

## 3. TIÊU CHÍ NGHIỆM THU & LỆNH KIỂM THỬ (BẮT BUỘC)

Sau khi hoàn tất chỉnh sửa, **bắt buộc chạy 2 lệnh sau từ thư mục `mobile`**:

1. **Kiểm tra phân tích tĩnh Dart (0 cảnh báo, 0 lỗi)**:
   ```powershell
   cd mobile
   flutter analyze
   ```
   *Yêu cầu*: Đầu ra phải là `No issues found!`.

2. **Kiểm tra Responsive trên 30 màn hình x 4 breakpoints**:
   ```powershell
   cd mobile
   flutter test
   ```
   *Yêu cầu*: Toàn bộ 4 test suites pass 100%:
   - 360x640 (Small Phone Portrait)
   - 640x360 (Small Phone Landscape)
   - 800x1280 (Tablet Portrait)
   - 1280x800 (Desktop / Tablet Landscape)

---

## 4. QUY CÁCH COMMIT MESSAGE (NẾU COMMIT)

```powershell
git commit -m "feat(mobile): add persistent theme mode selector in profile settings" -m "- Save and restore themeMode (system/light/dark) using SharedPreferences in AppState" -m "- Add responsive SegmentedButton theme selector card in S18 Profile Screen" -m "- Ensure 0 flutter analyze warnings and 100% responsive test pass across all 30 screens"
```
