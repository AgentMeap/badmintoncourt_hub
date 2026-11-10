package com.badminton.v2.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.*;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/media")
public class MediaController {

    private static final Logger log = LoggerFactory.getLogger(MediaController.class);
    private static final Path UPLOAD_DIR = Paths.get("./uploads/videos");

    public MediaController() {
        try {
            if (!Files.exists(UPLOAD_DIR)) {
                Files.createDirectories(UPLOAD_DIR);
            }
        } catch (IOException e) {
            log.error("Failed to initialize video upload directory: {}", e.getMessage());
        }
    }

    @PostMapping("/videos")
    public ResponseEntity<?> uploadVideo(@RequestParam("file") MultipartFile file) {
        if (file.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "File video trống!"));
        }

        String originalName = file.getOriginalFilename();
        if (originalName == null) originalName = "video.mp4";
        String cleanName = originalName.replaceAll("[^a-zA-Z0-9._-]", "_");
        String extension = "";
        int dotIdx = cleanName.lastIndexOf('.');
        if (dotIdx > 0) {
            extension = cleanName.substring(dotIdx).toLowerCase();
        }

        // Validate basic video extensions
        if (!extension.matches("\\.(mp4|mov|m4v|webm|avi|mkv)")) {
            return ResponseEntity.badRequest().body(Map.of("error", "Định dạng video không được hỗ trợ (chỉ chấp nhận MP4, MOV, WEBM)!"));
        }

        String uniqueFileName = UUID.randomUUID().toString().substring(0, 8) + "_" + cleanName;
        Path targetPath = UPLOAD_DIR.resolve(uniqueFileName);

        try {
            Files.copy(file.getInputStream(), targetPath, StandardCopyOption.REPLACE_EXISTING);
            String fileUrl = "/uploads/videos/" + uniqueFileName;
            log.info("Uploaded video successfully: {} ({} bytes)", uniqueFileName, file.getSize());

            return ResponseEntity.ok(Map.of(
                    "url", fileUrl,
                    "videoUrl", fileUrl,
                    "fileName", uniqueFileName,
                    "size", file.getSize()
            ));
        } catch (IOException e) {
            log.error("Video save failed: {}", e.getMessage());
            return ResponseEntity.internalServerError().body(Map.of("error", "Lỗi lưu file video lên máy chủ: " + e.getMessage()));
        }
    }

    private static final Path IMAGE_DIR = Paths.get("./uploads/venues");
    private static final long MAX_IMAGE_BYTES = 8L * 1024 * 1024;

    /**
     * Chủ sân tải ảnh cơ sở (jpg / png / webp, tối đa 8 MB).
     * Trả về {"url": "/uploads/venues/<tên file>"} để gửi kèm khi đăng ký cơ sở.
     */
    @PostMapping("/images")
    public ResponseEntity<?> uploadImage(@RequestParam("file") MultipartFile file) {
        if (file.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "File ảnh trống."));
        }
        if (file.getSize() > MAX_IMAGE_BYTES) {
            return ResponseEntity.badRequest().body(Map.of("error", "Ảnh quá lớn (tối đa 8 MB)."));
        }
        String ext = imageExtension(file);
        if (ext == null) {
            return ResponseEntity.badRequest().body(Map.of("error", "Chỉ nhận ảnh JPG, PNG hoặc WEBP."));
        }
        String fileName = UUID.randomUUID().toString().replace("-", "").substring(0, 16) + ext;
        try {
            Files.createDirectories(IMAGE_DIR);
            Files.copy(file.getInputStream(), IMAGE_DIR.resolve(fileName), StandardCopyOption.REPLACE_EXISTING);
        } catch (IOException e) {
            log.error("Image save failed: {}", e.getMessage());
            return ResponseEntity.internalServerError().body(Map.of("error", "Không lưu được ảnh lên máy chủ."));
        }
        String url = "/uploads/venues/" + fileName;
        return ResponseEntity.ok(Map.of("url", url, "size", file.getSize()));
    }

    /** Đuôi file theo nội dung thật (vài byte đầu), null nếu không phải ảnh được hỗ trợ. */
    private static String imageExtension(MultipartFile file) {
        byte[] h = new byte[12];
        int n;
        try (var in = file.getInputStream()) {
            n = in.readNBytes(h, 0, h.length);
        } catch (IOException e) {
            return null;
        }
        if (n >= 3 && (h[0] & 0xFF) == 0xFF && (h[1] & 0xFF) == 0xD8 && (h[2] & 0xFF) == 0xFF) return ".jpg";
        if (n >= 8 && (h[0] & 0xFF) == 0x89 && h[1] == 'P' && h[2] == 'N' && h[3] == 'G') return ".png";
        if (n >= 12 && h[0] == 'R' && h[1] == 'I' && h[2] == 'F' && h[3] == 'F'
                && h[8] == 'W' && h[9] == 'E' && h[10] == 'B' && h[11] == 'P') return ".webp";
        return null;
    }
}
