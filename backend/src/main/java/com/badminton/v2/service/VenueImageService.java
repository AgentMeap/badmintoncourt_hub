package com.badminton.v2.service;

import com.badminton.v2.entity.Venue;
import com.badminton.v2.repository.VenueRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

/**
 * Ảnh cơ sở lấy từ thư mục backend/venue-images (máy chủ phục vụ tại /venue-images/<tên file>).
 *
 * Quy tắc gán ảnh (chạy mỗi lần backend khởi động và khi chủ sân tạo cơ sở mới):
 *  - File có tên bắt đầu bằng id cơ sở (VD "3.jpg", "3-san-tpt.png") là ảnh riêng của cơ sở đó.
 *  - Các file còn lại dùng chung, chia lần lượt theo id cơ sở (cơ sở id 1 lấy file thứ 1, ...).
 *  - Thư mục trống: giữ nguyên link ảnh cũ (Unsplash).
 */
@Service
public class VenueImageService {

    private static final Logger log = LoggerFactory.getLogger(VenueImageService.class);
    /** Thư mục ảnh, tính từ thư mục chạy backend. */
    public static final String DIR = "venue-images";
    public static final String URL_PREFIX = "/" + DIR + "/";
    private static final Set<String> EXTENSIONS = Set.of("jpg", "jpeg", "png", "webp");
    private static final Pattern ID_PREFIX = Pattern.compile("^(\\d+)(?:[-_ .].*)?$");

    private final VenueRepository venueRepository;

    public VenueImageService(VenueRepository venueRepository) {
        this.venueRepository = venueRepository;
    }

    /** Ảnh hiện có trong thư mục: ảnh riêng theo id + danh sách ảnh dùng chung. */
    private record Images(Map<Long, String> byVenueId, List<String> shared) {
        boolean isEmpty() { return byVenueId.isEmpty() && shared.isEmpty(); }
    }

    private Images scan() {
        Path dir = Paths.get(DIR);
        Map<Long, String> byId = new HashMap<>();
        List<String> shared = new ArrayList<>();
        if (!Files.isDirectory(dir)) return new Images(byId, shared);
        try (Stream<Path> files = Files.list(dir)) {
            List<String> names = files
                    .filter(Files::isRegularFile)
                    .map(p -> p.getFileName().toString())
                    .filter(n -> EXTENSIONS.contains(extensionOf(n)))
                    .sorted(VenueImageService::naturalOrder)
                    .toList();
            for (String name : names) {
                Matcher m = ID_PREFIX.matcher(stripExtension(name));
                if (m.matches()) {
                    byId.putIfAbsent(Long.parseLong(m.group(1)), name);
                } else {
                    shared.add(name);
                }
            }
        } catch (IOException e) {
            log.warn("Không đọc được thư mục ảnh {}: {}", dir.toAbsolutePath(), e.getMessage());
        }
        return new Images(byId, shared);
    }

    private static String pick(Images images, Venue v) {
        String own = images.byVenueId().get(v.getId());
        if (own != null) return URL_PREFIX + own;
        if (images.shared().isEmpty()) return null;
        int index = (int) Math.floorMod(v.getId() - 1, (long) images.shared().size());
        return URL_PREFIX + images.shared().get(index);
    }

    /** Gán ảnh cho một cơ sở (gọi sau khi lưu để đã có id). Trả về true nếu đổi ảnh. */
    public boolean assign(Venue v) {
        String url = pick(scan(), v);
        if (url == null || url.equals(v.getImageUrl())) return false;
        v.setImageUrl(url);
        return true;
    }

    @EventListener(ApplicationReadyEvent.class)
    @Transactional
    public void syncAll() {
        Images images = scan();
        if (images.isEmpty()) {
            log.info("Thư mục {} chưa có ảnh: giữ ảnh cơ sở hiện tại.", Paths.get(DIR).toAbsolutePath());
            return;
        }
        int changed = 0;
        for (Venue v : venueRepository.findAll()) {
            String url = pick(images, v);
            if (url != null && !url.equals(v.getImageUrl())) {
                v.setImageUrl(url);
                venueRepository.save(v);
                changed++;
            }
        }
        log.info("Ảnh cơ sở: {} ảnh riêng, {} ảnh dùng chung, cập nhật {} cơ sở.",
                images.byVenueId().size(), images.shared().size(), changed);
    }

    private static String extensionOf(String name) {
        int dot = name.lastIndexOf('.');
        return dot < 0 ? "" : name.substring(dot + 1).toLowerCase(Locale.ROOT);
    }

    private static String stripExtension(String name) {
        int dot = name.lastIndexOf('.');
        return dot < 0 ? name : name.substring(0, dot);
    }

    /** "2.jpg" đứng trước "10.jpg". */
    private static int naturalOrder(String a, String b) {
        Matcher ma = Pattern.compile("^(\\d+)").matcher(a);
        Matcher mb = Pattern.compile("^(\\d+)").matcher(b);
        if (ma.find() && mb.find()) {
            int c = Long.compare(Long.parseLong(ma.group(1)), Long.parseLong(mb.group(1)));
            if (c != 0) return c;
        }
        return a.compareToIgnoreCase(b);
    }
}
