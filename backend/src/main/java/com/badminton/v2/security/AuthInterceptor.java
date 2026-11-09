package com.badminton.v2.security;

import com.badminton.v2.repository.UserRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

/**
 * Chặn mọi API /api/** trừ danh sách công khai: đọc "Authorization: Bearer <JWT>",
 * kiểm tra token, tài khoản còn hoạt động, và vai trò cho nhóm /api/admin, /api/owner.
 * Người dùng hợp lệ được gắn vào request (đọc lại bằng {@link CurrentUser}).
 */
@Component
public class AuthInterceptor implements HandlerInterceptor {

    /** API không cần đăng nhập: "METHOD path" (path khớp chính xác). */
    private static final Set<String> PUBLIC_EXACT = Set.of(
            "POST /api/auth/login",
            "POST /api/auth/register",
            "POST /api/auth/google",
            "POST /api/auth/send-otp",
            "POST /api/auth/verify-otp",
            "POST /api/auth/reset-password",
            "POST /api/payments/payos-webhook",
            "GET /api/venues",
            "GET /api/reviews",
            "GET /api/matches"
    );

    /** API công khai dạng có tham số trên đường dẫn (chỉ GET). */
    private static final Pattern PUBLIC_GET = Pattern.compile(
            "^/api/(venues/\\d+|reviews/venue/\\d+)$");

    private final JwtService jwtService;
    private final UserRepository userRepository;
    private final ObjectMapper objectMapper;

    public AuthInterceptor(JwtService jwtService, UserRepository userRepository, ObjectMapper objectMapper) {
        this.jwtService = jwtService;
        this.userRepository = userRepository;
        this.objectMapper = objectMapper;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler)
            throws IOException {
        String method = request.getMethod();
        String path = request.getRequestURI();
        if ("OPTIONS".equals(method) || !path.startsWith("/api/")) return true;

        AuthUser user = null;
        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")) {
            user = jwtService.verify(header.substring(7).trim());
        }
        if (user != null) request.setAttribute(CurrentUser.ATTRIBUTE, user);

        boolean isPublic = PUBLIC_EXACT.contains(method + " " + path)
                || ("GET".equals(method) && PUBLIC_GET.matcher(path).matches());
        if (isPublic) return true;

        if (user == null) {
            return reject(response, 401, "Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.");
        }
        // Tài khoản bị Admin khóa sau khi đã cấp token: chặn ngay ở request kế tiếp
        Long userId = user.id();
        boolean active = userRepository.findById(userId).map(u -> u.isActive()).orElse(false);
        if (!active) {
            return reject(response, 401, "Tài khoản không còn hoạt động, vui lòng liên hệ quản trị viên.");
        }

        if ((path.startsWith("/api/admin/") || path.equals("/api/auth/demo-accounts")) && !user.isAdmin()) {
            return reject(response, 403, "Chức năng này chỉ dành cho Quản trị viên.");
        }
        boolean ownerArea = path.startsWith("/api/owner/") || path.startsWith("/api/venues/owner");
        if (ownerArea && !user.isOwner() && !user.isAdmin()) {
            return reject(response, 403, "Chức năng này chỉ dành cho Chủ sân.");
        }
        return true;
    }

    private boolean reject(HttpServletResponse response, int status, String message) throws IOException {
        response.setStatus(status);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());
        response.getWriter().write(objectMapper.writeValueAsString(Map.of("error", message)));
        return false;
    }
}
