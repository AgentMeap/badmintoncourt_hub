package com.badminton.v2.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.ErrorResponse;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import com.badminton.v2.security.ForbiddenException;
import com.badminton.v2.security.UnauthorizedException;

import java.util.Map;
import java.util.NoSuchElementException;

/**
 * Trả mọi lỗi về cùng một dạng JSON {"error": "..."} với mã HTTP đúng nghĩa,
 * để app Flutter hiển thị được câu báo lỗi thay vì trang lỗi 500 mặc định của Spring.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    /** Optional.orElseThrow() khi không tìm thấy bản ghi theo id. */
    @ExceptionHandler(NoSuchElementException.class)
    public ResponseEntity<Map<String, String>> handleNotFound(NoSuchElementException ex) {
        return error(HttpStatus.NOT_FOUND, "Không tìm thấy dữ liệu yêu cầu.");
    }

    /** Vi phạm ràng buộc duy nhất (VD bấm "Xin tham gia" 2 lần cùng lúc). Giao dịch đã được rollback. */
    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<Map<String, String>> handleConflict(DataIntegrityViolationException ex) {
        log.debug("Data conflict: {}", ex.getMessage());
        return error(HttpStatus.CONFLICT, "Yêu cầu bị trùng, có thể bạn vừa bấm 2 lần. Vui lòng tải lại.");
    }

    @ExceptionHandler(ForbiddenException.class)
    public ResponseEntity<Map<String, String>> handleForbidden(ForbiddenException ex) {
        return error(HttpStatus.FORBIDDEN, ex.getMessage());
    }

    @ExceptionHandler(UnauthorizedException.class)
    public ResponseEntity<Map<String, String>> handleUnauthorized(UnauthorizedException ex) {
        return error(HttpStatus.UNAUTHORIZED, ex.getMessage());
    }

    /** Thiếu trường / sai kiểu số (VD Long.parseLong("null")), JSON hỏng, sai tham số URL. */
    @ExceptionHandler({
            IllegalArgumentException.class,
            HttpMessageNotReadableException.class,
            MethodArgumentTypeMismatchException.class,
            MissingServletRequestParameterException.class
    })
    public ResponseEntity<Map<String, String>> handleBadRequest(Exception ex) {
        log.debug("Bad request: {}", ex.getMessage());
        return error(HttpStatus.BAD_REQUEST, "Dữ liệu gửi lên không hợp lệ hoặc còn thiếu.");
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, String>> handleOther(Exception ex) {
        // Lỗi chuẩn của Spring MVC (404 không có route, 405 sai method...) giữ nguyên mã lỗi
        if (ex instanceof ErrorResponse er) {
            HttpStatusCode status = er.getStatusCode();
            return ResponseEntity.status(status).body(Map.of("error", messageFor(status)));
        }
        log.error("Unhandled error", ex);
        return error(HttpStatus.INTERNAL_SERVER_ERROR, "Máy chủ gặp lỗi, vui lòng thử lại sau.");
    }

    private static String messageFor(HttpStatusCode status) {
        return switch (status.value()) {
            case 404 -> "Không tìm thấy đường dẫn API.";
            case 405 -> "Phương thức không được hỗ trợ cho API này.";
            case 415 -> "Định dạng dữ liệu không được hỗ trợ.";
            default -> status.is4xxClientError() ? "Yêu cầu không hợp lệ." : "Máy chủ gặp lỗi, vui lòng thử lại sau.";
        };
    }

    private static ResponseEntity<Map<String, String>> error(HttpStatus status, String message) {
        return ResponseEntity.status(status).body(Map.of("error", message));
    }
}
