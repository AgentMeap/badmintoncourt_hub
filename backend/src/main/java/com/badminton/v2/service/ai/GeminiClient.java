package com.badminton.v2.service.ai;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
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

    private final RestClient restClient;
    private final String apiKey;
    private final String model;

    public GeminiClient(RestClient restClient,
                        @Value("${app.gemini.api-key:}") String apiKey,
                        @Value("${app.gemini.model:gemini-2.5-flash}") String model) {
        this.restClient = restClient;
        this.apiKey = apiKey == null ? "" : apiKey.trim();
        this.model = model == null || model.isBlank() ? "gemini-2.5-flash" : model.trim();
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
        generationConfig.put("maxOutputTokens", 1024);
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

        Map<String, Object> resp = restClient.post()
                .uri(BASE_URL + model + ":generateContent")
                .header("x-goog-api-key", apiKey)
                .contentType(MediaType.APPLICATION_JSON)
                .body(body)
                .retrieve()
                .body(Map.class);
        if (resp == null || !(resp.get("candidates") instanceof List<?> candidates) || candidates.isEmpty()) {
            throw new IllegalStateException("Gemini không trả về kết quả");
        }
        Object first = candidates.get(0);
        if (!(first instanceof Map<?, ?> candidate) || !(candidate.get("content") instanceof Map<?, ?> content)) {
            throw new IllegalStateException("Gemini trả về nội dung rỗng");
        }
        return (Map<String, Object>) content;
    }
}
