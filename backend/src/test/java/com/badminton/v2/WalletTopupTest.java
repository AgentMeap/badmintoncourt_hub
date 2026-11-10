package com.badminton.v2;

import com.badminton.v2.entity.User;
import com.badminton.v2.repository.WalletTransactionRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Nạp Ví Cầu Lông qua PayOS: chỉ cộng tiền khi đơn đã thanh toán, mỗi đơn cộng đúng một lần. */
class WalletTopupTest extends IntegrationTestBase {

    @Autowired private WalletTransactionRepository walletTransactionRepository;

    private double balance(User u) {
        return userRepository.findById(u.getId()).orElseThrow().getWalletBalance();
    }

    private long topupCount(User u) {
        return walletTransactionRepository.findByUserIdOrderByIdDesc(u.getId()).stream()
                .filter(t -> "TOPUP".equals(t.getType())).count();
    }

    @Test
    @DisplayName("Tạo đơn nạp chưa cộng tiền; giả lập thanh toán cộng đúng một lần")
    void topupCreditsOnce() throws Exception {
        User u = newUser("CUSTOMER", 0);
        String token = tokenOf(u);

        var created = body(mvc.perform(postAs(token, Map.of("amount", 50000), "/api/wallet/topup/payos"))
                .andExpect(status().isOk()).andReturn());
        long orderCode = created.path("orderCode").asLong();
        assertEquals("PENDING", created.path("status").asText());
        assertFalse(created.path("qrCodeData").asText().isBlank());
        assertTrue(created.path("canSimulate").asBoolean());
        assertEquals(0, balance(u), 0.001);

        // Hỏi trạng thái khi chưa thanh toán: vẫn chờ, chưa cộng tiền
        var pending = body(mvc.perform(getAs(token, "/api/wallet/topup/{c}", orderCode)).andExpect(status().isOk()).andReturn());
        assertFalse(pending.path("paid").asBoolean());
        assertEquals(0, balance(u), 0.001);

        var paid = body(mvc.perform(postAs(token, Map.of(), "/api/wallet/topup/{c}/simulate", orderCode))
                .andExpect(status().isOk()).andReturn());
        assertTrue(paid.path("paid").asBoolean());
        assertEquals(50000, paid.path("walletBalance").asDouble(), 0.001);

        // Bấm lại / gọi qua endpoint giả lập của đặt sân: không cộng lần hai
        mvc.perform(postAs(token, Map.of(), "/api/wallet/topup/{c}/simulate", orderCode)).andExpect(status().isOk());
        mvc.perform(postAs(token, Map.of(), "/api/payments/simulate-webhook/{c}", orderCode)).andExpect(status().isOk());
        mvc.perform(getAs(token, "/api/payments/{c}/status", orderCode)).andExpect(status().isOk());
        assertEquals(50000, balance(u), 0.001);
        assertEquals(1, topupCount(u));
    }

    @Test
    @DisplayName("Số tiền ngoài giới hạn bị từ chối")
    void invalidAmount() throws Exception {
        String token = tokenOf(newUser("CUSTOMER", 0));
        mvc.perform(postAs(token, Map.of("amount", 5000), "/api/wallet/topup/payos")).andExpect(status().isBadRequest());
        mvc.perform(postAs(token, Map.of("amount", 20_000_000), "/api/wallet/topup/payos")).andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("Người khác không xem / giả lập được đơn nạp của mình")
    void otherUserForbidden() throws Exception {
        User owner = newUser("CUSTOMER", 0);
        User other = newUser("CUSTOMER", 0);
        long orderCode = body(mvc.perform(postAs(tokenOf(owner), Map.of("amount", 100000), "/api/wallet/topup/payos"))
                .andExpect(status().isOk()).andReturn()).path("orderCode").asLong();

        mvc.perform(getAs(tokenOf(other), "/api/wallet/topup/{c}", orderCode)).andExpect(status().isForbidden());
        mvc.perform(postAs(tokenOf(other), Map.of(), "/api/wallet/topup/{c}/simulate", orderCode)).andExpect(status().isForbidden());
        // Webhook không kèm xác nhận từ PayOS (chưa cấu hình key) thì không cộng tiền
        mvc.perform(postAs(tokenOf(other), Map.of("data", Map.of("orderCode", orderCode)), "/api/payments/payos-webhook"))
                .andExpect(status().isOk());
        assertEquals(0, balance(owner), 0.001);
        assertEquals(0, balance(other), 0.001);
    }
}
