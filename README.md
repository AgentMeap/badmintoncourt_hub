# 🏸 Badminton Court Hub V2 — Nền Tảng Quản Lý, Đặt Sân & Tìm Kèo Cầu Lông

Dự án hoàn chỉnh môn **PRM393** sử dụng **Flutter Mobile Frontend** + **Java Spring Boot 3 Backend** + **SQLite (WAL Mode)**, tích hợp đầy đủ **3 Roles**, **5 Luồng nghiệp vụ chính**, **26 Màn hình (`S01` -> `S26`)** và **6 Module kỹ thuật bắt buộc**.

---

## 1. Cấu Trúc Thư Mục Dự Án (`d:\badminton_v2`)

```text
d:\badminton_v2\
├── backend\                        # Java Spring Boot 3.4 + SQLite (WAL Mode)
│   ├── pom.xml
│   ├── badminton_v2.db             # File CSDL SQLite tự động tạo & seed dữ liệu mẫu
│   ├── src\main\resources\application.yml
│   └── src\main\java\com\badminton\v2\
│       ├── config\                 # AppConfig, DataSeeder (Seed sẵn 3 Roles, 4 Sân, Kèo, Vé, Payout)
│       ├── entity\                 # 13 Entities (User, OtpToken, Venue, Court, PricingRule, Booking, Payment, Refund, WalletTransaction, PayoutRequest, MatchPost, MatchParticipant, NotificationItem)
│       ├── repository\             # 13 Spring Data JPA Repositories
│       ├── service\                # EmailOtpService (Module 4), NotificationService (Module 5), BookingHoldScheduler
│       └── controller\             # AuthController, VenueController, BookingPaymentController, MatchmakingController, AdminOwnerFinanceController, AiAssistantController, NotificationController
│
└── mobile\                         # Ứng dụng Flutter đa nền tảng (26 Screens)
    ├── pubspec.yaml                # http, flutter_map (OpenStreetMap), latlong2, qr_flutter, intl
    └── lib\
        ├── main.dart               # App Shell + Drawer chọn nhanh 26 Screens + Role-based BottomNav
        ├── core\
        │   ├── api_service.dart    # Kết nối REST API Spring Boot (tự động nhận diện Android Emulator / Desktop / Web)
        │   └── app_state.dart      # Quản lý phiên đăng nhập, trạng thái 26 màn hình & thông báo thời gian thực
        └── screens\
            ├── auth_and_shared_screens.dart        # S01 -> S05 (Auth, OTP 6 số qua Email, Notifications)
            ├── customer_booking_screens.dart       # S06 -> S14 (Trang chủ, OpenStreetMap, Lưới đặt sân, PayOS VietQR, Vé QR Check-in, Đổi/Hủy hoàn tiền Ví)
            ├── customer_social_ai_wallet_screens.dart # S15 -> S18 (Tìm kèo giao lưu, Đăng kèo, Chat AI Gemini, Ví Cầu Lông)
            └── owner_and_admin_screens.dart        # S19 -> S26 (Owner Dashboard, Ghim Map cơ sở, Lịch biểu Walk-in/Bảo trì, Quét QR Check-in, Payout OTP, Admin Duyệt sân & Giải ngân)
```

---

## 2. Hướng Dẫn Chạy Dự Án

### Bước 1: Khởi chạy Backend (Spring Boot + SQLite)
Mở Terminal tại `d:\badminton_v2\backend`:
```powershell
cd d:\badminton_v2\backend
mvn spring-boot:run
```
- Server sẽ chạy tại `http://localhost:8080`.
- File cơ sở dữ liệu SQLite `badminton_v2.db` được tự động khởi tạo ở chế độ **WAL Mode (`journal_mode=WAL`)** cùng dữ liệu mẫu từ `DataSeeder`.

### Bước 2: Khởi chạy Ứng dụng Mobile (Flutter)
Mở Terminal thứ hai tại `d:\badminton_v2\mobile`:
```powershell
cd d:\badminton_v2\mobile
flutter pub get
flutter run -d chrome   # Hoặc chạy trên máy ảo Android / Windows
```

