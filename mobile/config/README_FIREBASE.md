# Cấu hình đăng nhập Google (Firebase) – chỉ Android

Đăng nhập Google dùng cấu hình truyền lúc chạy bằng `--dart-define-from-file`.
Thông báo đẩy (mục 5) cần thêm `android/app/google-services.json`: có file này thì Gradle tự bật plugin
google-services; không có thì app vẫn build và chạy bình thường, chỉ không nhận được thông báo khi app đã đóng.

## 1. Firebase Console

1. Tạo project tại <https://console.firebase.google.com>.
2. **Authentication → Sign-in method → Google → Enable** (chọn email hỗ trợ, Lưu).
3. **Project settings → General → Your apps → Add app → Android**
   - Package name: `com.badminton.badminton_v2_mobile`
   - Thêm **SHA-1** của máy build (bắt buộc cho Google Sign-In):
     ```powershell
     cd mobile\android
     .\gradlew signingReport
     ```
     Lấy dòng `SHA1` của variant `debug`. Mỗi thành viên build bằng máy riêng cần thêm SHA-1 của mình.
   - Tải `google-services.json` về máy để **đọc** các giá trị ở bước 2
     (không cần chép vào project, không commit file này).

## 2. Lấy các giá trị cấu hình (từ google-services.json)

| Khóa | Vị trí trong google-services.json |
|---|---|
| `FIREBASE_API_KEY` | `client[0].api_key[0].current_key` |
| `FIREBASE_ANDROID_APP_ID` | `client[0].client_info.mobilesdk_app_id` |
| `FIREBASE_MESSAGING_SENDER_ID` | `project_info.project_number` |
| `FIREBASE_PROJECT_ID` | `project_info.project_id` |
| `GOOGLE_WEB_CLIENT_ID` | `client[0].oauth_client[]` phần tử có `"client_type": 3` → `client_id` |

Nếu không thấy `oauth_client` loại 3: bật Google ở bước 1 trước rồi tải lại file
(hoặc lấy ở Authentication → Sign-in method → Google → Web SDK configuration → Web client ID).

## 3. Mobile

```powershell
cd mobile
copy config\firebase.example.json config\firebase.json   # rồi điền giá trị thật
flutter pub get
flutter run --dart-define-from-file=config/firebase.json
```

`config/firebase.json` đã nằm trong `.gitignore`. Không có file này app vẫn chạy bình thường,
chỉ nút "Tiếp tục với Google" báo chưa cấu hình.

## 4. Backend

Đặt biến môi trường trước khi chạy Spring Boot:

```powershell
$env:FIREBASE_PROJECT_ID = "badminton-hub-xxxxx"
$env:JWT_SECRET = "<chuỗi ngẫu nhiên dài ít nhất 32 ký tự>"
$env:APP_DEMO_MODE = "true"   # false: tắt mật khẩu/OTP demo 123456
mvn spring-boot:run
```

Backend tự tải khóa công khai của Google để kiểm tra Firebase ID token, không cần file service account.

## Lỗi thường gặp

- Bấm chọn tài khoản xong báo "Đã hủy" ngay: thường do **thiếu SHA-1** hoặc **sai Web client ID**.
- Backend trả 503: chưa đặt `FIREBASE_PROJECT_ID`.
- Backend trả 401 "Phiên đăng nhập Google không hợp lệ": Project ID của backend khác project của app.

## 5. Thông báo đẩy (Firebase Cloud Messaging)

Thông báo (duyệt đơn, tin nhắn nhóm, nhắc lịch, hoàn cọc...) hiện trên điện thoại kể cả khi app đã đóng.

**Mobile (Android):**
1. Chép `google-services.json` (Project settings → Your apps → Android `com.badminton.badminton_v2_mobile`)
   vào `mobile/android/app/` – file đã nằm trong `.gitignore`.
2. `flutter pub get` rồi chạy như mục 3. Lần đầu đăng nhập, app hỏi quyền hiện thông báo (Android 13+) → **Cho phép**.
3. Máy ảo phải dùng image có **Google Play**; dễ nhất là thử trên điện thoại thật.

**Backend:**
1. Firebase Console → **Project settings → Service accounts → Generate new private key** → lưu thành
   `backend/firebase-service-account.json` (đã nằm trong `.gitignore`, **không commit**, không gửi cho ai).
2. Trong `backend/application-secret.properties`:
   ```properties
   app.fcm.credentials-file=./firebase-service-account.json
   ```
3. Khởi động lại backend; log có dòng `FCM đã bật cho project ...`. Để trống thì backend tắt thông báo đẩy
   (app vẫn có banner thông báo khi đang mở, hỏi máy chủ 30 giây/lần).

**Cách hoạt động:** đăng nhập → app gửi mã thiết bị lên `POST /api/devices`; mỗi thông báo backend tạo ra đều được
đẩy tới mọi điện thoại của người nhận; tin nhắn cùng một kèo thay nhau trên thanh thông báo; bấm thông báo mở đúng màn hình;
đăng xuất → `POST /api/devices/unregister`.

