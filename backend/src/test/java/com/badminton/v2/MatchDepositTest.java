package com.badminton.v2;

import com.badminton.v2.entity.NotificationItem;
import com.badminton.v2.entity.User;
import com.badminton.v2.entity.WalletTransaction;
import com.badminton.v2.repository.MatchPostRepository;
import com.badminton.v2.repository.NotificationRepository;
import com.badminton.v2.repository.WalletTransactionRepository;
import com.badminton.v2.service.MatchDepositService;
import com.badminton.v2.service.MatchReminderScheduler;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Cọc kèo giao lưu qua ví: trừ khi xin, hoàn khi bị từ chối / tự hủy / bị mời ra / chủ kèo hủy,
 * hoàn theo mốc 24h – 2h khi tự rời kèo, trả chủ kèo khi kèo kết thúc (không trả 2 lần).
 */
class MatchDepositTest extends IntegrationTestBase {

    private static final DateTimeFormatter HM = DateTimeFormatter.ofPattern("HH:mm");

    @Autowired private WalletTransactionRepository walletTransactionRepository;
    @Autowired private NotificationRepository notificationRepository;
    @Autowired private MatchReminderScheduler scheduler;
    @Autowired private MatchDepositService depositService;
    @Autowired private MatchPostRepository matchPostRepository;

    /** Kèo bắt đầu sau [hoursFromNow] giờ, đánh 2 giờ, tối đa 4 người (đang có 1). */
    private long createMatch(User host, int depositPercent, double fee, long hoursFromNow) throws Exception {
        LocalDateTime start = LocalDateTime.now().plusHours(hoursFromNow).truncatedTo(ChronoUnit.MINUTES);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("venueId", ownerApprovedVenue().getId());
        body.put("title", "Kèo test cọc " + depositPercent + "%");
        body.put("playDate", start.toLocalDate().toString());
        body.put("startTime", start.format(HM));
        body.put("endTime", start.plusHours(2).format(HM));
        body.put("requiredSkill", "TB_YEU");
        body.put("maxPlayers", 4);
        body.put("currentPlayers", 1);
        body.put("feePerPlayer", fee);
        body.put("depositPercent", depositPercent);
        return body(mvc.perform(postAs(tokenOf(host), body, "/api/matches")).andExpect(status().isOk()).andReturn())
                .path("id").asLong();
    }

    private double balance(User u) {
        return userRepository.findById(u.getId()).orElseThrow().getWalletBalance();
    }

    private long join(User u, long matchId) throws Exception {
        return body(mvc.perform(postAs(tokenOf(u), Map.of(), "/api/matches/{id}/join", matchId))
                .andExpect(status().isOk()).andReturn()).path("id").asLong();
    }

    private void review(User host, long matchId, long pid, String decision) throws Exception {
        mvc.perform(patchAs(tokenOf(host), Map.of("status", decision), "/api/matches/{m}/participants/{p}", matchId, pid))
                .andExpect(status().isOk());
    }

    private WalletTransaction lastTx(User u) {
        return walletTransactionRepository.findByUserIdOrderByIdDesc(u.getId()).get(0);
    }

