package com.badminton.v2.service.ai;

import com.badminton.v2.entity.Booking;
import com.badminton.v2.entity.Court;
import com.badminton.v2.entity.MatchParticipant;
import com.badminton.v2.entity.MatchPost;
import com.badminton.v2.entity.User;
import com.badminton.v2.entity.Venue;
import com.badminton.v2.repository.BookingRepository;
import com.badminton.v2.repository.CourtRepository;
import com.badminton.v2.repository.MatchParticipantRepository;
import com.badminton.v2.repository.MatchPostRepository;
import com.badminton.v2.repository.UserRepository;
import com.badminton.v2.repository.VenueRepository;
import com.badminton.v2.service.BookingRules;
import com.badminton.v2.service.HostReputationService;
import com.badminton.v2.service.MatchDepositService;
import org.springframework.stereotype.Service;

import java.text.Normalizer;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.util.*;

/**
 * Các hàm CHỈ ĐỌC mà Trợ lý AI được gọi (Gemini function calling).
 * Mỗi hàm trả về dữ liệu tóm tắt cho mô hình + các thẻ (card) để app hiển thị.
 * Thẻ luôn dựng từ dữ liệu thật trong DB, không lấy từ chữ AI viết, nên AI không thể bịa giờ trống / giá.
 */
@Service
public class AiTools {

    /** Kết quả một lần gọi hàm. */
    public record ToolResult(Map<String, Object> data, List<Map<String, Object>> cards) {
    }

    /** Ngữ cảnh người hỏi. */
    public record Context(Long userId, String skillLevel, double lat, double lng) {
    }

    public static final double DEFAULT_LAT = 10.8753;
    public static final double DEFAULT_LNG = 106.8000;

    private static final int MAX_VENUES = 3;
    private static final int MAX_SLOTS = 4;
    private static final int MAX_SLOTS_PER_VENUE = 2;

    private final VenueRepository venueRepository;
    private final CourtRepository courtRepository;
    private final BookingRepository bookingRepository;
    private final MatchPostRepository matchPostRepository;
    private final MatchParticipantRepository participantRepository;
    private final UserRepository userRepository;

    public AiTools(VenueRepository venueRepository,
                   CourtRepository courtRepository,
                   BookingRepository bookingRepository,
                   MatchPostRepository matchPostRepository,
                   MatchParticipantRepository participantRepository,
                   UserRepository userRepository) {
        this.venueRepository = venueRepository;
        this.courtRepository = courtRepository;
        this.bookingRepository = bookingRepository;
        this.matchPostRepository = matchPostRepository;
        this.participantRepository = participantRepository;
        this.userRepository = userRepository;
    }

    // ------------------------------------------------------------------ Khai báo cho Gemini

