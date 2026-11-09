package com.badminton.v2.routing;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Dịch vụ tìm đường trên bản đồ đường TP.HCM tự dựng từ OpenStreetMap.
 *
 * Khi khởi động (chạy nền, không chặn backend):
 * 1. Có file đồ thị ({data-dir}/hcm-roads.graph) -> đọc (vài giây).
 * 2. Chưa có -> tải dữ liệu OSM qua Overpass theo từng ô, dựng đồ thị, lưu file (lần đầu ~15-30 phút).
 * Trong lúc chuẩn bị, API trả 503 kèm trạng thái + % tiến độ; app quay về nét đứt đường chim bay.
 */
@Service
public class RoutingService {

    private static final Logger log = LoggerFactory.getLogger(RoutingService.class);
    private static final String GRAPH_FILE = "hcm-roads.graph";
    private static final int CACHE_SIZE = 500;
    private static final long CACHE_TTL_MS = 10 * 60_000L;
    private static final int PER_MINUTE_LIMIT = 30;

    public enum State { DISABLED, LOADING, DOWNLOADING, BUILDING, READY, FAILED }

    @Value("${app.routing.enabled:true}")
    private boolean enabled;
    @Value("${app.routing.data-dir:./data/routing}")
    private String dataDir;
    /** Vùng phủ: nam, tây, bắc, đông. Mặc định TP.HCM (trừ Cần Giờ) và Dĩ An / Thuận An. */
    @Value("${app.routing.bbox:10.60,106.40,11.10,106.95}")
    private String bbox;
    @Value("${app.routing.tile-size-deg:0.1}")
    private double tileDeg;
    @Value("${app.routing.overpass-url:https://overpass-api.de/api/interpreter}")
    private String overpassUrl;
    @Value("${app.routing.auto-import:true}")
    private boolean autoImport;
    @Value("${app.routing.traffic-factor:1.15}")
    private double trafficFactor;
    @Value("${app.routing.keep-tiles:false}")
    private boolean keepTiles;

