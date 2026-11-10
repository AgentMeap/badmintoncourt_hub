package com.badminton.v2;

import com.badminton.v2.entity.NotificationItem;
import com.badminton.v2.entity.User;
import com.badminton.v2.repository.NotificationRepository;
import com.badminton.v2.service.MatchReminderScheduler;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Kèo giao lưu: xin tham gia -> thông báo mở đúng kèo (S30) -> duyệt / từ chối, hủy đơn, tự rời kèo, mời ra,
 * nhắc lịch, tự đóng kèo qua giờ, chủ kèo hủy kèo, nhóm chat. */
class MatchmakingFlowTest extends IntegrationTestBase {

    @Autowired
    private NotificationRepository notificationRepository;

    @Autowired
    private MatchReminderScheduler reminderScheduler;

    private long createMatch(User host) throws Exception {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("venueId", ownerApprovedVenue().getId());
        body.put("title", "Kèo test duyệt thành viên");
        body.put("playDate", LocalDate.now().plusDays(3).toString());
        body.put("startTime", "18:00");
        body.put("endTime", "20:00");
        body.put("requiredSkill", "TB_YEU");
        body.put("maxPlayers", 3);
        body.put("currentPlayers", 1);
        body.put("feePerPlayer", 50000);
        return body(mvc.perform(postAs(tokenOf(host), body, "/api/matches")).andExpect(status().isOk()).andReturn())
                .path("id").asLong();
    }

    private List<NotificationItem> chatNotifications(User u, long matchId) {
        return notificationRepository.findByUserIdOrderByIdDesc(u.getId()).stream()
                .filter(n -> "CHAT".equals(n.getType()) && Long.valueOf(matchId).equals(n.getReferenceId()))
                .toList();
    }

    private void say(User u, long matchId, String text) throws Exception {
        mvc.perform(postAs(tokenOf(u), Map.of("content", text), "/api/matches/{id}/messages", matchId))
                .andExpect(status().isOk());
    }

    private NotificationItem latestNotification(User u) {
        return notificationRepository.findByUserIdOrderByIdDesc(u.getId()).get(0);
    }

    @Test
    @DisplayName("Xin tham gia: chủ kèo nhận thông báo mở thẳng S30 của đúng kèo")
    void joinNotifiesHostWithDeepLink() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User joiner = newUser("CUSTOMER", 0);
        long matchId = createMatch(host);

        mvc.perform(postAs(tokenOf(joiner), Map.of(), "/api/matches/{id}/join", matchId)).andExpect(status().isOk());

