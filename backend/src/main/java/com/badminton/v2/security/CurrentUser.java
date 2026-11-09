package com.badminton.v2.security;

import org.springframework.web.context.request.RequestAttributes;
import org.springframework.web.context.request.RequestContextHolder;

import java.util.Optional;

/**
 * Truy cập người dùng của request hiện tại (do {@link AuthInterceptor} gắn vào).
 *
 * <p>Mọi API cần đăng nhập đều đi qua interceptor, nên khi gọi qua HTTP luôn có người dùng.
 * Khi controller được gọi trực tiếp không qua HTTP (VD test tích hợp gọi hàm controller),
 * không có request nên các hàm kiểm tra quyền bỏ qua và {@link #idOr(Object)} dùng giá trị dự phòng.
 */
public final class CurrentUser {

    /** Tên thuộc tính request chứa {@link AuthUser}. */
    public static final String ATTRIBUTE = "badminton.authUser";

    private CurrentUser() {
    }

    public static Optional<AuthUser> get() {
        RequestAttributes attrs = RequestContextHolder.getRequestAttributes();
        if (attrs == null) return Optional.empty();
        Object value = attrs.getAttribute(ATTRIBUTE, RequestAttributes.SCOPE_REQUEST);
        return value instanceof AuthUser user ? Optional.of(user) : Optional.empty();
    }

    /** Có đang xử lý một request HTTP không (false khi controller bị gọi trực tiếp trong test). */
    public static boolean inHttpRequest() {
        return RequestContextHolder.getRequestAttributes() != null;
    }

    /**
     * Id người dùng đã đăng nhập. Không có request HTTP (gọi trực tiếp) thì dùng [fallback]
     * (giá trị trong body cũ như "userId", "customerId").
     */
    public static Long idOr(Object fallback) {
        Optional<AuthUser> user = get();
        if (user.isPresent()) return user.get().id();
        if (inHttpRequest()) throw new UnauthorizedException("Vui lòng đăng nhập để tiếp tục.");
        return fallback == null ? null : Long.valueOf(String.valueOf(fallback));
    }

    public static boolean isAdmin() {
        return get().map(AuthUser::isAdmin).orElse(false);
    }

    /** Chỉ chính chủ [userId] hoặc Admin được thao tác. */
    public static void requireSelfOrAdmin(Long userId) {
        Optional<AuthUser> user = get();
        if (user.isEmpty()) {
            if (inHttpRequest()) throw new UnauthorizedException("Vui lòng đăng nhập để tiếp tục.");
            return;
        }
        if (!user.get().isAdmin() && !user.get().id().equals(userId)) {
            throw new ForbiddenException("Bạn không có quyền truy cập dữ liệu của tài khoản khác.");
        }
    }

    /** Chỉ một trong các người dùng [allowedIds] (VD khách đặt vé hoặc chủ sân) hoặc Admin. */
    public static void requireAnyOf(String message, Long... allowedIds) {
        Optional<AuthUser> user = get();
        if (user.isEmpty()) {
            if (inHttpRequest()) throw new UnauthorizedException("Vui lòng đăng nhập để tiếp tục.");
            return;
        }
        if (user.get().isAdmin()) return;
        for (Long id : allowedIds) {
            if (id != null && id.equals(user.get().id())) return;
        }
        throw new ForbiddenException(message);
    }
}
