package com.badminton.v2;

import com.badminton.v2.entity.NotificationItem;
import com.badminton.v2.entity.User;
import com.badminton.v2.repository.MatchPostRepository;
import com.badminton.v2.repository.NotificationRepository;
import com.badminton.v2.service.MatchReminderScheduler;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Uy tín chủ kèo: ai được đánh giá, sửa đánh giá, hạn 7 ngày, công thức điểm, huy hiệu, tỉ lệ hủy kèo. */
class HostReputationTest extends IntegrationTestBase {

    private static final DateTimeFormatter HM = DateTimeFormatter.ofPattern("HH:mm");

    @Autowired private MatchReminderScheduler scheduler;
    @Autowired private NotificationRepository notificationRepository;
    @Autowired private MatchPostRepository matchPostRepository;

    /** Kèo bắt đầu lúc [start], đánh 2 giờ. */
    private long createMatch(User host, LocalDateTime start, int maxPlayers) throws Exception {
        start = start.truncatedTo(ChronoUnit.MINUTES);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("venueId", ownerApprovedVenue().getId());
        body.put("title", "Kèo test uy tín");
        body.put("playDate", start.toLocalDate().toString());
        body.put("startTime", start.format(HM));
        body.put("endTime", start.plusHours(2).format(HM));
        body.put("requiredSkill", "TB_YEU");
        body.put("maxPlayers", maxPlayers);
        body.put("currentPlayers", 1);
        body.put("feePerPlayer", 50_000);
        return body(mvc.perform(postAs(tokenOf(host), body, "/api/matches")).andExpect(status().isOk()).andReturn())
                .path("id").asLong();
    }

    private long join(User u, long matchId) throws Exception {
        return body(mvc.perform(postAs(tokenOf(u), Map.of(), "/api/matches/{id}/join", matchId))
                .andExpect(status().isOk()).andReturn()).path("id").asLong();
    }

    private void approve(User host, long matchId, long pid) throws Exception {
        mvc.perform(patchAs(tokenOf(host), Map.of("status", "APPROVED"), "/api/matches/{m}/participants/{p}", matchId, pid))
                .andExpect(status().isOk());
    }

    /** Kèo 2 ngày nữa với [members] thành viên đã duyệt, rồi cho kèo kết thúc. */
    private long completedMatch(User host, List<User> members) throws Exception {
        LocalDateTime start = LocalDateTime.now().plusHours(48);
        long id = createMatch(host, start, members.size() + 2);
        for (User m : members) approve(host, id, join(m, id));
        scheduler.closeFinished(start.plusHours(2).plusMinutes(5));
        return id;
    }

    private Map<String, Object> review(int rating, String accuracy, String... tags) {
        Map<String, Object> b = new LinkedHashMap<>();
        b.put("rating", rating);
        b.put("skillAccuracy", accuracy);
        b.put("tags", List.of(tags));
        b.put("comment", "Kèo vui");
        return b;
    }

    private List<User> users(int n) {
        List<User> list = new ArrayList<>();
        for (int i = 0; i < n; i++) list.add(newUser("CUSTOMER", 0));
        return list;
    }

    @Test
    @DisplayName("Chỉ thành viên đã duyệt của kèo đã kết thúc mới đánh giá được; sửa được, không nhân đôi")
    void whoCanReview() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User member = newUser("CUSTOMER", 0);
        User pending = newUser("CUSTOMER", 0);
        LocalDateTime start = LocalDateTime.now().plusHours(48);
        long id = createMatch(host, start, 5);
        approve(host, id, join(member, id));
        join(pending, id);

        // Chưa kết thúc
        mvc.perform(postAs(tokenOf(member), review(5, "ACCURATE"), "/api/matches/{id}/host-review", id))
                .andExpect(status().isBadRequest());

        scheduler.closeFinished(start.plusHours(2).plusMinutes(5));

        NotificationItem invite = notificationRepository.findByUserIdOrderByIdDesc(member.getId()).get(0);
        assertTrue(invite.getTitle().startsWith("Đánh giá chủ kèo"));
        assertEquals("S30", invite.getTargetScreen());
        assertEquals(id, invite.getReferenceId());

        var before = body(mvc.perform(getAs(tokenOf(member), "/api/matches/{id}", id)).andReturn());
        assertTrue(before.path("canReviewHost").asBoolean());

        mvc.perform(postAs(tokenOf(pending), review(5, "ACCURATE"), "/api/matches/{id}/host-review", id))
                .andExpect(status().isForbidden());
        mvc.perform(postAs(tokenOf(host), review(5, "ACCURATE"), "/api/matches/{id}/host-review", id))
                .andExpect(status().isForbidden());
        mvc.perform(postAs(tokenOf(member), review(6, "ACCURATE"), "/api/matches/{id}/host-review", id))
                .andExpect(status().isBadRequest());
        mvc.perform(postAs(tokenOf(member), review(5, "MAYBE"), "/api/matches/{id}/host-review", id))
                .andExpect(status().isBadRequest());

        var first = body(mvc.perform(postAs(tokenOf(member), review(4, "HIGHER", "Đúng giờ", "Không có trong danh sách"),
                        "/api/matches/{id}/host-review", id))
                .andExpect(status().isOk()).andReturn());
        assertEquals(1, first.path("review").path("tags").size(), "nhãn lạ bị bỏ");
        assertEquals(first.path("review").path("raterName").asText(), userRepository.findById(member.getId()).orElseThrow().getFullName());

        var edited = body(mvc.perform(postAs(tokenOf(member), review(5, "ACCURATE"), "/api/matches/{id}/host-review", id))
                .andExpect(status().isOk()).andReturn());
        assertEquals(first.path("review").path("id").asLong(), edited.path("review").path("id").asLong());
        assertEquals(5, edited.path("entry").path("myHostReview").path("rating").asInt());