    /** functionDeclarations gửi kèm request Gemini. */
    public List<Map<String, Object>> declarations() {
        return List.of(
                declare("search_venues",
                        "Tìm cơ sở sân cầu lông đang hoạt động, sắp theo khoảng cách. Dùng khi hỏi sân gần, sân rẻ, thông tin / giá sân.",
                        props(
                                "keyword", str("Tên sân hoặc khu vực, VD 'Linh Trung', 'KTX Khu B'"),
                                "maxPricePerHour", num("Giá giờ thường tối đa (VND)")
                        ), List.of()),
                declare("check_availability",
                        "Tìm khung giờ còn trống để đặt sân. Dùng khi hỏi sân trống, đặt sân, giờ nào còn chỗ.",
                        props(
                                "venueId", num("ID cơ sở nếu đã biết (từ search_venues)"),
                                "keyword", str("Tên sân / khu vực nếu chưa biết ID"),
                                "date", str("Ngày chơi yyyy-MM-dd, hoặc 'today' / 'tomorrow'"),
                                "startTime", str("Giờ bắt đầu mong muốn dạng HH:00 (để trống = giờ trống sớm nhất)"),
                                "durationHours", num("Số giờ chơi, 1-4, mặc định 2")
                        ), List.of("date")),
                declare("find_matches",
                        "Tìm kèo giao lưu đang tuyển người (bỏ qua kèo người dùng đã xin hoặc tự tổ chức). "
                                + "Mỗi kèo có mức cọc qua ví và uy tín chủ kèo (điểm, số đánh giá, huy hiệu TRUSTED). "
                                + "Dùng khi hỏi kèo, ghép đội, tìm người chơi cùng, kèo không cọc, chủ kèo uy tín.",
                        props(
                                "skill", str("Trình độ: NEWBIE, TB_YEU, TRUNG_BINH, KHA (để trống = theo hồ sơ người dùng)"),
                                "date", str("Ngày yyyy-MM-dd hoặc 'today' / 'tomorrow' (tùy chọn)"),
                                "trustedOnly", bool("true = chỉ kèo của chủ kèo có huy hiệu Uy tín"),
                                "maxDeposit", num("Số tiền cọc tối đa (VND); 0 = chỉ kèo không cần cọc")
                        ), List.of()),
                declare("get_my_matches",
                        "Kèo giao lưu của chính người đang hỏi: kèo tôi tổ chức (số đơn chờ duyệt) "
                                + "và kèo tôi đã xin tham gia (trạng thái đơn, tiền cọc).",
                        props(), List.of()),
                declare("get_policy",
                        "Chính sách của ứng dụng: hủy & hoàn tiền, đổi lịch, giữ chỗ & thanh toán, "
                                + "cọc kèo giao lưu (hủy đơn / rời kèo được hoàn bao nhiêu).",
                        props("topic", str("CANCEL, RESCHEDULE, PAYMENT, MATCH_DEPOSIT hoặc ALL")), List.of()),
                declare("get_my_bookings",
                        "Vé sắp tới của chính người đang hỏi.",
                        props(), List.of())
        );
    }

    private static Map<String, Object> declare(String name, String description, Map<String, Object> properties,
                                               List<String> required) {
        Map<String, Object> params = new LinkedHashMap<>();
        params.put("type", "OBJECT");
        params.put("properties", properties);
        if (!required.isEmpty()) params.put("required", required);
        return Map.of("name", name, "description", description, "parameters", params);
    }

    private static Map<String, Object> props(Object... kv) {
        Map<String, Object> m = new LinkedHashMap<>();
        for (int i = 0; i + 1 < kv.length; i += 2) m.put((String) kv[i], kv[i + 1]);
        return m;
    }

    private static Map<String, Object> str(String description) {
        return Map.of("type", "STRING", "description", description);
    }

    private static Map<String, Object> num(String description) {
        return Map.of("type", "NUMBER", "description", description);
    }

    private static Map<String, Object> bool(String description) {
        return Map.of("type", "BOOLEAN", "description", description);
    }

    // ------------------------------------------------------------------ Thực thi

    public ToolResult execute(String name, Map<String, Object> args, Context ctx) {
        Map<String, Object> a = args == null ? Map.of() : args;
        try {
            return switch (name) {
                case "search_venues" -> searchVenues(text(a.get("keyword")), number(a.get("maxPricePerHour")), ctx);
                case "check_availability" -> checkAvailability(
                        number(a.get("venueId")), text(a.get("keyword")), text(a.get("date")),
                        text(a.get("startTime")), number(a.get("durationHours")), ctx);
                case "find_matches" -> findMatches(text(a.get("skill")), text(a.get("date")),
                        Boolean.TRUE.equals(a.get("trustedOnly")) || "true".equalsIgnoreCase(text(a.get("trustedOnly"))),
                        number(a.get("maxDeposit")), ctx);
                case "get_my_matches" -> myMatches(ctx);
                case "get_policy" -> policy(text(a.get("topic")));
                case "get_my_bookings" -> myBookings(ctx);
                default -> new ToolResult(Map.of("error", "Hàm không tồn tại: " + name), List.of());
            };
        } catch (Exception e) {
            return new ToolResult(Map.of("error", "Không tra cứu được dữ liệu: " + e.getMessage()), List.of());
        }
    }

