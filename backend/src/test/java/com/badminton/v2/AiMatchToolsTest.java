package com.badminton.v2;

import com.badminton.v2.entity.User;
import com.badminton.v2.service.ai.AiTools;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Trợ lý AI theo kịp tính năng kèo: kèo của tôi, chính sách cọc, lọc kèo không cọc / chủ kèo uy tín. */
class AiMatchToolsTest extends IntegrationTestBase {

    @Autowired private AiTools tools;

    private long createMatch(User host, int depositPercent) throws Exception {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("venueId", ownerApprovedVenue().getId());
        body.put("title", "Kèo AI test cọc " + depositPercent);
        body.put("playDate", LocalDate.now().plusDays(2).toString());
        body.put("startTime", "18:00");
        body.put("endTime", "20:00");
        body.put("requiredSkill", "TB_YEU");
        body.put("maxPlayers", 6);
        body.put("currentPlayers", 1);
        body.put("feePerPlayer", 40_000);
        body.put("depositPercent", depositPercent);
        return body(mvc.perform(postAs(tokenOf(host), body, "/api/matches")).andExpect(status().isOk()).andReturn())
                .path("id").asLong();
    }

    private com.fasterxml.jackson.databind.JsonNode ask(User u, String message) throws Exception {
        return body(mvc.perform(postAs(tokenOf(u), Map.of("message", message), "/api/ai/chat"))
                .andExpect(status().isOk()).andReturn());
    }

    @Test
    @DisplayName("\"Kèo của tôi có ai xin chưa?\" -> thẻ kèo tôi tổ chức kèm số đơn chờ duyệt")
    void myMatchesViaChat() throws Exception {
        User host = newUser("CUSTOMER", 0);
        long id = createMatch(host, 0);
        mvc.perform(postAs(tokenOf(newUser("CUSTOMER", 0)), Map.of(), "/api/matches/{id}/join", id))
                .andExpect(status().isOk());

        var res = ask(host, "Kèo của tôi có ai xin chưa?");
        assertEquals(1, res.path("cards").size());
        var match = res.path("cards").get(0).path("match");
        assertEquals("MATCH", res.path("cards").get(0).path("type").asText());
        assertEquals(id, match.path("id").asLong());
        assertEquals("HOST", match.path("role").asText());
        assertEquals(1, match.path("pendingCount").asInt());
    }

    @Test
    @DisplayName("Hỏi rời kèo có mất cọc không -> thẻ chính sách cọc kèo")
    void depositPolicyViaChat() throws Exception {
        var res = ask(newUser("CUSTOMER", 0), "Rời kèo sát giờ có mất cọc không?");
        var card = res.path("cards").get(0);
        assertEquals("POLICY", card.path("type").asText());
        assertEquals("Chính sách cọc kèo giao lưu", card.path("title").asText());
        assertTrue(card.path("lines").toString().contains("24 tiếng"));
    }

    @Test
    @DisplayName("Tìm kèo: có cọc + uy tín chủ kèo trong thẻ; lọc không cọc; bỏ kèo đã xin")
    void findMatchesFilters() throws Exception {
        User host = newUser("CUSTOMER", 0);
        long withDeposit = createMatch(host, 100);
        long free = createMatch(host, 0);
        User me = newUser("CUSTOMER", 100_000);
        AiTools.Context ctx = new AiTools.Context(me.getId(), "TB_YEU", AiTools.DEFAULT_LAT, AiTools.DEFAULT_LNG);

        // Không cọc: mọi thẻ đều có depositAmount = 0
        var noDeposit = tools.findMatches(null, null, false, 0.0, ctx);
        for (var card : noDeposit.cards()) {
            @SuppressWarnings("unchecked")
            Map<String, Object> m = (Map<String, Object>) card.get("match");
            assertEquals(0.0, ((Number) m.get("depositAmount")).doubleValue(), 1e-9);
            assertNotEquals(withDeposit, ((Number) m.get("id")).longValue());
            assertTrue(m.containsKey("host"), "thẻ kèo phải có uy tín chủ kèo");
        }

        // Đã xin vào kèo free -> không còn gợi ý kèo đó
        mvc.perform(postAs(tokenOf(me), Map.of(), "/api/matches/{id}/join", free)).andExpect(status().isOk());
        var after = tools.findMatches(null, null, false, null, ctx);
        List<Long> ids = after.cards().stream()
                .map(c -> ((Number) ((Map<?, ?>) c.get("match")).get("id")).longValue()).toList();
        assertFalse(ids.contains(free));

        // Chỉ chủ kèo uy tín: chủ kèo mới (chưa có đánh giá) bị loại
        var trusted = tools.findMatches(null, null, true, null, ctx);
        for (var card : trusted.cards()) {
            @SuppressWarnings("unchecked")
            Map<String, Object> h = (Map<String, Object>) ((Map<String, Object>) card.get("match")).get("host");
            assertEquals("TRUSTED", h.get("badge"));
        }

        // Kèo đã xin hiện trong "kèo của tôi" với trạng thái đơn
        var mine = tools.myMatches(ctx);
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> joined = (List<Map<String, Object>>) mine.data().get("joined");
        assertEquals("PENDING", joined.get(0).get("myStatus"));
    }
}