        var profile = body(mvc.perform(getAs(tokenOf(pending), "/api/matches/hosts/{id}/profile", host.getId()))
                .andExpect(status().isOk()).andReturn());
        assertEquals(1, profile.path("summary").path("count").asInt());
        assertEquals(1, profile.path("reviews").size());
        assertEquals(1, profile.path("summary").path("completed").asInt());
    }

    @Test
    @DisplayName("Quá 7 ngày sau khi kèo kết thúc thì không đánh giá được")
    void reviewWindow() throws Exception {
        User host = newUser("CUSTOMER", 0);
        User member = newUser("CUSTOMER", 0);
        LocalDateTime start = LocalDateTime.now().plusHours(48);
        long id = createMatch(host, start, 4);
        approve(host, id, join(member, id));

        // Dời kèo về 10 ngày trước rồi đóng
        var post = matchPostRepository.findById(id).orElseThrow();
        post.setPlayDate(LocalDateTime.now().minusDays(10).toLocalDate().toString());
        matchPostRepository.save(post);
        scheduler.closeFinished(LocalDateTime.now());

        mvc.perform(postAs(tokenOf(member), review(5, "ACCURATE"), "/api/matches/{id}/host-review", id))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("Điểm làm mượt + huy hiệu: 5 đánh giá tốt = Chủ kèo uy tín; đa số lệch trình độ = cảnh báo")
    void scoreAndBadges() throws Exception {
        // Chủ kèo tốt: 5,5,5,5,4 và đều đúng trình độ -> (3*4 + 24) / 8 = 4.5
        User good = newUser("CUSTOMER", 0);
        List<User> m1 = users(5);
        long g = completedMatch(good, m1);
        int[] stars = {5, 5, 5, 5, 4};
        for (int i = 0; i < 5; i++) {
            mvc.perform(postAs(tokenOf(m1.get(i)), review(stars[i], "ACCURATE"), "/api/matches/{id}/host-review", g))
                    .andExpect(status().isOk());
        }
        var gp = body(mvc.perform(getAs(tokenOf(good), "/api/matches/hosts/{id}/profile", good.getId())).andReturn()).path("summary");
        assertEquals(5, gp.path("count").asInt());
        assertEquals(4.5, gp.path("score").asDouble(), 1e-9);
        assertEquals(1.0, gp.path("skillAccuracy").asDouble(), 1e-9);
        assertEquals("TRUSTED", gp.path("badge").asText());

        // Thẻ kèo trên bảng tin / chi tiết cũng mang tóm tắt uy tín
        var entry = body(mvc.perform(getAs(tokenOf(m1.get(0)), "/api/matches/{id}", g)).andReturn());
        assertEquals("TRUSTED", entry.path("host").path("badge").asText());

        // Chủ kèo hay mô tả thấp hơn thực tế: 3/5 "cao hơn"
        User off = newUser("CUSTOMER", 0);
        List<User> m2 = users(5);
        long o = completedMatch(off, m2);
        String[] acc = {"HIGHER", "HIGHER", "HIGHER", "ACCURATE", "ACCURATE"};
        for (int i = 0; i < 5; i++) {
            mvc.perform(postAs(tokenOf(m2.get(i)), review(4, acc[i]), "/api/matches/{id}/host-review", o))
                    .andExpect(status().isOk());
        }
        var op = body(mvc.perform(getAs(tokenOf(off), "/api/matches/hosts/{id}/profile", off.getId())).andReturn()).path("summary");
        assertEquals(0.4, op.path("skillAccuracy").asDouble(), 1e-9);
        assertEquals("HIGHER", op.path("skillBias").asText());
        assertEquals("SKILL_MISMATCH", op.path("badge").asText());
    }

    @Test
    @DisplayName("Tỉ lệ hủy kèo: chỉ tính kèo đã có người xin; hủy nhiều thì mất huy hiệu")
    void cancelRate() throws Exception {
        User host = newUser("CUSTOMER", 0);
        List<User> members = users(5);
        long done = completedMatch(host, members);
        for (User m : members) {
            mvc.perform(postAs(tokenOf(m), review(5, "ACCURATE"), "/api/matches/{id}/host-review", done))
                    .andExpect(status().isOk());
        }
        // Kèo không ai xin bị hủy: không tính
        long empty = createMatch(host, LocalDateTime.now().plusHours(72), 4);
        mvc.perform(postAs(tokenOf(host), Map.of(), "/api/matches/{id}/cancel", empty)).andExpect(status().isOk());
        var s1 = body(mvc.perform(getAs(tokenOf(host), "/api/matches/hosts/{id}/profile", host.getId())).andReturn()).path("summary");
        assertEquals(0.0, s1.path("cancelRate").asDouble(), 1e-9);
        assertEquals("TRUSTED", s1.path("badge").asText());

        // Kèo đã có người xin bị hủy: 1 hủy / (1 xong + 1 hủy) = 50%
        long withReq = createMatch(host, LocalDateTime.now().plusHours(72), 4);
        join(newUser("CUSTOMER", 0), withReq);
        mvc.perform(postAs(tokenOf(host), Map.of(), "/api/matches/{id}/cancel", withReq)).andExpect(status().isOk());
        var s2 = body(mvc.perform(getAs(tokenOf(host), "/api/matches/hosts/{id}/profile", host.getId())).andReturn()).path("summary");
        assertEquals(0.5, s2.path("cancelRate").asDouble(), 1e-9);
        assertTrue(s2.path("badge").isNull());
    }
}