    // ------------------------------------------------------------------ search_venues

    public ToolResult searchVenues(String keyword, Double maxPrice, Context ctx) {
        List<Venue> venues = nearestVenues(keyword, maxPrice, ctx, MAX_VENUES);
        List<Map<String, Object>> cards = new ArrayList<>();
        List<Map<String, Object>> rows = new ArrayList<>();
        for (Venue v : venues) {
            Map<String, Object> venue = venueSummary(v, ctx);
            rows.add(venue);
            cards.add(Map.of("type", "VENUE", "venue", venue,
                    "action", Map.of("type", "OPEN_VENUE", "venueId", v.getId())));
        }
        if (!venues.isEmpty()) cards.add(miniMap(venues));
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("count", rows.size());
        data.put("venues", rows);
        if (rows.isEmpty()) data.put("note", "Không tìm thấy sân phù hợp");
        return new ToolResult(data, cards);
    }

    // ------------------------------------------------------------------ check_availability

    public ToolResult checkAvailability(Double venueId, String keyword, String dateText, String startTime,
                                        Double durationHours, Context ctx) {
        LocalDate today = LocalDate.now();
        LocalDate date = parseDate(dateText, today);
        if (date.isBefore(today) || date.isAfter(today.plusDays(13))) {
            return new ToolResult(Map.of("error", "Chỉ đặt được trong 14 ngày tới"), List.of());
        }
        int duration = durationHours == null ? 2 : (int) Math.max(1, Math.min(4, Math.round(durationHours)));
        Integer wantedStart = parseHour(startTime);

        List<Venue> venues;
        if (venueId != null) {
            venues = venueRepository.findById(venueId.longValue())
                    .filter(v -> "APPROVED".equals(v.getStatus()))
                    .map(List::of).orElse(List.of());
        } else {
            venues = nearestVenues(keyword, null, ctx, MAX_VENUES);
        }

        LocalDateTime now = LocalDateTime.now();
        List<Map<String, Object>> slots = new ArrayList<>();
        for (Venue v : venues) {
            int openHour = BookingRules.openMinutes(v) / 60;
            int closeHour = BookingRules.closeMinutes(v) / 60;
            List<Integer> starts = new ArrayList<>();
            if (wantedStart != null) {
                starts.add(wantedStart);
            } else {
                for (int h = openHour; h + duration <= closeHour; h++) starts.add(h);
            }
            List<Court> courts = courtRepository.findByVenueIdOrderByIdAsc(v.getId()).stream()
                    .filter(Court::isActive).toList();
            int perVenue = 0;
            for (int start : starts) {
                int end = start + duration;
                if (start < openHour || end > closeHour) continue;
                if (!LocalDateTime.of(date, LocalTime.of(start, 0)).isAfter(now)) continue;
                for (Court c : courts) {
                    if (!courtFree(c.getId(), date.toString(), start * 60, end * 60)) continue;
                    slots.add(slotMap(v, c, date, start, end));
                    perVenue++;
                    break; // mỗi giờ bắt đầu chỉ gợi ý 1 sân của cơ sở
                }
                if (perVenue >= MAX_SLOTS_PER_VENUE || slots.size() >= MAX_SLOTS) break;
            }
            if (slots.size() >= MAX_SLOTS) break;
        }

        List<Map<String, Object>> cards = new ArrayList<>();
        for (Map<String, Object> s : slots) {
            cards.add(Map.of("type", "VENUE_SLOT", "slot", s, "action", Map.of("type", "HOLD_SLOT")));
        }
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("date", date.toString());
        data.put("durationHours", duration);
        data.put("availableSlots", slots);
        if (venues.isEmpty()) data.put("note", "Không tìm thấy cơ sở phù hợp");
        else if (slots.isEmpty()) data.put("note", "Không còn khung trống phù hợp, gợi ý chọn giờ hoặc ngày khác");
        return new ToolResult(data, cards);
    }

