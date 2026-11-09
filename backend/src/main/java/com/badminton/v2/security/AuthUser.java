package com.badminton.v2.security;

/**
 * Người dùng đã đăng nhập, đọc từ JWT của mỗi request.
 *
 * @param id    id người dùng (claim "sub")
 * @param role  CUSTOMER | COURT_OWNER | ADMIN
 * @param email email đăng nhập
 */
public record AuthUser(Long id, String role, String email) {

    public boolean isAdmin() {
        return "ADMIN".equals(role);
    }

    public boolean isOwner() {
        return "COURT_OWNER".equals(role);
    }
}