    @Test
    @DisplayName("Đăng kèo: cọc = phí × % làm tròn lên 1.000đ; chỉ nhận 0 / 50 / 100%")
    void depositAmountOnCreate() throws Exception {
        User host = newUser("CUSTOMER", 0);
        long id = createMatch(host, 50, 65_000, 48);
        var post = body(mvc.perform(getAs(tokenOf(host), "/api/matches/{id}", id)).andReturn()).path("post");
        assertEquals(50, post.path("depositPercent").asInt());
        assertEquals(33_000, post.path("depositAmount").asDouble());

        assertEquals(0, MatchDepositService.depositFor(65_000, 0));
        assertEquals(65_000, MatchDepositService.depositFor(65_000, 100));

        Map<String, Object> bad = new LinkedHashMap<>(Map.of("venueId", ownerApprovedVenue().getId(), "depositPercent", 30));
        mvc.perform(postAs(tokenOf(host), bad, "/api/matches")).andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("Không đủ tiền: 402 kèm số cần và số dư, không tạo đơn, không trừ ví")
    void insufficientBalance() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User poor = newUser("CUSTOMER", 20_000);
        long id = createMatch(host, 100, 60_000, 48);

        var err = body(mvc.perform(postAs(tokenOf(poor), Map.of(), "/api/matches/{id}/join", id))
                .andExpect(status().is(402)).andReturn());
        assertEquals(60_000, err.path("needed").asDouble());
        assertEquals(20_000, err.path("balance").asDouble());
        assertEquals(20_000, balance(poor));
        var asPoor = body(mvc.perform(getAs(tokenOf(poor), "/api/matches/{id}", id)).andReturn());
        assertTrue(asPoor.path("myStatus").isNull());
    }

    @Test
    @DisplayName("Xin tham gia trừ cọc ngay; bị từ chối hoàn đủ và thông báo có số tiền hoàn")
    void holdThenRejectRefunds() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User a = newUser("CUSTOMER", 100_000);
        long id = createMatch(host, 50, 65_000, 48);

        long pid = join(a, id);
        assertEquals(67_000, balance(a));
        assertEquals(MatchDepositService.HOLD, lastTx(a).getType());
        var asA = body(mvc.perform(getAs(tokenOf(a), "/api/matches/{id}", id)).andReturn());
        assertEquals("HELD", asA.path("participants").get(0).path("depositStatus").asText());

