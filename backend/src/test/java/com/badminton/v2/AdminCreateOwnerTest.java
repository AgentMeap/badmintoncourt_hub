package com.badminton.v2;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Admin tạo tài khoản chủ sân; chủ sân đăng nhập được ngay; người khác không gọi được. */
class AdminCreateOwnerTest extends IntegrationTestBase {

    private Map<String, Object> owner(String email) {
        return Map.of("fullName", "Chủ sân mới", "email", email, "phone", "0912345678", "password", "matkhau1");
    }

    @Test
    @DisplayName("Admin tạo chủ sân -> đăng nhập được với vai trò COURT_OWNER")
    void adminCreatesOwner() throws Exception {
        String email = "owner" + System.nanoTime() + "@test.vn";
        var res = body(mvc.perform(postAs(tokenOf(ADMIN), owner(email), "/api/admin/users"))
                .andExpect(status().isOk()).andReturn());
        assertEquals("COURT_OWNER", res.path("role").asText());

        var login = body(mvc.perform(postAs(null, Map.of("email", email, "password", "matkhau1"), "/api/auth/login"))
                .andExpect(status().isOk()).andReturn());
        assertEquals("COURT_OWNER", login.path("role").asText());

        // Trùng email
        mvc.perform(postAs(tokenOf(ADMIN), owner(email), "/api/admin/users")).andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("Không phải Admin thì không tạo được; dữ liệu sai bị từ chối")
    void onlyAdminAndValidated() throws Exception {
        String email = "x" + System.nanoTime() + "@test.vn";
        mvc.perform(postAs(tokenOf(OWNER), owner(email), "/api/admin/users")).andExpect(status().isForbidden());
        mvc.perform(postAs(tokenOf(CUSTOMER), owner(email), "/api/admin/users")).andExpect(status().isForbidden());
        mvc.perform(postAs(tokenOf(ADMIN), Map.of("fullName", "A B", "email", "sai-email", "phone", "0912345678",
                "password", "matkhau1"), "/api/admin/users")).andExpect(status().isBadRequest());
        assertTrue(userRepository.findByEmailIgnoreCase(email).isEmpty());
    }
}
