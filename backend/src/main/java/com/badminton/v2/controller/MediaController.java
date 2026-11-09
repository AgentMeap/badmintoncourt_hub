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
}
