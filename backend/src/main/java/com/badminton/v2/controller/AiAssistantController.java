package com.badminton.v2.controller;

import com.badminton.v2.entity.AiChatSession;
import com.badminton.v2.entity.User;
import com.badminton.v2.repository.UserRepository;
import com.badminton.v2.security.AuthUser;
import com.badminton.v2.security.CurrentUser;
import com.badminton.v2.service.ai.AiAssistantService;
import com.badminton.v2.service.ai.AiTools;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;

/**
 * Trợ lý AI (S17) - chỉ dành cho người chơi (CUSTOMER).
 * POST /api/ai/chat            {sessionId?, message, lat?, lng?}
 * GET  /api/ai/sessions/current lịch sử phiên đang mở + hạn mức
 * POST /api/ai/sessions         bắt đầu cuộc trò chuyện mới
 */
@RestController
@RequestMapping("/api/ai")
public class AiAssistantController {

    private static final int HISTORY_LIMIT = 50;

    private final AiAssistantService aiService;
    private final UserRepository userRepository;

    public AiAssistantController(AiAssistantService aiService, UserRepository userRepository) {
        this.aiService = aiService;
        this.userRepository = userRepository;
    }

    @PostMapping("/chat")
    public ResponseEntity<?> chatWithAi(@RequestBody Map<String, Object> body) {
        User user = customer(body.get("userId"));
        if (user == null) return customerOnly();
        try {
            Map<String, Object> res = aiService.chat(
                    user,
                    longOrNull(body.get("sessionId")),
                    body.get("message") == null ? "" : String.valueOf(body.get("message")),
                    doubleOr(body.get("lat"), AiTools.DEFAULT_LAT),
                    doubleOr(body.get("lng"), AiTools.DEFAULT_LNG));
            return ResponseEntity.ok(res);
        } catch (IllegalArgumentException e) {
            // Câu hỏi trống / quá 300 ký tự
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (AiAssistantService.RateLimitException e) {
            Map<String, Object> err = new LinkedHashMap<>();
            err.put("error", e.getMessage());
            err.put("retryAfterSeconds", e.getRetryAfterSeconds());
            err.put("quota", aiService.quota(user.getId()));
            return ResponseEntity.status(429)
                    .header("Retry-After", String.valueOf(e.getRetryAfterSeconds()))
                    .body(err);
        }
    }

    @GetMapping("/sessions/current")
    public ResponseEntity<?> currentSession() {
        User user = customer(null);
        if (user == null) return customerOnly();
        AiChatSession session = aiService.currentSession(user.getId());
        return ResponseEntity.ok(sessionResponse(user, session));
    }

    @PostMapping("/sessions")
    public ResponseEntity<?> newSession() {
        User user = customer(null);
        if (user == null) return customerOnly();
        AiChatSession session = aiService.newSession(user.getId());
        return ResponseEntity.ok(sessionResponse(user, session));
    }

    private Map<String, Object> sessionResponse(User user, AiChatSession session) {
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("sessionId", session.getId());
        res.put("messages", aiService.messagesOf(session, HISTORY_LIMIT));
        res.put("quota", aiService.quota(user.getId()));
        return res;
    }

    /**
     * Người chơi đang đăng nhập. Gọi trực tiếp không qua HTTP (test) thì dùng [fallbackUserId] (mặc định 1).
     * Trả về null nếu không phải tài khoản CUSTOMER.
     */
    private User customer(Object fallbackUserId) {
        Optional<AuthUser> auth = CurrentUser.get();
        Long userId = auth.map(AuthUser::id)
                .orElseGet(() -> CurrentUser.idOr(fallbackUserId == null ? 1 : fallbackUserId));
        return userRepository.findById(userId)
                .filter(u -> "CUSTOMER".equals(u.getRole()))
                .orElse(null);
    }

    private static ResponseEntity<?> customerOnly() {
        return ResponseEntity.status(403).body(Map.of("error", "Trợ lý AI chỉ dành cho tài khoản người chơi."));
    }

    private static Long longOrNull(Object v) {
        if (v == null) return null;
        try {
            return Long.valueOf(String.valueOf(v));
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static double doubleOr(Object v, double fallback) {
        if (v == null) return fallback;
        try {
            return Double.parseDouble(String.valueOf(v));
        } catch (NumberFormatException e) {
            return fallback;
        }
    }
}
