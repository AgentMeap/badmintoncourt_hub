package com.badminton.v2;

import com.badminton.v2.entity.User;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Giới tính trong hồ sơ, hoàn thiện hồ sơ sau đăng ký, kèo giá nam / nữ khác nhau. */
class GenderFeeTest extends IntegrationTestBase {

    private User player(String gender, double balance) {
        User u = newUser("CUSTOMER", balance);
        u.setGender(gender);
        return userRepository.save(u);
    }

    private long createSplitMatch(User host, int depositPercent) throws Exception {
        LocalDateTime start = LocalDateTime.now().plusDays(2).truncatedTo(ChronoUnit.HOURS);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("venueId", ownerApprovedVenue().getId());
        body.put("title", "Kèo giá nam nữ");
        body.put("playDate", start.toLocalDate().toString());
        body.put("startTime", start.format(DateTimeFormatter.ofPattern("HH:mm")));
        body.put("endTime", start.plusHours(2).format(DateTimeFormatter.ofPattern("HH:mm")));
        body.put("maxPlayers", 6);
        body.put("currentPlayers", 1);
        body.put("feeMale", 70000);
        body.put("feeFemale", 55000);
        body.put("depositPercent", depositPercent);
        var post = body(mvc.perform(postAs(tokenOf(host), body, "/api/matches")).andExpect(status().isOk()).andReturn());
        assertEquals(70000, post.path("feePerPlayer").asDouble(), 0.01);
        assertEquals(55000, post.path("feeFemale").asDouble(), 0.01);
        return post.path("id").asLong();
    }

    private double balance(User u) {
        return userRepository.findById(u.getId()).orElseThrow().getWalletBalance();
    }

    @Test
    @DisplayName("Kèo nam 70k / nữ 55k cọc 100%: nam bị trừ 70k, nữ 55k; chưa có giới tính thì phải cập nhật")
    void depositByGender() throws Exception {
        User host = player("MALE", 0);
        long matchId = createSplitMatch(host, 100);

        User male = player("MALE", 500_000);
        User female = player("FEMALE", 500_000);
        User unknown = player(null, 500_000);

        var forFemale = body(mvc.perform(getAs(tokenOf(female), "/api/matches/{id}", matchId))
                .andExpect(status().isOk()).andReturn());
        assertEquals(55000, forFemale.path("myFee").asDouble(), 0.01);
        assertEquals(55000, forFemale.path("myDeposit").asDouble(), 0.01);

        mvc.perform(postAs(tokenOf(male), Map.of(), "/api/matches/{id}/join", matchId)).andExpect(status().isOk());
        mvc.perform(postAs(tokenOf(female), Map.of(), "/api/matches/{id}/join", matchId)).andExpect(status().isOk());
        assertEquals(430_000, balance(male), 0.01);
        assertEquals(445_000, balance(female), 0.01);

        mvc.perform(postAs(tokenOf(unknown), Map.of(), "/api/matches/{id}/join", matchId)).andExpect(status().isBadRequest());
        assertEquals(500_000, balance(unknown), 0.01);
    }

    @Test
    @DisplayName("Hồ sơ: cập nhật giới tính hợp lệ thì hoàn thiện hồ sơ, giá trị lạ bị từ chối")
    void profileGender() throws Exception {
        User u = newUser("CUSTOMER", 0);
        u.setProfileCompleted(false);
        userRepository.save(u);

        var me = body(mvc.perform(getAs(tokenOf(u), "/api/auth/profile/{id}", u.getId())).andExpect(status().isOk()).andReturn());
        assertFalse(me.path("profileCompleted").asBoolean());

        mvc.perform(patchAs(tokenOf(u), Map.of("gender", "abc"), "/api/auth/profile/{id}", u.getId()))
                .andExpect(status().isBadRequest());
        var updated = body(mvc.perform(patchAs(tokenOf(u), Map.of("gender", "FEMALE", "skillLevel", "KHA"),
                "/api/auth/profile/{id}", u.getId())).andExpect(status().isOk()).andReturn());
        assertEquals("FEMALE", updated.path("gender").asText());
        assertTrue(updated.path("profileCompleted").asBoolean());
    }
}
