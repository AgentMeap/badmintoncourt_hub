# Badminton Court Hub V2 – Mobile (Flutter)

Ứng dụng đặt sân & quản lý cơ sở cầu lông cho 3 vai trò: **Người chơi**, **Chủ sân**, **Quản trị viên**.
Đồ án môn PRM393 – 26 màn hình (S01–S26), 5 luồng nghiệp vụ, 6 module.

## Chạy dự án

```bash
flutter pub get
flutter run            # chọn Chrome (web) hoặc máy ảo Android
flutter test           # kiểm tra tràn giao diện của 26 màn trên 4 kích thước màn hình
```

- Backend Spring Boot chạy tại `http://localhost:8080/api` (Android emulator: `10.0.2.2`).
  Khi không kết nối được backend, app tự dùng dữ liệu mẫu trong `AppState`.
- Đăng nhập demo: `customer@badminton.vn`, `owner@badminton.vn`, `admin@badminton.vn` (mật khẩu `123456`),
  hoặc bấm ô vai trò ở màn đăng nhập.
- Menu ☰ liệt kê đủ 26 màn (kèm mã S01–S26) để trình bày; đầu menu có nút chọn giao diện Sáng / Tối / Theo hệ thống.

## Cấu trúc thư mục

```
lib/
  main.dart                 Gốc ứng dụng: tạo AppState, gắn Theme và AppShell (~45 dòng)
  app/
    app_shell.dart          "Master page": Scaffold + AppBar + điều hướng + phím Back (PopScope)
    app_navigation.dart     Tab theo vai trò (NavSpec) + NavigationBar (điện thoại) / NavigationRail (tablet)
    app_drawer.dart         Menu demo 26 màn + chọn giao diện sáng/tối
    screen_registry.dart    BẢNG DUY NHẤT: mã màn → tiêu đề + widget
    app_theme.dart          Theme sáng/tối, font Barlow
    scroll_to_top.dart      Nút "Lên đầu trang" dùng chung cho mọi màn hình
  core/
    app_state.dart          Trạng thái & dữ liệu mẫu; điều hướng: goTo, goBack, goToTab, resetTo, completeFlow
    api_service.dart        Gọi REST API
    booking_rules.dart      QUY TẮC NGHIỆP VỤ dùng chung (giá, lịch trống, hủy/đổi lịch, tài chính chủ sân)
    ui_kit.dart             Thành phần giao diện dùng chung (định dạng tiền/ngày, thẻ, badge, nút, hộp xác nhận…)
    responsive.dart         Breakpoint & khung nội dung responsive
  screens/
    screens.dart            Export toàn bộ màn hình
    auth/                   S01 Đăng nhập · S02 Đăng ký · S03 OTP · S04 Quên mật khẩu
    shared/                 S05 Thông báo
    customer/               S06 Trang chủ … S18 Ví & hồ sơ
    owner/                  S19 Tổng quan … S23 Giải ngân
    admin/                  S24 Tổng quan … S26 Duyệt giải ngân
assets/fonts/               Barlow, Barlow Condensed (giấy phép OFL – xem OFL.txt)
```

Quy ước: mỗi màn hình một file, tên file `sXX_ten_man_hinh_screen.dart` trùng tên class `SXXTenManHinhScreen`.

**Thêm một màn hình mới:** tạo file trong `screens/<nhóm>/`, export trong `screens/screens.dart`,
rồi thêm **một dòng** `ScreenEntry(...)` vào `app/screen_registry.dart`. Nếu là tab, khai báo thêm trong `app/app_navigation.dart`.

## Design system

Xây dựng theo skill **ui-ux-pro-max** (nextlevelbuilder/ui-ux-pro-max-skill):

- **Màu:** sinh từ seed `#059669` (Material 3 `ColorScheme`), có cả giao diện tối. Màn hình **không hardcode màu**,
  luôn lấy từ `Theme.of(context).colorScheme`; tông cảnh báo dùng `WarningTone` để tự đổi theo sáng/tối.
- **Chữ:** Barlow cho nội dung và tiêu đề màn hình (đậm 700, cao dòng 1.3 cho dấu tiếng Việt);
  Barlow Condensed (≤ 700) chỉ cho số lớn như số dư ví, tiền giải ngân. Font nhúng sẵn, chạy offline.
- **Icon:** chỉ dùng icon vector Material, không dùng emoji làm icon.
- **Trạng thái:** luôn có màu + icon + chữ (không truyền thông tin chỉ bằng màu), ví dụ `StatusBadge`.
- **Vùng chạm** tối thiểu 48dp; nút chỉ có icon luôn có `tooltip`.
- Hành động không hoàn tác (hủy vé, từ chối, giải ngân…) luôn có hộp thoại xác nhận (`confirmAction`).
- Tôn trọng cài đặt "giảm chuyển động" của hệ thống.

## Quy tắc nghiệp vụ (`lib/core/booking_rules.dart`)

| Quy tắc | Giá trị |
|---|---|
| Giữ chỗ chờ thanh toán | 5 phút (`holdMinutes`) |
| Giờ vàng | từ 17:00 thứ 2–6, cả ngày thứ 7 & CN (`peakStartHour`) |
| Hủy vé | ≥ 24h hoàn 100% · 6–24h hoàn 50% · < 6h không hoàn; vé chưa thanh toán không hoàn |
| Đổi lịch | tối đa 1 lần, trước giờ chơi ≥ 6h, giữ nguyên sân & số giờ, chênh lệch giá bù/hoàn qua Ví |
| Hoa hồng nền tảng | 5% doanh thu online (`OwnerFinance.commissionRate`) |

- Lưới chọn giờ (S09) lấy số sân, giờ mở cửa, bảng giá từ cơ sở; ô đã đặt/bảo trì suy ra từ danh sách đặt sân → **không đặt trùng**.
- Khách vãng lai / bảo trì (S21) cũng kiểm tra trùng lịch qua cùng quy tắc.
- Doanh thu, tiền giải ngân, GMV (S19, S23, S24) được **tính từ dữ liệu**, vé đã đưa vào yêu cầu giải ngân được đánh dấu để không giải ngân 2 lần.

> Backend cũng cần áp đúng các quy tắc trên; app hiện gửi kèm `refundPercent` khi hủy vé.

## Điều hướng

- Màn gốc (các tab, màn đăng nhập) hiện nút menu; màn con hiện nút Back bên trái.
- Phím Back Android đi lùi theo lịch sử trong app, chỉ thoát khi ở màn đầu tiên.
- Chuyển tab không làm dài lịch sử; đăng nhập/đăng xuất/đổi vai trò bắt đầu lịch sử mới.
- Thanh toán xong, Back từ vé không quay lại màn thanh toán / QR (`completeFlow`).
- Cuộn sâu hơn ~1 màn hình sẽ hiện nút **"Lên đầu trang"** ở giữa phía trên (ẩn khi đang vuốt xuống);
  chạm lại tab đang mở cũng cuộn về đầu (`app/scroll_to_top.dart`). Không áp dụng cho Trợ lý AI.