---

## 3. Tài Khoản Demo Sẵn Có (Mật khẩu chung: `123456` | Mã OTP Demo: `123456`)

| Vai trò (Role) | Email đăng nhập | Mật khẩu | Màn hình chính sau khi vào |
| :--- | :--- | :--- | :--- |
| **👤 Customer (Người chơi)** | `customer@badminton.vn` | `123456` | `S06` (Trang chủ & Tìm sân) |
| **🏟️ Court Owner (Chủ sân)** | `owner@badminton.vn` | `123456` | `S19` (Owner Dashboard) |
| **🛡️ Admin (Quản trị viên)** | `admin@badminton.vn` | `123456` | `S24` (Admin Platform Dashboard) |

> 💡 **Mẹo khi thuyết trình:** Ngay tại màn hình `S01 (Login)` có sẵn 3 nút **Chuyển nhanh Role Demo (`Customer` / `Owner` / `Admin`)**, và trên thanh `AppBar` bên trái có **Menu Drawer liệt kê toàn bộ 26 Màn hình (`S01` -> `S26`)** để bạn nhảy tới bất kỳ màn hình nào trong 1 giây khi giảng viên hỏi!

---

## 4. Kịch Bản Demo 6 Module Kỹ Thuật Theo Checklist `TT PRM393`

1. **Module 1: Database & REST API (`Module 8, 9`)**
   - Trình bày file `badminton_v2.db` (SQLite WAL mode) kết nối qua Spring Data JPA (`13 bảng`) và các REST API trong `com.badminton.v2.controller`.
2. **Module 2: Map (`Module 6, 8`)**
   - Mở màn hình **`S07` (OpenStreetMap Discovery)**: Hiển thị vị trí GPS người dùng, ghim các sân cầu lông kèm giá/khoảng cách tính bằng công thức Haversine và vẽ tuyến đường đi trực tiếp.
   - Mở màn hình **`S20` (Owner Venue Setup)**: Bấm trực tiếp lên bản đồ OpenStreetMap để ghim tọa độ cơ sở mới.
3. **Module 3: Payment (`Module 7, 8, 10`)**
   - Mở **`S09` -> `S10` -> `S11` (PayOS VietQR)**: Chọn khung giờ trên lưới -> Khóa tạm `HELD` 5 phút -> Sinh mã VietQR động của PayOS -> Bấm nút **Giả lập Webhook PayOS** (hoặc quét thật khi cấu hình key) -> Tự động chuyển trạng thái vé sang `CONFIRMED` và sinh mã QR Check-in tại **`S13`**.
   - Mở **`S14` (Luồng 4 - Hủy & Hoàn tiền)**: Hủy vé trước giờ chơi -> Tự động tính % hoàn tiền cộng thẳng vào **Ví Cầu Lông nội bộ (`S18`)**.
4. **Module 4: Bảo mật tài khoản (`Module 10`)**
   - Mở **`S02` (Đăng ký)**, **`S04` (Quên mật khẩu)** hoặc **`S23` (Chủ sân rút tiền Payout)** -> Hệ thống sinh mã **OTP 6 chữ số** gửi qua Email (`EmailOtpService`) và chuyển tới màn hình **`S03` (Xác thực OTP 6 ô số)**.
5. **Module 5: Notifications Screen (`Module 10`)**
   - Mỗi khi thanh toán PayOS xong, hủy sân hoàn tiền, có người xin vào kèo giao lưu hoặc Admin duyệt sân, hệ thống tự động hiện **Push Banner** và lưu vào **`S05` (Trung tâm Thông báo)** kèm badge đếm số thông báo chưa đọc trên thanh AppBar.
6. **Module 6: Chat AI (`Module 8, 10`)**
   - Mở **`S17` (Trợ lý Chat AI Gemini)**: Kết nối `/api/ai/chat` truy vấn ngữ cảnh thực tế từ SQLite (danh sách sân trống, bảng giá, các kèo giao lưu đang mở, chính sách hoàn hủy) và hiển thị nút bấm nhảy thẳng tới màn hình Đặt sân hoặc Xem kèo.