        NotificationItem n = latestNotification(host);
        assertEquals("S30", n.getTargetScreen());
        assertEquals(matchId, n.getReferenceId());
    }

    @Test
    @DisplayName("Chi tiết kèo: chủ kèo thấy SĐT + số đơn chờ, người khác không thấy SĐT")
    void detailHidesPhoneFromOthers() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User joiner = newUser("CUSTOMER", 0);
        long matchId = createMatch(host);
        mvc.perform(postAs(tokenOf(joiner), Map.of(), "/api/matches/{id}/join", matchId)).andExpect(status().isOk());

        var asHost = body(mvc.perform(getAs(tokenOf(host), "/api/matches/{id}", matchId)).andExpect(status().isOk()).andReturn());
        assertTrue(asHost.path("isHost").asBoolean());
        assertEquals("HOST", asHost.path("myStatus").asText());
        assertEquals(1, asHost.path("pendingCount").asInt());
        assertTrue(asHost.path("participants").get(0).has("userPhone"));

        var asJoiner = body(mvc.perform(getAs(tokenOf(joiner), "/api/matches/{id}", matchId)).andExpect(status().isOk()).andReturn());
        assertEquals("PENDING", asJoiner.path("myStatus").asText());
        assertTrue(asJoiner.path("participants").get(0).has("userPhone"), "chính người xin thấy SĐT của mình");

        var asOther = body(mvc.perform(getAs(tokenOf(newUser("CUSTOMER", 0)), "/api/matches/{id}", matchId))
                .andExpect(status().isOk()).andReturn());
        assertFalse(asOther.path("participants").get(0).has("userPhone"));
        assertTrue(asOther.path("myStatus").isNull());

        mvc.perform(getAs(tokenOf(host), "/api/matches/{id}", 99_999_999)).andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("Kèo của tôi: tách kèo tổ chức và kèo đã xin tham gia")
    void myMatches() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User joiner = newUser("CUSTOMER", 0);
        long matchId = createMatch(host);
        mvc.perform(postAs(tokenOf(joiner), Map.of(), "/api/matches/{id}/join", matchId)).andExpect(status().isOk());

        var mineHost = body(mvc.perform(getAs(tokenOf(host), "/api/matches/mine")).andExpect(status().isOk()).andReturn());
        assertEquals(1, mineHost.path("hosting").size());
        assertEquals(matchId, mineHost.path("hosting").get(0).path("post").path("id").asLong());
        assertEquals(0, mineHost.path("joined").size());
        assertEquals(1, mineHost.path("pendingTotal").asInt());

        var mineJoiner = body(mvc.perform(getAs(tokenOf(joiner), "/api/matches/mine")).andExpect(status().isOk()).andReturn());
        assertEquals(0, mineJoiner.path("hosting").size());
        assertEquals("PENDING", mineJoiner.path("joined").get(0).path("myStatus").asText());

        mvc.perform(getAs(null, "/api/matches/mine")).andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Duyệt: chỉ chủ kèo, chỉ duyệt 1 lần; từ chối gửi kèm lý do")
    void reviewRules() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User a = newUser("CUSTOMER", 0);
        User b = newUser("CUSTOMER", 0);
        long matchId = createMatch(host);
        long pa = body(mvc.perform(postAs(tokenOf(a), Map.of(), "/api/matches/{id}/join", matchId))
                .andExpect(status().isOk()).andReturn()).path("id").asLong();
        long pb = body(mvc.perform(postAs(tokenOf(b), Map.of(), "/api/matches/{id}/join", matchId))
                .andExpect(status().isOk()).andReturn()).path("id").asLong();

        // Người khác không duyệt được
        mvc.perform(patchAs(tokenOf(b), Map.of("status", "APPROVED"), "/api/matches/{m}/participants/{p}", matchId, pa))
                .andExpect(status().isForbidden());

        var approved = body(mvc.perform(patchAs(tokenOf(host), Map.of("status", "APPROVED"),
                        "/api/matches/{m}/participants/{p}", matchId, pa))
                .andExpect(status().isOk()).andReturn());
        assertEquals(2, approved.path("post").path("currentPlayers").asInt());
        assertEquals(1, approved.path("entry").path("pendingCount").asInt());
        assertEquals("S30", latestNotification(a).getTargetScreen());

        mvc.perform(patchAs(tokenOf(host), Map.of("status", "REJECTED"), "/api/matches/{m}/participants/{p}", matchId, pa))
                .andExpect(status().isConflict());

        mvc.perform(patchAs(tokenOf(host), Map.of("status", "REJECTED", "reason", "Kèo cần trình độ khá hơn"),
                        "/api/matches/{m}/participants/{p}", matchId, pb))
                .andExpect(status().isOk());
        NotificationItem rejected = latestNotification(b);
        assertEquals("S15", rejected.getTargetScreen());
        assertTrue(rejected.getBody().contains("Kèo cần trình độ khá hơn"));

        var asB = body(mvc.perform(getAs(tokenOf(b), "/api/matches/{id}", matchId)).andExpect(status().isOk()).andReturn());
        assertEquals("REJECTED", asB.path("myStatus").asText());
    }

    private long join(User u, long matchId) throws Exception {
        return body(mvc.perform(postAs(tokenOf(u), Map.of(), "/api/matches/{id}/join", matchId))
                .andExpect(status().isOk()).andReturn()).path("id").asLong();
    }

    private void approve(User host, long matchId, long participantId) throws Exception {
        mvc.perform(patchAs(tokenOf(host), Map.of("status", "APPROVED"),
                "/api/matches/{m}/participants/{p}", matchId, participantId)).andExpect(status().isOk());
    }

    @Test
    @DisplayName("Hủy đơn chờ duyệt: xoá đơn, không báo chủ kèo, có thể xin lại")
    void cancelPendingRequest() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User a = newUser("CUSTOMER", 0);
        long matchId = createMatch(host);
        join(a, matchId);
        int hostNotisBefore = notificationRepository.findByUserIdOrderByIdDesc(host.getId()).size();

        var res = body(mvc.perform(postAs(tokenOf(a), Map.of(), "/api/matches/{id}/leave", matchId))
                .andExpect(status().isOk()).andReturn());
        assertEquals("PENDING", res.path("left").asText());
        assertTrue(res.path("entry").path("myStatus").isNull());
        assertEquals(hostNotisBefore, notificationRepository.findByUserIdOrderByIdDesc(host.getId()).size());

        join(a, matchId); // xin lại được
        mvc.perform(postAs(null, Map.of(), "/api/matches/{id}/leave", matchId)).andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Thành viên đã duyệt tự rời kèo: trả lại chỗ, kèo FULL mở lại, chủ kèo nhận thông báo S30")
    void approvedMemberLeavesSelf() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User a = newUser("CUSTOMER", 0);
        User b = newUser("CUSTOMER", 0);
        long matchId = createMatch(host); // tối đa 3, đang có 1
        approve(host, matchId, join(a, matchId));
        approve(host, matchId, join(b, matchId));

        var res = body(mvc.perform(postAs(tokenOf(a), Map.of(), "/api/matches/{id}/leave", matchId))
                .andExpect(status().isOk()).andReturn());
        assertEquals("APPROVED", res.path("left").asText());
        assertEquals(2, res.path("entry").path("post").path("currentPlayers").asInt());
        assertEquals("OPEN", res.path("entry").path("post").path("status").asText());

        NotificationItem n = latestNotification(host);
        assertEquals("Thành viên đã rời kèo", n.getTitle());
        assertEquals("S30", n.getTargetScreen());
        assertEquals(matchId, n.getReferenceId());
    }

    @Test
    @DisplayName("Mời ra: chỉ chủ kèo, chỉ thành viên đã duyệt; người bị mời ra không xin lại được")
    void hostRemovesMember() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User a = newUser("CUSTOMER", 0);
        User b = newUser("CUSTOMER", 0);
        long matchId = createMatch(host);
        long pa = join(a, matchId);
        long pb = join(b, matchId);
        approve(host, matchId, pa);

        mvc.perform(postAs(tokenOf(b), Map.of(), "/api/matches/{m}/participants/{p}/remove", matchId, pa))
                .andExpect(status().isForbidden());
        mvc.perform(postAs(tokenOf(host), Map.of(), "/api/matches/{m}/participants/{p}/remove", matchId, pb))
                .andExpect(status().isConflict()); // b mới chờ duyệt

        var res = body(mvc.perform(postAs(tokenOf(host), Map.of("reason", "Đổi đội hình"),
                        "/api/matches/{m}/participants/{p}/remove", matchId, pa))
                .andExpect(status().isOk()).andReturn());
        assertEquals(1, res.path("post").path("currentPlayers").asInt());
        assertEquals("REMOVED", res.path("participant").path("status").asText());

        NotificationItem n = latestNotification(a);
        assertEquals("S15", n.getTargetScreen());
        assertTrue(n.getBody().contains("Đổi đội hình"));

        var asA = body(mvc.perform(getAs(tokenOf(a), "/api/matches/{id}", matchId)).andReturn());
        assertEquals("REMOVED", asA.path("myStatus").asText());
        mvc.perform(postAs(tokenOf(a), Map.of(), "/api/matches/{id}/join", matchId)).andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("Nhắc lịch: 2 giờ trước giờ đánh, gửi chủ kèo + thành viên đã duyệt, chỉ một lần")
    void reminderBeforeStart() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User a = newUser("CUSTOMER", 0);
        User pending = newUser("CUSTOMER", 0);
        long matchId = createMatch(host); // 18:00, 3 ngày nữa
        approve(host, matchId, join(a, matchId));
        join(pending, matchId);

        LocalDateTime start = LocalDate.now().plusDays(3).atTime(LocalTime.of(18, 0));
        reminderScheduler.sendDueReminders(start.minusHours(3)); // còn quá sớm
        assertNotEquals("Sắp tới giờ đánh kèo giao lưu", latestNotification(a).getTitle());

        reminderScheduler.sendDueReminders(start.minusMinutes(90));
        for (User u : new User[]{host, a}) {
            NotificationItem n = latestNotification(u);
            assertEquals("Sắp tới giờ đánh kèo giao lưu", n.getTitle());
            assertEquals("S30", n.getTargetScreen());
            assertEquals(matchId, n.getReferenceId());
        }
        assertTrue(notificationRepository.findByUserIdOrderByIdDesc(pending.getId()).stream()
                        .noneMatch(n -> "Sắp tới giờ đánh kèo giao lưu".equals(n.getTitle())),
                "người còn chờ duyệt không nhận nhắc lịch");

        int before = notificationRepository.findByUserIdOrderByIdDesc(a.getId()).size();
        reminderScheduler.sendDueReminders(start.minusMinutes(30)); // không nhắc lần 2
        assertEquals(before, notificationRepository.findByUserIdOrderByIdDesc(a.getId()).size());
    }

    private boolean feedHas(long matchId) throws Exception {
        var feed = body(mvc.perform(getAs(null, "/api/matches")).andExpect(status().isOk()).andReturn());
        for (var e : feed) if (e.path("post").path("id").asLong() == matchId) return true;
        return false;
    }

    @Test
    @DisplayName("Tự đóng kèo: qua giờ kết thúc -> COMPLETED, biến khỏi bảng tin, không xin vào được")
    void finishedMatchIsClosed() throws Exception {
        User host = newUser("CUSTOMER", 0);
        long matchId = createMatch(host); // 3 ngày nữa, 18:00-20:00
        assertTrue(feedHas(matchId));

        LocalDateTime end = LocalDate.now().plusDays(3).atTime(LocalTime.of(20, 0));
        reminderScheduler.closeFinished(end.minusMinutes(1));
        assertTrue(feedHas(matchId), "chưa hết giờ thì chưa đóng");

        reminderScheduler.closeFinished(end.plusMinutes(1));
        assertFalse(feedHas(matchId));
        var detail = body(mvc.perform(getAs(tokenOf(host), "/api/matches/{id}", matchId)).andReturn());
        assertEquals("COMPLETED", detail.path("post").path("status").asText());
        mvc.perform(postAs(tokenOf(newUser("CUSTOMER", 0)), Map.of(), "/api/matches/{id}/join", matchId))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("Hủy kèo: chỉ chủ kèo; người đã xin / đã vào nhận thông báo kèm lý do; không hủy 2 lần")
    void hostCancelsMatch() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User a = newUser("CUSTOMER", 0);
        User b = newUser("CUSTOMER", 0);
        long matchId = createMatch(host);
        approve(host, matchId, join(a, matchId));
        join(b, matchId);

        mvc.perform(postAs(tokenOf(a), Map.of(), "/api/matches/{id}/cancel", matchId)).andExpect(status().isForbidden());

        var res = body(mvc.perform(postAs(tokenOf(host), Map.of("reason", "Sân bảo trì"), "/api/matches/{id}/cancel", matchId))
                .andExpect(status().isOk()).andReturn());
        assertEquals("CANCELLED", res.path("post").path("status").asText());
        for (User u : new User[]{a, b}) {
            NotificationItem n = latestNotification(u);
            assertEquals("Kèo giao lưu đã bị hủy", n.getTitle());
            assertEquals("S30", n.getTargetScreen());
            assertTrue(n.getBody().contains("Sân bảo trì"));
        }
        assertFalse(feedHas(matchId));
        mvc.perform(postAs(tokenOf(host), Map.of(), "/api/matches/{id}/cancel", matchId)).andExpect(status().isConflict());
        mvc.perform(postAs(tokenOf(a), Map.of(), "/api/matches/{id}/leave", matchId)).andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("Nhóm chat: chủ kèo + thành viên đã duyệt nhắn được, người chờ duyệt / người ngoài bị chặn")
    void groupChat() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User a = newUser("CUSTOMER", 0);
        User pending = newUser("CUSTOMER", 0);
        long matchId = createMatch(host);
        approve(host, matchId, join(a, matchId));
        join(pending, matchId);

        long first = body(mvc.perform(postAs(tokenOf(host), Map.of("content", "Mọi người nhớ mang cầu nhé"),
                        "/api/matches/{id}/messages", matchId))
                .andExpect(status().isOk()).andReturn()).path("id").asLong();
        mvc.perform(postAs(tokenOf(a), Map.of("content", "Ok anh"), "/api/matches/{id}/messages", matchId))
                .andExpect(status().isOk());
        mvc.perform(postAs(tokenOf(a), Map.of("content", "   "), "/api/matches/{id}/messages", matchId))
                .andExpect(status().isBadRequest());

        var all = body(mvc.perform(getAs(tokenOf(a), "/api/matches/{id}/messages", matchId)).andExpect(status().isOk()).andReturn());
        assertEquals(2, all.path("items").size());
        assertFalse(all.path("items").get(0).path("mine").asBoolean());
        assertTrue(all.path("items").get(1).path("mine").asBoolean());

        var newer = body(mvc.perform(getAs(tokenOf(host), "/api/matches/{id}/messages?afterId=" + first, matchId))
                .andExpect(status().isOk()).andReturn());
        assertEquals(1, newer.path("items").size());
        assertEquals("Ok anh", newer.path("items").get(0).path("content").asText());

        var asHost = body(mvc.perform(getAs(tokenOf(host), "/api/matches/{id}", matchId)).andReturn());
        assertTrue(asHost.path("canChat").asBoolean());
        assertEquals(2, asHost.path("messageCount").asInt());

        mvc.perform(getAs(tokenOf(pending), "/api/matches/{id}/messages", matchId)).andExpect(status().isForbidden());
        mvc.perform(postAs(tokenOf(newUser("CUSTOMER", 0)), Map.of("content", "hi"), "/api/matches/{id}/messages", matchId))
                .andExpect(status().isForbidden());
        mvc.perform(getAs(null, "/api/matches/{id}/messages", matchId)).andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("Tin nhắn mới: gộp 1 thông báo chưa đọc / kèo, không báo người gửi / người chờ duyệt")
    void chatNotificationsCollapse() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User a = newUser("CUSTOMER", 0);
        User pending = newUser("CUSTOMER", 0);
        long matchId = createMatch(host);
        approve(host, matchId, join(a, matchId));
        join(pending, matchId);

        say(host, matchId, "Mọi người nhớ mang cầu");
        say(host, matchId, "Tối nay 18h nhé");
        say(host, matchId, "Ai đến muộn báo trước");

        List<NotificationItem> forA = chatNotifications(a, matchId);
        assertEquals(1, forA.size(), "chỉ 1 thông báo chat cho mỗi kèo");
        assertFalse(forA.get(0).isRead());
        assertTrue(forA.get(0).getTitle().startsWith("3 tin nhắn mới"));
        assertTrue(forA.get(0).getBody().contains("Ai đến muộn"));
        assertEquals("S30", forA.get(0).getTargetScreen());
        assertTrue(chatNotifications(host, matchId).isEmpty(), "người gửi không nhận");
        assertTrue(chatNotifications(pending, matchId).isEmpty(), "người chờ duyệt không nhận");

        var asA = body(mvc.perform(getAs(tokenOf(a), "/api/matches/{id}", matchId)).andReturn());
        assertEquals(3, asA.path("unreadMessages").asInt());
    }

    @Test
    @DisplayName("Mở chat = đã đọc; đang mở chat thì không báo; tắt thông báo nhóm thì không báo")
    void chatReadActiveAndMute() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User a = newUser("CUSTOMER", 0);
        long matchId = createMatch(host);
        approve(host, matchId, join(a, matchId));

        say(host, matchId, "Tin 1");
        var opened = body(mvc.perform(getAs(tokenOf(a), "/api/matches/{id}/messages", matchId))
                .andExpect(status().isOk()).andReturn());
        assertEquals(0, opened.path("lastReadBefore").asLong());
        assertTrue(chatNotifications(a, matchId).stream().allMatch(NotificationItem::isRead), "mở chat thì thông báo đã đọc");
        var asA = body(mvc.perform(getAs(tokenOf(a), "/api/matches/{id}", matchId)).andReturn());
        assertEquals(0, asA.path("unreadMessages").asInt());

        // a vừa mở chat (trong 15 giây) -> tin mới không tạo thông báo
        say(host, matchId, "Tin 2");
        assertTrue(chatNotifications(a, matchId).stream().allMatch(NotificationItem::isRead));

        // host tắt thông báo nhóm -> a nhắn, host không nhận
        mvc.perform(patchAs(tokenOf(host), Map.of("muted", true), "/api/matches/{id}/chat-settings", matchId))
                .andExpect(status().isOk());
        say(a, matchId, "Ok anh");
        assertTrue(chatNotifications(host, matchId).isEmpty());
        var asHost = body(mvc.perform(getAs(tokenOf(host), "/api/matches/{id}", matchId)).andReturn());
        assertTrue(asHost.path("chatMuted").asBoolean());
        assertEquals(1, asHost.path("unreadMessages").asInt(), "vẫn đếm tin chưa đọc dù tắt thông báo");

        var count = body(mvc.perform(getAs(tokenOf(a), "/api/notifications/user/{id}/unread-count", a.getId()))
                .andExpect(status().isOk()).andReturn());
        assertTrue(count.has("latestId"));
    }
}
