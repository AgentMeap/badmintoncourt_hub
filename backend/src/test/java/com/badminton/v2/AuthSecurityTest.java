package com.badminton.v2;

import com.badminton.v2.entity.User;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Giai đoạn 1: đăng nhập, JWT, phân quyền theo vai trò và tài khoản bị khóa. */
class AuthSecurityTest extends IntegrationTestBase {

    @Test
    @DisplayName("Đăng nhập tài khoản demo trả về JWT và vai trò")
    void loginReturnsJwt() throws Exception {
        var res = mvc.perform(postAs(null, Map.of("email", CUSTOMER, "password", "123456"), "/api/auth/login"))
                .andExpect(status().isOk())
                .andReturn();
        var body = body(res);
        assertFalse(body.path("token").asText().isBlank());
        assertEquals("CUSTOMER", body.path("role").asText());
    }

    @Test
    @DisplayName("Sai mật khẩu -> 401, email không tồn tại -> 401")
    void loginRejectsWrongCredentials() throws Exception {
        mvc.perform(postAs(null, Map.of("email", CUSTOMER, "password", "sai-mat-khau"), "/api/auth/login"))
                .andExpect(status().isUnauthorized());
        mvc.perform(postAs(null, Map.of("email", "khong-ton-tai@test.vn", "password", "123456"), "/api/auth/login"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("API cần đăng nhập: không có / sai token -> 401")
    void protectedApiNeedsToken() throws Exception {
        mvc.perform(getAs(null, "/api/admin/dashboard")).andExpect(status().isUnauthorized());
        mvc.perform(getAs("token-gia-mao", "/api/admin/dashboard")).andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Phân quyền: khu Admin / Chủ sân chặn sai vai trò")
    void roleBasedAccess() throws Exception {
        String customer = tokenOf(CUSTOMER);
        String owner = tokenOf(OWNER);
        String admin = tokenOf(ADMIN);

        mvc.perform(getAs(customer, "/api/admin/dashboard")).andExpect(status().isForbidden());
        mvc.perform(getAs(owner, "/api/admin/dashboard")).andExpect(status().isForbidden());
        mvc.perform(getAs(admin, "/api/admin/dashboard")).andExpect(status().isOk());

        Long ownerId = user(OWNER).getId();
        mvc.perform(getAs(customer, "/api/owner/{id}/dashboard", ownerId)).andExpect(status().isForbidden());
        mvc.perform(getAs(owner, "/api/owner/{id}/dashboard", ownerId)).andExpect(status().isOk());
    }

    @Test
    @DisplayName("Không xem được hồ sơ / ví của người khác")
    void cannotReadOtherProfile() throws Exception {
        User other = newUser("CUSTOMER", 0);
        mvc.perform(getAs(tokenOf(CUSTOMER), "/api/auth/profile/{id}", other.getId()))
                .andExpect(status().isForbidden());
        mvc.perform(getAs(tokenOf(other), "/api/auth/profile/{id}", other.getId()))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("Admin khóa tài khoản: token cũ bị chặn ngay, đăng nhập bị từ chối; mở khóa thì dùng lại được")
    void lockedAccountIsBlocked() throws Exception {
        String admin = tokenOf(ADMIN);
        User victim = newUser("CUSTOMER", 0);
        String victimToken = tokenOf(victim);

        mvc.perform(getAs(victimToken, "/api/auth/profile/{id}", victim.getId())).andExpect(status().isOk());

        var locked = body(mvc.perform(patchAs(admin, Map.of(), "/api/admin/users/{id}/toggle-active", victim.getId()))
                .andExpect(status().isOk()).andReturn());
        assertFalse(locked.path("active").asBoolean(true));

        mvc.perform(getAs(victimToken, "/api/auth/profile/{id}", victim.getId())).andExpect(status().isUnauthorized());
        mvc.perform(postAs(null, Map.of("email", victim.getEmail(), "password", "123456"), "/api/auth/login"))
                .andExpect(status().isForbidden());

        mvc.perform(patchAs(admin, Map.of(), "/api/admin/users/{id}/toggle-active", victim.getId()))
                .andExpect(status().isOk());
        mvc.perform(getAs(victimToken, "/api/auth/profile/{id}", victim.getId())).andExpect(status().isOk());
    }

    @Test
    @DisplayName("Không khóa được tài khoản Admin (kể cả chính mình)")
    void cannotLockAdmin() throws Exception {
        User admin = user(ADMIN);
        mvc.perform(patchAs(tokenOf(admin), Map.of(), "/api/admin/users/{id}/toggle-active", admin.getId()))
                .andExpect(status().isBadRequest());
        assertTrue(user(ADMIN).isActive());
    }
}
