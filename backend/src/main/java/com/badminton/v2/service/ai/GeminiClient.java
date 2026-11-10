package com.badminton.v2.service.ai;

import org.springframework.beans.factory.annotation.Value;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.HttpStatusCodeException;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Gọi Gemini generateContent (REST v1beta). API key gửi qua header x-goog-api-key,
 * chỉ nằm ở máy chủ (biến môi trường GEMINI_API_KEY), không bao giờ gửi xuống app.
 */
@Component
public class GeminiClient {

    private static final String BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models/";

    private static final Logger log = LoggerFactory.getLogger(GeminiClient.class);

    private final RestClient restClient;
    private final String apiKey;
    private final String model;
    /** Model dự phòng khi model chính quá tải (503 / 429). Trống = chỉ thử lại model chính. */
    private final String fallbackModel;

    public GeminiClient(@Value("${app.gemini.api-key:}") String apiKey,
                        @Value("${app.gemini.model:gemini-3.8-flash}") String model,
                        @Value("${app.gemini.fallback-model:}") String fallbackModel) {
        // Giới hạn thời gian để máy chủ luôn trả lời app trước khi app hết thời gian chờ (60 giây)
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(5_000);
        factory.setReadTimeout(25_000);
        this.restClient = RestClient.builder().requestFactory(factory).build();
        this.apiKey = apiKey == null ? "" : apiKey.trim();
        this.model = model == null || model.isBlank() ? "gemini-3.8-flash" : model.trim();
        this.fallbackModel = fallbackModel == null ? "" : fallbackModel.trim();
    }

    public boolean isConfigured() {
        return !apiKey.isEmpty();
    }

    /**
     * @param systemInstruction luật của trợ lý
     * @param contents          lịch sử hội thoại (role user / model, parts)
     * @param functionDeclarations các hàm mô hình được gọi
     * @return nội dung (content) của ứng viên đầu tiên: {"role": "model", "parts": [...]}
     */
    @SuppressWarnings("unchecked")
    public Map<String, Object> generate(String systemInstruction,
                                        List<Map<String, Object>> contents,
                                        List<Map<String, Object>> functionDeclarations) {
        Map<String, Object> generationConfig = new LinkedHashMap<>();
        generationConfig.put("temperature", 0.2);
        // Model mới có thể "suy nghĩ" trước khi trả lời, chừa thêm token để câu trả lời không bị cắt
        generationConfig.put("maxOutputTokens", model.startsWith("gemini-2.5-flash") ? 1024 : 4096);
        if (model.startsWith("gemini-2.5-flash")) {
            // Tắt "thinking" để trả lời nhanh trên mobile (chỉ áp dụng cho 2.5 Flash)
            generationConfig.put("thinkingConfig", Map.of("thinkingBudget", 0));
        }

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("systemInstruction", Map.of("parts", List.of(Map.of("text", systemInstruction))));
        body.put("contents", contents);
        body.put("tools", List.of(Map.of("functionDeclarations", functionDeclarations)));
        body.put("toolConfig", Map.of("functionCallingConfig", Map.of("mode", "AUTO")));
        body.put("generationConfig", generationConfig);

        Map<String, Object> resp = callWithRetry(body);
        if (resp == null || !(resp.get("candidates") instanceof List<?> candidates) || candidates.isEmpty()) {
            throw new IllegalStateException("Gemini không trả về kết quả");
        }
        Object first = candidates.get(0);
        if (!(first instanceof Map<?, ?> candidate) || !(candidate.get("content") instanceof Map<?, ?> content)) {
            throw new IllegalStateException("Gemini trả về nội dung rỗng");
        }
        return (Map<String, Object>) content;
    }

    /**
     * Model đang quá tải (503) hoặc hết lượt tạm thời (429): đợi 1 giây thử lại một lần,
     * vẫn lỗi thì thử model dự phòng (nếu cấu hình). Lỗi khác ném ra ngay để dùng trả lời dự phòng.
     */
    @SuppressWarnings("unchecked")
    private Map<String, Object> callWithRetry(Map<String, Object> body) {
        List<String> attempts = new java.util.ArrayList<>(List.of(model, model));
        if (!fallbackModel.isEmpty() && !fallbackModel.equals(model)) attempts.add(fallbackModel);
        RuntimeException last = null;
        for (int i = 0; i < attempts.size(); i++) {
            String m = attempts.get(i);
            try {
                return restClient.post()
                        .uri(BASE_URL + m + ":generateContent")
                        .header("x-goog-api-key", apiKey)
                        .contentType(MediaType.APPLICATION_JSON)
                        .body(body)
                        .retrieve()
                        .body(Map.class);
            } catch (HttpStatusCodeException e) {
                int code = e.getStatusCode().value();
                if (code != 503 && code != 429) throw e;
                last = e;
                log.info("Gemini {} báo {} (lần {}), thử lại", m, code, i + 1);
                try {
                    Thread.sleep(1_000);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    throw e;
                }
            }
        }
        throw last;
    }
}
