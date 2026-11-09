package com.badminton.v2.service.ai;

import org.springframework.stereotype.Component;

import java.util.List;
import java.util.regex.Pattern;

/**
 * Lớp lọc 1 (không tốn token): chặn câu quá dài, câu cố "bẻ khóa" trợ lý (jailbreak)
 * và các yêu cầu rõ ràng nằm ngoài phạm vi (viết code, giải bài tập, dịch, làm thơ...).
 * Lớp 2 là System Prompt + trường "inScope" trong câu trả lời của Gemini.
 */
@Component
public class AiGuardrail {

    public static final int MAX_MESSAGE_LENGTH = 300;

    public static final String OUT_OF_SCOPE_REPLY =
            "Mình là Trợ lý Cầu Lông nên chỉ hỗ trợ đặt sân, xem giờ trống, bảng giá, chính sách hủy / hoàn tiền "
                    + "và tìm kèo giao lưu. Bạn muốn mình giúp gì về sân cầu lông không?";

    public static final List<String> DEFAULT_CHIPS = List.of(
            "Sân trống tối nay",
            "Kèo hợp trình độ của tôi",
            "Chính sách hủy sân",
            "Vé sắp tới của tôi"
    );

    /** So khớp trên chữ đã bỏ dấu, chữ thường (xem {@link AiTools#fold}). */
    private static final List<Pattern> JAILBREAK = compile(
            "ignore (all |the )?(previous|above|prior) (instructions|rules|prompts?)",
            "system prompt", "prompt he thong", "jailbreak", "developer mode", "dan mode",
            "you are now", "act as", "pretend (to be|you)", "dong vai", "gia vo (la|lam)",
            "bo qua (moi |tat ca |cac )?(huong dan|chi dan|quy tac|luat)",
            "quen (het |moi |tat ca )?(huong dan|chi dan|quy tac|luat)",
            "(tiet lo|cho (toi|minh) xem|in ra) (huong dan|cau lenh|prompt)"
    );

    private static final List<Pattern> OFF_TOPIC = compile(
            "viet (code|chuong trinh|ham|script)", "lap trinh", "\\b(python|javascript|java|c\\+\\+|sql|html|css)\\b",
            "giai (bai|phuong trinh|toan)", "bai tap (ve nha)?", "homework",
            "dich (sang|giup|cau|doan|bai)", "translate",
            "(lam|viet) (tho|van|bai van|luan van|essay)", "ke chuyen cuoi"
    );

    private static List<Pattern> compile(String... regex) {
        return java.util.Arrays.stream(regex).map(Pattern::compile).toList();
    }

    /** Kết quả kiểm tra câu hỏi. */
    public enum Verdict { OK, EMPTY, TOO_LONG, BLOCKED }

    public Verdict check(String message) {
        if (message == null || message.isBlank()) return Verdict.EMPTY;
        if (message.length() > MAX_MESSAGE_LENGTH) return Verdict.TOO_LONG;
        String folded = AiTools.fold(message);
        for (Pattern p : JAILBREAK) {
            if (p.matcher(folded).find()) return Verdict.BLOCKED;
        }
        for (Pattern p : OFF_TOPIC) {
            if (p.matcher(folded).find()) return Verdict.BLOCKED;
        }
        return Verdict.OK;
    }
}