    private final ExecutorService worker = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "routing-import");
        t.setDaemon(true);
        return t;
    });

    private volatile RoutePlanner planner;
    private volatile State state = State.LOADING;
    private volatile String message = "Đang khởi động";
    private volatile int progress;
    private volatile boolean busy;

    private final Map<String, CachedRoute> cache = new LinkedHashMap<>(64, 0.75f, true) {
        @Override
        protected boolean removeEldestEntry(Map.Entry<String, CachedRoute> eldest) {
            return size() > CACHE_SIZE;
        }
    };
    private final Map<Long, Deque<Long>> requests = new ConcurrentHashMap<>();

    private record CachedRoute(RouteResult result, long at) {}

    // ------------------------------------------------------------------ lỗi

    public static class RoutingUnavailableException extends RuntimeException {
        public RoutingUnavailableException(String message) {
            super(message);
        }
    }

    public static class RateLimitedException extends RuntimeException {
        public RateLimitedException(String message) {
            super(message);
        }
    }

    // ------------------------------------------------------------------ khởi động

    @EventListener(ApplicationReadyEvent.class)
    public void onReady() {
        if (!enabled) {
            state = State.DISABLED;
            message = "Tính năng tìm đường đang tắt (app.routing.enabled=false).";
            return;
        }
        submit(false);
    }

    /** Admin: tải lại dữ liệu OSM và dựng lại đồ thị. false nếu đang chạy. */
    public synchronized boolean reimport() {
        if (!enabled || busy) return false;
        submit(true);
        return true;
    }

    private synchronized void submit(boolean forceDownload) {
        busy = true;
        worker.submit(() -> {
            try {
                prepare(forceDownload);
            } catch (Throwable e) {
                log.error("Chuẩn bị bản đồ đường thất bại", e);
                state = State.FAILED;
                message = "Không chuẩn bị được bản đồ đường: " + e.getMessage();
            } finally {
                busy = false;
            }
        });
    }

    private void prepare(boolean forceDownload) throws Exception {
        Path dir = Path.of(dataDir).toAbsolutePath();
        Path graphFile = dir.resolve(GRAPH_FILE);
        if (!forceDownload && Files.exists(graphFile)) {
            state = State.LOADING;
            message = "Đang đọc bản đồ đường";
            long t0 = System.currentTimeMillis();
            RoadGraph g = RoadGraph.load(graphFile);
            activate(g);
            log.info("Đã đọc bản đồ đường: {} đỉnh, {} cạnh ({} ms)", g.vertexCount(), g.edgeCount(),
                    System.currentTimeMillis() - t0);
            return;
        }
        if (!forceDownload && !autoImport) {
            state = State.FAILED;
            message = "Chưa có dữ liệu bản đồ đường. Bật ROUTING_AUTO_IMPORT=true hoặc để Admin gọi POST /api/admin/routing/reimport.";
            return;
        }

        double[] b = parseBbox(bbox);
        Path tiles = dir.resolve("tiles");
        if (forceDownload) deleteTiles(tiles);
        OverpassImporter importer = new OverpassImporter(overpassUrl, tiles, (p, m) -> {
            progress = p;
            message = m;
        });

        state = State.DOWNLOADING;
        progress = 0;
        log.info("Bắt đầu tải bản đồ đường OSM vùng {} (ô {}°) từ {}", bbox, tileDeg, overpassUrl);
        List<Path> files = importer.download(b[0], b[1], b[2], b[3], tileDeg);

        state = State.BUILDING;
        progress = 0;
        GraphBuilder builder = new GraphBuilder();
        importer.parse(files, builder);
        message = "Đang dựng đồ thị đường";
        RoadGraph g = builder.build();
        g.save(graphFile);
        log.info("Đã dựng bản đồ đường: {} đỉnh, {} cạnh -> {}", g.vertexCount(), g.edgeCount(), graphFile);
        if (!keepTiles) deleteTiles(tiles);
        activate(g);
    }

    private void activate(RoadGraph g) {
        planner = new RoutePlanner(g, trafficFactor);
        synchronized (cache) {
            cache.clear();
        }
        state = State.READY;
        progress = 100;
        message = String.format(Locale.ROOT, "Sẵn sàng (%,d đỉnh, %,d cạnh)", g.vertexCount(), g.edgeCount());
    }

    static double[] parseBbox(String raw) {
        String[] parts = raw.split(",");
        if (parts.length != 4) throw new IllegalArgumentException("app.routing.bbox phải có dạng nam,tây,bắc,đông");
        double[] b = new double[4];
        for (int i = 0; i < 4; i++) b[i] = Double.parseDouble(parts[i].trim());
        if (b[0] >= b[2] || b[1] >= b[3]) throw new IllegalArgumentException("app.routing.bbox không hợp lệ: " + raw);
        return b;
    }

    private static void deleteTiles(Path tiles) {
        if (!Files.isDirectory(tiles)) return;
        try (DirectoryStream<Path> ds = Files.newDirectoryStream(tiles)) {
            for (Path p : ds) Files.deleteIfExists(p);
        } catch (IOException e) {
            log.warn("Không xoá được thư mục ô tạm {}: {}", tiles, e.getMessage());
        }
    }

    // ------------------------------------------------------------------ tìm đường

    public RouteResult route(Long userId, double fromLat, double fromLng, double toLat, double toLng,
                             TravelMode mode, String destinationName, String cacheKeySuffix) {
        RoutePlanner p = planner;
        if (p == null) throw new RoutingUnavailableException(message);
        checkRate(userId);

        // ~100 m: người dùng đứng gần như cùng chỗ thì dùng lại kết quả
        String key = String.format(Locale.ROOT, "%.3f,%.3f|%s|%s", fromLat, fromLng, cacheKeySuffix, mode);
        long now = System.currentTimeMillis();
        synchronized (cache) {
            CachedRoute c = cache.get(key);
            if (c != null && now - c.at() < CACHE_TTL_MS) return c.result();
        }
        RouteResult result = p.route(fromLat, fromLng, toLat, toLng, mode, destinationName);
        synchronized (cache) {
            cache.put(key, new CachedRoute(result, now));
        }
        return result;
    }

    private void checkRate(Long userId) {
        if (userId == null) return;
        long now = System.currentTimeMillis();
        Deque<Long> q = requests.computeIfAbsent(userId, k -> new ArrayDeque<>());
        synchronized (q) {
            while (!q.isEmpty() && now - q.peekFirst() > 60_000) q.pollFirst();
            if (q.size() >= PER_MINUTE_LIMIT) {
                throw new RateLimitedException("Bạn tìm đường hơi nhanh, vui lòng thử lại sau ít giây.");
            }
            q.addLast(now);
        }
    }

    public Map<String, Object> status() {
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("state", state.name());
        res.put("ready", state == State.READY);
        res.put("progress", progress);
        res.put("message", message);
        RoutePlanner p = planner;
        if (p != null) {
            res.put("vertices", p.graph().vertexCount());
            res.put("edges", p.graph().edgeCount());
            res.put("bounds", p.graph().bounds());
        }
        res.put("coverage", bbox);
        return res;
    }

    /** Dùng trong test: nạp đồ thị dựng sẵn. */
    public void useGraph(RoadGraph g) {
        activate(g);
    }
}