    private boolean courtFree(Long courtId, String playDate, int startMin, int endMin) {
        for (Booking b : bookingRepository.findByCourtIdAndPlayDateOrderByStartTimeAsc(courtId, playDate)) {
            if (!BookingRules.blocksCourt(b)) continue;
            if (BookingRules.overlaps(startMin, endMin,
                    BookingRules.toMinutes(b.getStartTime()), BookingRules.toMinutes(b.getEndTime()))) {
                return false;
            }
        }
        return true;
    }

    private Map<String, Object> slotMap(Venue v, Court c, LocalDate date, int start, int end) {
        Map<String, Object> s = new LinkedHashMap<>();
        s.put("venueId", v.getId());
        s.put("venueName", v.getName());
        s.put("venueAddress", v.getAddress());
        s.put("courtId", c.getId());
        s.put("courtName", c.getName());
        s.put("playDate", date.toString());
        s.put("startTime", BookingRules.hourLabel(start));
        s.put("endTime", BookingRules.hourLabel(end));
        s.put("totalPrice", BookingRules.priceFor(v, date, start, end));
        s.put("peak", BookingRules.isPeak(date, start));
        return s;
    }

    // ------------------------------------------------------------------ find_matches

    public ToolResult findMatches(String skill, String dateText, Context ctx) {
        return findMatches(skill, dateText, false, null, ctx);
    }

    public ToolResult findMatches(String skill, String dateText, boolean trustedOnly, Double maxDeposit, Context ctx) {
        Set<Long> requested = new HashSet<>();
        if (ctx.userId() != null) {
            for (MatchParticipant mp : participantRepository.findByUserIdOrderByIdDesc(ctx.userId())) {
                requested.add(mp.getMatchId());
            }
        }
        String wanted = (skill == null || skill.isBlank()) ? ctx.skillLevel() : skill.trim().toUpperCase();
        LocalDate today = LocalDate.now();
        LocalDate onDate = (dateText == null || dateText.isBlank()) ? null : parseDate(dateText, today);
        List<Map<String, Object>> rows = new ArrayList<>();
        List<Map<String, Object>> cards = new ArrayList<>();
        for (MatchPost m : matchPostRepository.findAllByOrderByIdDesc()) {
            if (!"OPEN".equals(m.getStatus()) || m.getCurrentPlayers() >= m.getMaxPlayers()) continue;
            LocalDate d;
            try {
                d = LocalDate.parse(m.getPlayDate());
            } catch (Exception e) {
                continue;
            }
            if (d.isBefore(today) || (onDate != null && !d.equals(onDate))) continue;
            if (wanted != null && !wanted.isBlank() && !"ALL".equalsIgnoreCase(m.getRequiredSkill())
                    && !wanted.equalsIgnoreCase(m.getRequiredSkill())) continue;
            if (ctx.userId() != null && ctx.userId().equals(m.getHostId())) continue;
            if (requested.contains(m.getId())) continue; // đã xin rồi -> xem ở get_my_matches
            double deposit = MatchDepositService.depositOf(m);
            if (maxDeposit != null && deposit > maxDeposit + 1e-6) continue;
            Map<String, Object> host = hostSummary(m.getHostId());
            if (trustedOnly && !"TRUSTED".equals(host.get("badge"))) continue;

            Map<String, Object> match = matchRow(m, host);
            rows.add(match);
            cards.add(Map.of("type", "MATCH", "match", match,
                    "action", Map.of("type", "OPEN_MATCH", "matchId", m.getId())));
            if (rows.size() >= 3) break;
        }
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("skillFilter", wanted == null ? "ALL" : wanted);
        data.put("trustedOnly", trustedOnly);
        if (maxDeposit != null) data.put("maxDeposit", maxDeposit);
        data.put("matches", rows);
        if (rows.isEmpty()) data.put("note", "Hiện không có kèo phù hợp, có thể tự tạo kèo ở mục Ghép kèo");
        return new ToolResult(data, cards);
    }

