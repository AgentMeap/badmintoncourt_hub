package com.badminton.v2.routing;

import com.fasterxml.jackson.core.JsonFactory;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.core.JsonToken;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.HttpTimeoutException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;

/**
 * Tải đường phố OpenStreetMap qua Overpass API theo từng ô (lưu gzip để chạy lại không phải tải lại),
 * rồi đọc các ô vào {@link GraphBuilder}.
 * - Ô lỗi tạm thời (429 / 503 / 504 / hết thời gian) được thử lại với thời gian chờ tăng dần.
 * - Ô quá nặng (Overpass báo runtime error / timeout) được chia làm 4 ô nhỏ hơn.
 */
public final class OverpassImporter {

    private static final Logger log = LoggerFactory.getLogger(OverpassImporter.class);

    /** Các loại đường cần tải (khớp {@link RoadClass}). */
    static final String HIGHWAY_REGEX = "^(motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|"
            + "secondary_link|tertiary|tertiary_link|unclassified|residential|living_street|service|road|track|"
            + "pedestrian|footway|path|cycleway|steps)$";

    private static final int MAX_ATTEMPTS = 4;
    private static final int MAX_SPLIT_DEPTH = 3;

    /** Lỗi không thể thử lại (VD câu truy vấn sai). */
    static final class FatalOverpassException extends IOException {
        FatalOverpassException(String message) {
            super(message);
        }
    }

    public interface Progress {
        void update(int percent, String message);
    }

    private final String endpoint;
    private final Path tileDir;
    private final Progress progress;
    private final HttpClient http;
    private final JsonFactory json = new JsonFactory();

