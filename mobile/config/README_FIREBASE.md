# Cấu hình đăng nhập Google (Firebase) – chỉ Android

App không dùng `google-services.json` / plugin Gradle. Cấu hình Firebase được truyền lúc chạy
bằng `--dart-define-from-file`, backend chỉ cần biết Project ID.

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