    private Map<String, Object> hostSummary(Long hostId) {
        return userRepository.findById(hostId).map(HostReputationService::summaryOf).orElseGet(LinkedHashMap::new);
    }

    /** Một dòng kèo cho mô hình + thẻ MATCH (kèm cọc và uy tín chủ kèo). */
    private static Map<String, Object> matchRow(MatchPost m, Map<String, Object> host) {
        Map<String, Object> match = new LinkedHashMap<>();
        match.put("id", m.getId());
        match.put("title", m.getTitle());
        match.put("venueName", m.getVenueName());
        match.put("courtName", m.getCourtName());
        match.put("playDate", m.getPlayDate());
        match.put("startTime", m.getStartTime());
        match.put("endTime", m.getEndTime());
        match.put("requiredSkill", m.getRequiredSkill());
        match.put("hostName", m.getHostName());
        match.put("slotsLeft", m.getMaxPlayers() - m.getCurrentPlayers());
        match.put("feePerPlayer", m.getFeePerPlayer());
        if (MatchDepositService.splitFee(m)) {
            match.put("feeMale", m.getFeeMale());
            match.put("feeFemale", m.getFeeFemale());
        }
        match.put("status", m.getStatus());
        match.put("depositPercent", m.getDepositPercent() == null ? 0 : m.getDepositPercent());
        match.put("depositAmount", MatchDepositService.depositOf(m));
        match.put("host", host);
        return match;
    }

    // ------------------------------------------------------------------ get_my_matches

    public ToolResult myMatches(Context ctx) {
        if (ctx.userId() == null) return new ToolResult(Map.of("error", "Chưa đăng nhập"), List.of());
        List<Map<String, Object>> hosting = new ArrayList<>();
        List<Map<String, Object>> joined = new ArrayList<>();
        List<Map<String, Object>> cards = new ArrayList<>();
        for (MatchPost m : matchPostRepository.findByHostIdOrderByIdDesc(ctx.userId())) {
            if (!"OPEN".equals(m.getStatus()) && !"FULL".equals(m.getStatus())) continue;
            Map<String, Object> row = matchRow(m, hostSummary(m.getHostId()));
            long pending = participantRepository.findByMatchIdOrderByIdAsc(m.getId()).stream()
                    .filter(p -> "PENDING".equals(p.getStatus())).count();
            row.put("role", "HOST");
            row.put("pendingCount", pending);
            hosting.add(row);
            if (cards.size() < 5) {
                cards.add(Map.of("type", "MATCH", "match", row,
                        "action", Map.of("type", "OPEN_MATCH", "matchId", m.getId())));
            }
        }
        for (MatchParticipant mp : participantRepository.findByUserIdOrderByIdDesc(ctx.userId())) {
            MatchPost m = matchPostRepository.findById(mp.getMatchId()).orElse(null);
            if (m == null || (!"OPEN".equals(m.getStatus()) && !"FULL".equals(m.getStatus()))) continue;
            Map<String, Object> row = matchRow(m, hostSummary(m.getHostId()));
            row.put("role", "MEMBER");
            row.put("myStatus", mp.getStatus());
            row.put("myDeposit", mp.getDepositAmount() == null ? 0 : mp.getDepositAmount());
            row.put("myDepositStatus", mp.getDepositStatus() == null ? "NONE" : mp.getDepositStatus());
            if (mp.getRejectReason() != null) row.put("rejectReason", mp.getRejectReason());
            joined.add(row);
            if (cards.size() < 5) {
                cards.add(Map.of("type", "MATCH", "match", row,
                        "action", Map.of("type", "OPEN_MATCH", "matchId", m.getId())));
            }
        }
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("hosting", hosting);
        data.put("joined", joined);
        if (hosting.isEmpty() && joined.isEmpty()) {
            data.put("note", "Người dùng chưa tổ chức hay xin vào kèo nào đang mở");
        }
        return new ToolResult(data, cards);
    }

    // ------------------------------------------------------------------ get_policy