    public OverpassImporter(String endpoint, Path tileDir, Progress progress) {
        this.endpoint = endpoint;
        this.tileDir = tileDir;
        this.progress = progress == null ? (p, m) -> { } : progress;
        this.http = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(30))
                .followRedirects(HttpClient.Redirect.NORMAL)
                .build();
    }

    static String query(double s, double w, double n, double e) {
        return String.format(Locale.ROOT,
                "[out:json][timeout:300];way[\"highway\"~\"%s\"][\"area\"!=\"yes\"](%.5f,%.5f,%.5f,%.5f);out body;>;out skel qt;",
                HIGHWAY_REGEX, s, w, n, e);
    }

    /** Tải mọi ô trong vùng (bỏ qua ô đã có file). Trả về danh sách file đã tải. */
    public List<Path> download(double south, double west, double north, double east, double tileDeg)
            throws IOException, InterruptedException {
        Files.createDirectories(tileDir);
        List<double[]> tiles = new ArrayList<>();
        for (double s = south; s < north - 1e-9; s += tileDeg) {
            for (double w = west; w < east - 1e-9; w += tileDeg) {
                tiles.add(new double[]{s, w, Math.min(s + tileDeg, north), Math.min(w + tileDeg, east)});
            }
        }
        List<Path> files = new ArrayList<>();
        for (int i = 0; i < tiles.size(); i++) {
            double[] t = tiles.get(i);
            progress.update(i * 100 / tiles.size(), "Đang tải bản đồ đường ô " + (i + 1) + "/" + tiles.size());
            fetchTile(t[0], t[1], t[2], t[3], 0, files);
        }
        progress.update(100, "Đã tải " + tiles.size() + " ô bản đồ");
        return files;
    }

    private void fetchTile(double s, double w, double n, double e, int depth, List<Path> out)
            throws IOException, InterruptedException {
        Path file = tileDir.resolve(String.format(Locale.ROOT, "tile_%.4f_%.4f_%.4f_%.4f.json.gz", s, w, n, e));
        if (Files.exists(file) && Files.size(file) > 0) {
            out.add(file);
            return;
        }
        boolean tooHeavy = false;
        for (int attempt = 1; attempt <= MAX_ATTEMPTS && !tooHeavy; attempt++) {
            Path tmp = file.resolveSibling(file.getFileName() + ".part");
            try {
                long started = System.currentTimeMillis();
                int status = downloadTo(query(s, w, n, e), tmp);
                boolean slowFailure = System.currentTimeMillis() - started > 90_000;
                if (status == 200) {
                    String remark = remarkOf(tmp);
                    if (remark == null) {
                        Files.move(tmp, file, StandardCopyOption.REPLACE_EXISTING);
                        out.add(file);
                        return;
                    }
                    log.warn("Overpass báo lỗi ô {}: {}", file.getFileName(), remark);
                    tooHeavy = true;
                } else if ((status == 502 || status == 504) && (slowFailure || (status == 504 && attempt >= 2))) {
                    // Máy chủ xử lý quá lâu rồi mới báo lỗi = ô quá nặng -> chia nhỏ ngay, không chờ tiếp
                    log.warn("Ô {} quá nặng ({}), chia thành 4 ô nhỏ", file.getFileName(), status);
                    tooHeavy = true;
                } else if (status == 429 || status == 502 || status == 503 || status == 504) {
                    log.warn("Overpass bận ({}), thử lại ô {} lần {}", status, file.getFileName(), attempt);
                    Thread.sleep(attempt * 15_000L);
                } else {
                    throw new FatalOverpassException("Overpass trả mã " + status + " cho ô " + file.getFileName());
                }
            } catch (HttpTimeoutException ex) {
                log.warn("Hết thời gian tải ô {} (lần {})", file.getFileName(), attempt);
                tooHeavy = attempt >= 2;
            } catch (FatalOverpassException ex) {
                throw ex;
            } catch (IOException ex) {
                // Mất kết nối giữa chừng...: chờ rồi thử lại
                log.warn("Lỗi mạng khi tải ô {} (lần {}): {}", file.getFileName(), attempt, ex.getMessage());
                Thread.sleep(attempt * 10_000L);
            } finally {
                Files.deleteIfExists(tmp);
            }
        }
        if (depth >= MAX_SPLIT_DEPTH) {
            throw new IOException("Không tải được ô bản đồ " + file.getFileName() + " sau nhiều lần thử.");
        }
        // Chia 4 ô nhỏ
        double ms = (s + n) / 2, mw = (w + e) / 2;
        fetchTile(s, w, ms, mw, depth + 1, out);
        fetchTile(s, mw, ms, e, depth + 1, out);
        fetchTile(ms, w, n, mw, depth + 1, out);
        fetchTile(ms, mw, n, e, depth + 1, out);
    }

    private int downloadTo(String query, Path target) throws IOException, InterruptedException {
        HttpRequest req = HttpRequest.newBuilder(URI.create(endpoint))
                .timeout(Duration.ofSeconds(420))
                .header("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
                .header("User-Agent", "BadmintonHub-PRM393/1.0 (student project; routing import)")
                .POST(HttpRequest.BodyPublishers.ofString("data=" + URLEncoder.encode(query, StandardCharsets.UTF_8)))
                .build();
        HttpResponse<InputStream> res = http.send(req, HttpResponse.BodyHandlers.ofInputStream());
        try (InputStream in = res.body()) {
            if (res.statusCode() != 200) {
                in.transferTo(OutputStream.nullOutputStream());
                return res.statusCode();
            }
            try (OutputStream o = new GZIPOutputStream(Files.newOutputStream(target), 1 << 16)) {
                in.transferTo(o);
            }
        }
        return 200;
    }

    /** Nội dung "remark" (Overpass dùng để báo lỗi khi vẫn trả HTTP 200), null nếu không có. */
    private String remarkOf(Path file) throws IOException {
        try (InputStream in = new GZIPInputStream(Files.newInputStream(file), 1 << 16);
             JsonParser p = json.createParser(in)) {
            if (p.nextToken() != JsonToken.START_OBJECT) return "Phản hồi không phải JSON";
            while (p.nextToken() == JsonToken.FIELD_NAME) {
                String field = p.currentName();
                p.nextToken();
                if ("remark".equals(field)) {
                    String r = p.getValueAsString("");
                    if (r.contains("error") || r.contains("timed out") || r.contains("Timeout")) return r;
                } else {
                    p.skipChildren();
                }
            }
            return null;
        } catch (IOException e) {
            return "JSON hỏng: " + e.getMessage();
        }
    }

    /** Đọc các ô đã tải vào [builder] (đọc luồng, không giữ cả file trong bộ nhớ). */
    public void parse(List<Path> files, GraphBuilder builder) throws IOException {
        for (int i = 0; i < files.size(); i++) {
            progress.update(i * 100 / Math.max(1, files.size()), "Đang đọc dữ liệu ô " + (i + 1) + "/" + files.size());
            try (InputStream in = new GZIPInputStream(Files.newInputStream(files.get(i)), 1 << 16);
                 JsonParser p = json.createParser(in)) {
                parseStream(p, builder);
            }
        }
    }

    static void parseStream(JsonParser p, GraphBuilder builder) throws IOException {
        if (p.nextToken() != JsonToken.START_OBJECT) throw new IOException("Dữ liệu Overpass không hợp lệ");
        while (p.nextToken() == JsonToken.FIELD_NAME) {
            String field = p.currentName();
            JsonToken t = p.nextToken();
            if (!"elements".equals(field) || t != JsonToken.START_ARRAY) {
                p.skipChildren();
                continue;
            }
            while (p.nextToken() == JsonToken.START_OBJECT) readElement(p, builder);
        }
    }

    private static void readElement(JsonParser p, GraphBuilder builder) throws IOException {
        String type = null;
        long id = 0;
        double lat = Double.NaN, lon = Double.NaN;
        long[] nodes = null;
        Map<String, String> tags = null;
        while (p.nextToken() == JsonToken.FIELD_NAME) {
            String f = p.currentName();
            JsonToken t = p.nextToken();
            switch (f) {
                case "type" -> type = p.getText();
                case "id" -> id = p.getLongValue();
                case "lat" -> lat = p.getDoubleValue();
                case "lon" -> lon = p.getDoubleValue();
                case "nodes" -> {
                    long[] buf = new long[64];
                    int n = 0;
                    while (p.nextToken() != JsonToken.END_ARRAY) {
                        if (n == buf.length) buf = java.util.Arrays.copyOf(buf, n * 2);
                        buf[n++] = p.getLongValue();
                    }
                    nodes = java.util.Arrays.copyOf(buf, n);
                }
                case "tags" -> {
                    tags = new HashMap<>();
                    while (p.nextToken() == JsonToken.FIELD_NAME) {
                        String k = p.currentName();
                        p.nextToken();
                        tags.put(k, p.getText());
                    }
                }
                default -> {
                    if (t == JsonToken.START_OBJECT || t == JsonToken.START_ARRAY) p.skipChildren();
                }
            }
        }
        if ("node".equals(type) && !Double.isNaN(lat) && !Double.isNaN(lon)) {
            builder.addNode(id, lat, lon);
        } else if ("way".equals(type) && nodes != null && tags != null) {
            builder.addWay(id, nodes, tags);
        }
    }
}
