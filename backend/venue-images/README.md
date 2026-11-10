# Ảnh cơ sở (sân cầu lông)

Đặt ảnh `.jpg`, `.jpeg`, `.png` hoặc `.webp` vào thư mục này rồi **khởi động lại backend**.
Máy chủ phục vụ ảnh tại `http://<máy chủ>:8080/venue-images/<tên file>`.

Cách đặt tên:

- **Ảnh riêng cho một cơ sở:** tên bắt đầu bằng id cơ sở, ví dụ `1.jpg`, `5-san-tpt.png`.
  Id cơ sở xem trong app (Admin > Kiểm duyệt) hoặc API `GET /api/venues`.
- **Ảnh dùng chung:** tên bất kỳ không bắt đầu bằng số, ví dụ `san-a.jpg`, `san-b.jpg`.
  Các cơ sở chưa có ảnh riêng được chia lần lượt các ảnh này.

Thư mục trống thì cơ sở giữ ảnh cũ. Nên dùng ảnh ngang, rộng khoảng 1200px, dưới 500 KB để app tải nhanh.