        review(host, id, pid, "REJECTED");
        assertEquals(100_000, balance(a));
        assertEquals(MatchDepositService.REFUND, lastTx(a).getType());
        NotificationItem n = notificationRepository.findByUserIdOrderByIdDesc(a.getId()).get(0);
        assertTrue(n.getBody().contains("33.000đ"));
    }

    @Test
    @DisplayName("Kèo không cọc: xin tham gia không đụng tới ví")
    void noDeposit() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User a = newUser("CUSTOMER", 0);
        long id = createMatch(host, 0, 65_000, 48);
        join(a, id);
        assertEquals(0, balance(a));
        assertTrue(walletTransactionRepository.findByUserIdOrderByIdDesc(a.getId()).isEmpty());
    }

    @Test
    @DisplayName("Tự hủy đơn chờ duyệt: hoàn đủ")
    void cancelPendingRefunds() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User a = newUser("CUSTOMER", 50_000);
        long id = createMatch(host, 100, 50_000, 3); // sát giờ nhưng chưa duyệt -> vẫn hoàn đủ
        join(a, id);
        assertEquals(0, balance(a));

        var preview = body(mvc.perform(getAs(tokenOf(a), "/api/matches/{id}/leave-preview", id)).andReturn());
        assertEquals(50_000, preview.path("refundAmount").asDouble());

        var res = body(mvc.perform(postAs(tokenOf(a), Map.of(), "/api/matches/{id}/leave", id))
                .andExpect(status().isOk()).andReturn());
        assertEquals(50_000, res.path("refundedAmount").asDouble());
        assertEquals(50_000, balance(a));
    }

    @Test
    @DisplayName("Thành viên tự rời kèo: ≥24h hoàn đủ, 2–24h hoàn 50% (50% cho chủ kèo), <2h mất cọc")
    void selfLeaveRefundTiers() throws Exception {
        record Case(long hours, double refund, double toHost) {}
        for (Case c : new Case[]{new Case(48, 40_000, 0), new Case(5, 20_000, 20_000), new Case(1, 0, 40_000)}) {
            User host = newUser("CUSTOMER", 0);
            User a = newUser("CUSTOMER", 40_000);
            long id = createMatch(host, 100, 40_000, c.hours());
            review(host, id, join(a, id), "APPROVED");

            var preview = body(mvc.perform(getAs(tokenOf(a), "/api/matches/{id}/leave-preview", id)).andReturn());
            assertEquals(c.refund(), preview.path("refundAmount").asDouble(), "preview " + c);
            assertEquals(c.toHost(), preview.path("forfeitAmount").asDouble(), "preview " + c);

            var res = body(mvc.perform(postAs(tokenOf(a), Map.of(), "/api/matches/{id}/leave", id))
                    .andExpect(status().isOk()).andReturn());
            assertEquals(c.refund(), res.path("refundedAmount").asDouble(), "leave " + c);
            assertEquals(c.refund(), balance(a), "ví người rời " + c);
            assertEquals(c.toHost(), balance(host), "ví chủ kèo " + c);
        }
    }

    @Test
    @DisplayName("Chủ kèo mời ra: mặc định hoàn đủ, chọn 'theo chính sách' thì áp mốc giờ")
    void removeWithPolicy() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User a = newUser("CUSTOMER", 40_000);
        long id = createMatch(host, 100, 40_000, 5); // 2–24h -> 50%
        long pid = join(a, id);
        review(host, id, pid, "APPROVED");
        mvc.perform(postAs(tokenOf(host), Map.of("refundMode", "POLICY"), "/api/matches/{m}/participants/{p}/remove", id, pid))
                .andExpect(status().isOk());
        assertEquals(20_000, balance(a));
        assertEquals(20_000, balance(host));
    }

    @Test
    @DisplayName("Chủ kèo mời ra hoặc hủy kèo: hoàn đủ cho mọi người")
    void removeAndCancelRefundAll() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User a = newUser("CUSTOMER", 30_000);
        User b = newUser("CUSTOMER", 30_000);
        User c = newUser("CUSTOMER", 30_000);
        long id = createMatch(host, 100, 30_000, 5);
        long pa = join(a, id);
        long pb = join(b, id);
        join(c, id); // c còn chờ duyệt
        review(host, id, pa, "APPROVED");
        review(host, id, pb, "APPROVED");

        mvc.perform(postAs(tokenOf(host), Map.of(), "/api/matches/{m}/participants/{p}/remove", id, pa))
                .andExpect(status().isOk());
        assertEquals(30_000, balance(a));

        var held = body(mvc.perform(getAs(tokenOf(host), "/api/matches/{id}", id)).andReturn());
        assertEquals(30_000, held.path("depositHeldTotal").asDouble());

        mvc.perform(postAs(tokenOf(host), Map.of("reason", "Mưa to"), "/api/matches/{id}/cancel", id))
                .andExpect(status().isOk());
        assertEquals(30_000, balance(b));
        assertEquals(30_000, balance(c));
        assertEquals(0, balance(host));
    }

    @Test
    @DisplayName("Kèo kết thúc: cọc thành viên đã duyệt vào ví chủ kèo, đơn chưa duyệt được hoàn, không trả 2 lần")
    void completedPaysHostOnce() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User a = newUser("CUSTOMER", 50_000);
        User b = newUser("CUSTOMER", 50_000);
        User pending = newUser("CUSTOMER", 50_000);
        long id = createMatch(host, 50, 50_000, 48); // cọc 25.000đ
        review(host, id, join(a, id), "APPROVED");
        review(host, id, join(b, id), "APPROVED");
        join(pending, id);

        LocalDateTime end = LocalDateTime.now().plusHours(50).plusMinutes(5);
        scheduler.closeFinished(end);
        assertEquals(50_000, balance(host));
        assertEquals(MatchDepositService.PAYOUT, lastTx(host).getType());
        assertEquals(50_000, balance(pending));
        assertEquals(25_000, balance(a));

        // Gọi lại (tác vụ nền chạy lần nữa / gọi thẳng) không trả thêm
        scheduler.closeFinished(end.plusMinutes(5));
        depositService.settleCompleted(matchPostRepository.findById(id).orElseThrow());
        assertEquals(50_000, balance(host));
    }
}
