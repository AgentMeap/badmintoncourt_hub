package com.badminton.v2.controller;

import com.badminton.v2.entity.MatchPost;
import com.badminton.v2.entity.Venue;
import com.badminton.v2.repository.MatchPostRepository;
import com.badminton.v2.repository.VenueRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestClient;

import java.util.*;

@RestController
@RequestMapping("/api/ai")
public class AiAssistantController {

    private static final Logger log = LoggerFactory.getLogger(AiAssistantController.class);

    private final VenueRepository venueRepository;
    private final MatchPostRepository matchPostRepository;
    private final RestClient restClient;

    @Value("${app.gemini.api-key:}")
    private String geminiApiKey;

    @Value("${app.gemini.model:gemini-2.5-flash}")
    private String geminiModel;

    public AiAssistantController(VenueRepository venueRepository,
                                 MatchPostRepository matchPostRepository,
                                 RestClient restClient) {
        this.venueRepository = venueRepository;
        this.matchPostRepository = matchPostRepository;
        this.restClient = restClient;
    }

    @PostMapping("/chat")
    public ResponseEntity<?> chatWithAi(@RequestBody Map<String, String> body) {
        String prompt = body.getOrDefault("message", "").trim();
        List<Venue> approvedVenues = venueRepository.findByStatusOrderByIdDesc("APPROVED");
        List<MatchPost> openMatches = matchPostRepository.findAllByOrderByIdDesc()
                .stream()
                .filter(m -> "OPEN".equals(m.getStatus()))
                .toList();

        // Build database context for RAG
        StringBuilder contextBuilder = new StringBuilder();
        contextBuilder.append("Bạn là Trợ lý AI Cầu Lông của ứng dụng Badminton Hub. Dưới đây là dữ liệu thời gian thực từ SQLite Database:\n");
        contextBuilder.append("1. Danh sách sân cầu lông đang hoạt động:\n");
        for (Venue v : approvedVenues) {
            contextBuilder.append("- ID ").append(v.getId()).append(": ").append(v.getName())
                    .append(" (Địa chỉ: ").append(v.getAddress())
                    .append(", Giá: ").append((long) v.getBasePricePerHour()).append("đ - ").append((long) v.getPeakPricePerHour()).append("đ/h, ")
                    .append(v.getTotalCourts()).append(" sân)\n");
        }
        contextBuilder.append("2. Danh sách Kèo giao lưu đang tuyển người:\n");
        for (MatchPost m : openMatches) {
            contextBuilder.append("- Kèo ID ").append(m.getId()).append(": ").append(m.getTitle())
                    .append(" tại ").append(m.getVenueName()).append(" (").append(m.getStartTime()).append("-").append(m.getEndTime())
                    .append(", Trình độ: ").append(m.getRequiredSkill())
                    .append(", Còn trống: ").append(m.getMaxPlayers() - m.getCurrentPlayers()).append(" slot, Phí: ")
                    .append((long) m.getFeePerPlayer()).append("đ/người)\n");
        }
        contextBuilder.append("3. Chính sách Hủy sân & Hoàn tiền (Luồng 4): Hủy trước >= 24h hoàn 100% về Ví nội bộ; trước 6h-24h hoàn 50%; dưới 6h không hoàn tiền. Mỗi vé được đổi lịch (Reschedule) miễn phí 1 lần.\n");
        contextBuilder.append("\nCâu hỏi của người dùng: ").append(prompt).append("\nHãy trả lời ngắn gọn, thân thiện bằng tiếng Việt.");

        String aiReply = null;
        if (geminiApiKey != null && !geminiApiKey.isBlank()) {
            try {
                String url = "https://generativelanguage.googleapis.com/v1beta/models/" + geminiModel + ":generateContent?key=" + geminiApiKey;
                Map<String, Object> req = Map.of(
                        "contents", List.of(
                                Map.of("parts", List.of(Map.of("text", contextBuilder.toString())))
                        )
                );
                @SuppressWarnings("unchecked")
                Map<String, Object> resp = restClient.post()
                        .uri(url)
                        .contentType(MediaType.APPLICATION_JSON)
                        .body(req)
                        .retrieve()
                        .body(Map.class);
                if (resp != null && resp.get("candidates") instanceof List<?> candidates && !candidates.isEmpty()) {
                    Object first = candidates.get(0);
                    if (first instanceof Map<?, ?> cMap && cMap.get("content") instanceof Map<?, ?> contentMap
                            && contentMap.get("parts") instanceof List<?> parts && !parts.isEmpty()
                            && parts.get(0) instanceof Map<?, ?> partMap) {
                        aiReply = String.valueOf(partMap.get("text"));
                    }
                }
            } catch (Exception e) {
                log.warn("Gemini API fallback used: {}", e.getMessage());
            }
        }

        if (aiReply == null || aiReply.isBlank()) {
            aiReply = buildSmartLocalReply(prompt, approvedVenues, openMatches);
        }

        return ResponseEntity.ok(Map.of(
                "reply", aiReply,
                "suggestedVenues", approvedVenues.stream().limit(2).toList(),
                "suggestedMatches", openMatches.stream().limit(2).toList()
        ));
    }