    public ToolResult policy(String topic) {
        String t = topic == null ? "ALL" : topic.trim().toUpperCase();
        List<String> lines = new ArrayList<>();
        if (t.equals("ALL") || t.equals("CANCEL")) {
            lines.add("Hủy trước giờ chơi từ " + BookingRules.FULL_REFUND_HOURS + " tiếng: hoàn 100% vào Ví Cầu Lông.");
            lines.add("Hủy trước " + BookingRules.HALF_REFUND_HOURS + " - " + BookingRules.FULL_REFUND_HOURS
                    + " tiếng: hoàn 50%. Dưới " + BookingRules.HALF_REFUND_HOURS + " tiếng: không hoàn tiền.");
        }
        if (t.equals("ALL") || t.equals("RESCHEDULE")) {
            lines.add("Mỗi vé được đổi lịch 1 lần, trước giờ chơi ít nhất " + BookingRules.RESCHEDULE_CUTOFF_HOURS
                    + " tiếng; chênh lệch giá được bù / hoàn qua Ví.");
        }
        if (t.equals("ALL") || t.equals("PAYMENT")) {
            lines.add("Khung giờ được giữ " + BookingRules.HOLD_MINUTES
                    + " phút để thanh toán bằng Ví Cầu Lông hoặc VietQR (PayOS).");
            lines.add("Giờ vàng: từ " + BookingRules.PEAK_START_HOUR + ":00 ngày thường và cả ngày cuối tuần.");
        }
        if (t.equals("ALL") || t.equals("MATCH_DEPOSIT") || t.equals("MATCH")) {
            lines.add("Kèo giao lưu có cọc (50% / 100%): tiền cọc trừ ví ngay khi xin tham gia, "
                    + "được giữ hộ và chỉ chuyển cho chủ kèo sau khi kèo kết thúc.");
            lines.add("Hoàn đủ cọc khi: bị từ chối, tự hủy đơn chưa duyệt, bị chủ kèo mời ra hoặc chủ kèo hủy kèo.");
            lines.add("Đã được duyệt mà tự rời kèo: còn từ 24 tiếng hoàn 100%; 2 - 24 tiếng hoàn 50% "
                    + "(50% cho chủ kèo); dưới 2 tiếng mất cọc.");
        }
        if (lines.isEmpty()) return policy("ALL");
        String title = t.equals("MATCH_DEPOSIT") || t.equals("MATCH") ? "Chính sách cọc kèo giao lưu"
                : t.equals("ALL") ? "Chính sách đặt sân & kèo giao lưu" : "Chính sách đặt sân";
        Map<String, Object> card = Map.of("type", "POLICY", "title", title, "lines", lines);
        return new ToolResult(Map.of("policy", lines), List.of(card));
    }

    // ------------------------------------------------------------------ get_my_bookings

    public ToolResult myBookings(Context ctx) {
        if (ctx.userId() == null) return new ToolResult(Map.of("error", "Chưa đăng nhập"), List.of());
        LocalDate today = LocalDate.now();
        List<Map<String, Object>> rows = new ArrayList<>();
        List<Map<String, Object>> cards = new ArrayList<>();
        for (Booking b : bookingRepository.findByCustomerIdOrderByIdDesc(ctx.userId())) {
            boolean upcoming;
            try {
                upcoming = !LocalDate.parse(b.getPlayDate()).isBefore(today);
            } catch (Exception e) {
                upcoming = false;
            }
            boolean live = List.of("CONFIRMED", "CHECKED_IN").contains(b.getStatus()) || BookingRules.isHoldActive(b);
            if (!upcoming || !live) continue;
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("id", b.getId());
            row.put("bookingCode", b.getBookingCode());
            row.put("venueName", b.getVenueName());
            row.put("courtName", b.getCourtName());
            row.put("playDate", b.getPlayDate());
            row.put("startTime", b.getStartTime());
            row.put("endTime", b.getEndTime());
            row.put("status", b.getStatus());
            row.put("totalPrice", b.getTotalPrice());
            rows.add(row);
            cards.add(Map.of("type", "BOOKING", "booking", row,
                    "action", Map.of("type", "OPEN_BOOKING", "bookingId", b.getId())));
            if (rows.size() >= 5) break;
        }
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("upcomingBookings", rows);
        if (rows.isEmpty()) data.put("note", "Bạn chưa có vé sắp tới");
        return new ToolResult(data, cards);
    }

