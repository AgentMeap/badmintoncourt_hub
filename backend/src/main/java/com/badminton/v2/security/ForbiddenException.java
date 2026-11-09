package com.badminton.v2.security;

/** Người dùng đã đăng nhập nhưng không có quyền với dữ liệu này -> HTTP 403. */
public class ForbiddenException extends RuntimeException {

    public ForbiddenException(String message) {
        super(message);
    }
}