    private String buildSmartLocalReply(String prompt, List<Venue> venues, List<MatchPost> matches) {
        String lower = prompt.toLowerCase();
        if (lower.contains("hủy") || lower.contains("hoàn tiền") || lower.contains("đổi lịch")) {
            return "📌 **Chính sách Đổi lịch & Hoàn tiền của Badminton Hub:**\n"
                    + "• **Hủy trước ≥ 24 tiếng:** Hoàn **100%** tiền vé ngay lập tức vào **Ví Cầu Lông nội bộ**.\n"
                    + "• **Hủy trước từ 6h đến < 24 tiếng:** Hoàn **50%** tiền vé vào Ví.\n"
                    + "• **Hủy sát giờ (< 6 tiếng):** Không áp dụng hoàn tiền.\n"
                    + "• **Đổi lịch (Reschedule):** Miễn phí đổi 1 lần sang khung giờ trống khác ngay tại màn hình Chi tiết Vé!";
        }
        if (lower.contains("kèo") || lower.contains("giao lưu") || lower.contains("ghép") || lower.contains("trình độ")) {
            StringBuilder sb = new StringBuilder("🤝 **Các Kèo Giao Lưu đang mở trên hệ thống:**\n");
            for (MatchPost m : matches) {
                sb.append("• **").append(m.getTitle()).append("** tại ").append(m.getVenueName())
                        .append(" (").append(m.getStartTime()).append("-").append(m.getEndTime()).append(") — Trình độ: `")
                        .append(m.getRequiredSkill()).append("`, còn **")
                        .append(m.getMaxPlayers() - m.getCurrentPlayers()).append(" chỗ**, phí chia sẻ **")
                        .append((long) m.getFeePerPlayer()).append("đ/người**.\n");
            }
            sb.append("👉 Bạn có thể bấm trực tiếp vào thẻ Kèo bên dưới để xin tham gia ngay!");
            return sb.toString();
        }

        StringBuilder sb = new StringBuilder("🏸 **Gợi ý Sân Cầu Lông đang có khung giờ trống hôm nay:**\n");
        for (Venue v : venues) {
            sb.append("• **").append(v.getName()).append("** (").append(v.getAddress()).append(") — Giá từ **")
                    .append((long) v.getBasePricePerHour()).append("đ - ").append((long) v.getPeakPricePerHour())
                    .append("đ/giờ**, quy mô ").append(v.getTotalCourts()).append(" sân thảm tiêu chuẩn.\n");
        }
        sb.append("\n💡 Mình cũng tìm thấy **").append(matches.size()).append(" kèo giao lưu** đang tuyển thêm thành viên tối nay. Bạn bấm vào thẻ gợi ý bên dưới để Đặt sân hoặc Ghép kèo nhé!");
        return sb.toString();
    }
}
