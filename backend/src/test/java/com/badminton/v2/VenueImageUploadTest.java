package com.badminton.v2;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockMultipartFile;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Chủ sân tải ảnh cơ sở và gửi kèm khi đăng ký cơ sở mới. */
class VenueImageUploadTest extends IntegrationTestBase {

    private static final byte[] JPEG = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0, 0, 0x10, 'J', 'F', 'I', 'F', 0, 1};

    private String upload(byte[] content, String name, int expectedStatus) throws Exception {
        var res = mvc.perform(auth(multipart("/api/media/images")
                        .file(new MockMultipartFile("file", name, "image/jpeg", content)), tokenOf(OWNER)))
                .andExpect(status().is(expectedStatus)).andReturn();
        return body(res).path("url").asText();
    }

    @Test
    @DisplayName("Tải ảnh JPG -> /uploads/venues/..., file không phải ảnh bị từ chối")
    void uploadImage() throws Exception {
        String url = upload(JPEG, "san.jpg", 200);
        assertTrue(url.startsWith("/uploads/venues/") && url.endsWith(".jpg"), url);
        upload("not an image".getBytes(), "fake.jpg", 400);
    }

    @Test
    @DisplayName("Đăng ký cơ sở kèm ảnh: ảnh đầu là ảnh bìa, giữ thứ tự, bỏ đường dẫn lạ")
    void createVenueWithImages() throws Exception {
        String a = upload(JPEG, "a.jpg", 200);
        String b = upload(JPEG, "b.jpg", 200);
        Map<String, Object> venue = new LinkedHashMap<>();
        venue.put("name", "Sân test có ảnh");
        venue.put("address", "Thủ Đức");
        venue.put("totalCourts", 2);
        venue.put("imageUrls", List.of(a, "https://evil.example/x.jpg", b));
        var res = body(mvc.perform(postAs(tokenOf(OWNER), venue, "/api/venues/owner")).andExpect(status().isOk()).andReturn());
        assertEquals(a, res.path("imageUrl").asText());
        assertEquals(2, res.path("imageUrls").size());
        assertEquals(b, res.path("imageUrls").get(1).asText());
    }
}
