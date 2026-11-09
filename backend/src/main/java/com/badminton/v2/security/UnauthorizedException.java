package com.badminton.v2.security;

/** Thao tác cần đăng nhập nhưng request không có phiên hợp lệ -> HTTP 401. */
public class UnauthorizedException extends RuntimeException {

    public UnauthorizedException(String message) {
        super(message);
    }
}