    // ------------------------------------------------------------------ Tiện ích

    private List<Venue> nearestVenues(String keyword, Double maxPrice, Context ctx, int limit) {
        String kw = keyword == null ? "" : fold(keyword);
        return venueRepository.findByStatusOrderByIdDesc("APPROVED").stream()
                .filter(v -> kw.isBlank() || fold(v.getName()).contains(kw) || fold(v.getAddress()).contains(kw))
                .filter(v -> maxPrice == null || v.getBasePricePerHour() <= maxPrice)
                .sorted(Comparator.comparingDouble(v -> distanceKm(ctx, v)))
                .limit(limit)
                .toList();
    }

    private Map<String, Object> venueSummary(Venue v, Context ctx) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", v.getId());
        m.put("name", v.getName());
        m.put("address", v.getAddress());
        m.put("distanceKm", Math.round(distanceKm(ctx, v) * 10.0) / 10.0);
        m.put("rating", v.getRating());
        m.put("openTime", v.getOpenTime());
        m.put("closeTime", v.getCloseTime());
        m.put("totalCourts", v.getTotalCourts());
        m.put("basePricePerHour", v.getBasePricePerHour());
        m.put("peakPricePerHour", v.getPeakPricePerHour());
        m.put("imageUrl", v.getImageUrl());
        m.put("latitude", v.getLatitude());
        m.put("longitude", v.getLongitude());
        return m;
    }

    private static Map<String, Object> miniMap(List<Venue> venues) {
        List<Map<String, Object>> markers = new ArrayList<>();
        for (Venue v : venues) {
            markers.add(Map.of("venueId", v.getId(), "name", v.getName(),
                    "latitude", v.getLatitude(), "longitude", v.getLongitude()));
        }
        return Map.of("type", "MINI_MAP", "markers", markers);
    }

    private static double distanceKm(Context ctx, Venue v) {
        double dLat = Math.toRadians(v.getLatitude() - ctx.lat());
        double dLon = Math.toRadians(v.getLongitude() - ctx.lng());
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(ctx.lat())) * Math.cos(Math.toRadians(v.getLatitude()))
                * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    /** Chữ thường, bỏ dấu tiếng Việt (để "linh trung" khớp "Linh Trung"). */
    public static String fold(String s) {
        if (s == null) return "";
        String n = Normalizer.normalize(s.toLowerCase(Locale.ROOT), Normalizer.Form.NFD)
                .replaceAll("\\p{M}+", "");
        return n.replace('đ', 'd');
    }

    static LocalDate parseDate(String text, LocalDate today) {
        if (text == null || text.isBlank()) return today;
        String t = fold(text.trim());
        if (t.equals("today") || t.contains("hom nay") || t.contains("toi nay")) return today;
        if (t.equals("tomorrow") || t.contains("ngay mai") || t.equals("mai")) return today.plusDays(1);
        try {
            return LocalDate.parse(text.trim());
        } catch (Exception e) {
            return today;
        }
    }

    static Integer parseHour(String text) {
        if (text == null || text.isBlank()) return null;
        try {
            int h = Integer.parseInt(text.trim().split(":")[0].replaceAll("[^0-9]", ""));
            return (h >= 0 && h <= 23) ? h : null;
        } catch (Exception e) {
            return null;
        }
    }

    private static String text(Object v) {
        return v == null ? null : String.valueOf(v);
    }

    private static Double number(Object v) {
        if (v instanceof Number n) return n.doubleValue();
        if (v == null) return null;
        try {
            return Double.parseDouble(String.valueOf(v));
        } catch (Exception e) {
            return null;
        }
    }
}
