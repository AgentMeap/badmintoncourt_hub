package com.badminton.v2.controller;

import com.badminton.v2.entity.*;
import com.badminton.v2.repository.*;
import com.badminton.v2.service.HostReputationService;
import com.badminton.v2.service.MatchChatService;
import com.badminton.v2.service.MatchDepositService;
import com.badminton.v2.service.NotificationService;
import com.badminton.v2.security.AuthUser;
import com.badminton.v2.security.CurrentUser;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.http.ResponseEntity;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

/**
 * Kèo giao lưu (S15, S16, S30).
 * <ul>
 *   <li>GET   /api/matches                      bảng tin kèo (công khai)</li>
 *   <li>GET   /api/matches/{id}                 chi tiết một kèo (mở từ thông báo)</li>
 *   <li>GET   /api/matches/mine                 kèo tôi tổ chức + kèo tôi đã xin tham gia</li>
 *   <li>POST  /api/matches                      đăng kèo</li>
 *   <li>POST  /api/matches/{id}/join            xin tham gia</li>
 *   <li>PATCH /api/matches/{id}/participants/{pid}  chủ kèo duyệt / từ chối (kèm lý do)</li>
 *   <li>POST  /api/matches/{id}/leave           người xin hủy đơn chờ duyệt / thành viên rời kèo</li>
 *   <li>POST  /api/matches/{id}/participants/{pid}/remove  chủ kèo mời thành viên ra (kèm lý do)</li>
 *   <li>POST  /api/matches/{id}/cancel          chủ kèo hủy kèo, báo cho mọi người đã xin / đã vào</li>
 *   <li>GET   /api/matches/{id}/messages?afterId=  nhóm chat của kèo (chủ kèo + thành viên đã duyệt)</li>
 *   <li>POST  /api/matches/{id}/messages        gửi tin nhắn vào nhóm chat (báo cho thành viên khác, gộp 1 thông báo / kèo)</li>
 *   <li>PATCH /api/matches/{id}/chat-settings   {muted} tắt / bật thông báo nhóm chat</li>
 *   <li>GET   /api/matches/{id}/leave-preview   số tiền cọc được hoàn nếu hủy đơn / tự rời kèo ngay bây giờ</li>
 *   <li>POST  /api/matches/{id}/leave           hủy đơn chờ duyệt (hoàn đủ) hoặc thành viên đã duyệt tự rời (hoàn theo mốc 24h / 2h)</li>
 *   <li>GET   /api/matches/{id}/participants/{pid}/remove-preview  số tiền hoàn nếu mời ra (hoàn đủ / theo chính sách)</li>
 *   <li>POST  /api/matches/{id}/host-review     thành viên đánh giá chủ kèo (sau khi kèo kết thúc, trong 7 ngày)</li>
 *   <li>GET   /api/matches/hosts/{hostId}/profile  uy tín chủ kèo + đánh giá gần đây</li>
 * </ul>
 * Cọc trước (depositPercent 0/50/100): trừ ví khi xin tham gia, giữ hộ đến khi kèo kết thúc rồi trả chủ kèo;
 * hoàn theo chính sách trong {@link MatchDepositService}.
 * <ul>
 * </ul>
 * Mỗi kèo trả về dạng {post, participants, pendingCount, myStatus, canChat, messageCount}; SĐT người tham gia
 * chỉ hiện cho chủ kèo và chính người đó. Bảng tin chỉ hiện kèo còn mở (OPEN / FULL); kèo đã qua giờ được
 * MatchReminderScheduler chuyển sang COMPLETED.
 */
@RestController
@RequestMapping("/api/matches")
public class MatchmakingController {

    private final MatchPostRepository matchPostRepository;
    private final MatchParticipantRepository matchParticipantRepository;
    private final VenueRepository venueRepository;
    private final UserRepository userRepository;
    private final NotificationService notificationService;
    private final ObjectMapper objectMapper;
    private final MatchMessageRepository matchMessageRepository;
    private final MatchDepositService depositService;
    private final HostReputationService reputationService;
    private final MatchChatService chatService;
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    public MatchmakingController(MatchPostRepository matchPostRepository,
                                 MatchParticipantRepository matchParticipantRepository,
                                 VenueRepository venueRepository,
                                 UserRepository userRepository,
                                 NotificationService notificationService,
                                 ObjectMapper objectMapper,
                                 MatchMessageRepository matchMessageRepository,
                                 MatchDepositService depositService,
                                 HostReputationService reputationService,
                                 MatchChatService chatService) {
        this.matchPostRepository = matchPostRepository;
        this.matchParticipantRepository = matchParticipantRepository;
        this.venueRepository = venueRepository;
        this.userRepository = userRepository;
        this.notificationService = notificationService;
        this.objectMapper = objectMapper;
        this.matchMessageRepository = matchMessageRepository;
        this.depositService = depositService;
        this.reputationService = reputationService;
        this.chatService = chatService;
    }

    /** Người đang xem (null nếu chưa đăng nhập). */
    private static Long viewerId() {
        return CurrentUser.get().map(AuthUser::id).orElse(null);
    }

    /** Một kèo kèm người tham gia (thêm video / ảnh hồ sơ), số đơn chờ duyệt và trạng thái của người xem. */
    @SuppressWarnings("unchecked")
    private Map<String, Object> entryOf(MatchPost p, Long viewer) {
        Map<String, Object> post = objectMapper.convertValue(p, Map.class);
        Map<String, Object> hostSummary = new LinkedHashMap<>();
        userRepository.findById(p.getHostId()).ifPresent(h -> {
            post.put("hostVideoUrl", h.getIntroVideoUrl());
            post.put("hostAvatarUrl", h.getAvatarUrl());
            hostSummary.putAll(HostReputationService.summaryOf(h));
        });
        boolean viewerIsHost = viewer != null && viewer.equals(p.getHostId());
        List<Map<String, Object>> participants = new ArrayList<>();
        int pending = 0;
        String myStatus = null;
        for (MatchParticipant mp : matchParticipantRepository.findByMatchIdOrderByIdAsc(p.getId())) {
            boolean self = viewer != null && viewer.equals(mp.getUserId());
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", mp.getId());
            m.put("matchId", mp.getMatchId());
            m.put("userId", mp.getUserId());
            m.put("userName", mp.getUserName());
            m.put("userSkill", mp.getUserSkill());
            if (mp.getUserGender() != null) m.put("userGender", mp.getUserGender());
            m.put("status", mp.getStatus());
            m.put("joinedAt", mp.getJoinedAt());
            if (mp.getRejectReason() != null) m.put("rejectReason", mp.getRejectReason());
            if (viewerIsHost || self) {
                m.put("userPhone", mp.getUserPhone());
                m.put("depositAmount", mp.getDepositAmount() == null ? 0 : mp.getDepositAmount());
                m.put("depositStatus", mp.getDepositStatus() == null ? "NONE" : mp.getDepositStatus());
                m.put("refundedAmount", mp.getRefundedAmount() == null ? 0 : mp.getRefundedAmount());
            }
            userRepository.findById(mp.getUserId()).ifPresent(u -> {
                m.put("userVideoUrl", u.getIntroVideoUrl());
                m.put("userAvatarUrl", u.getAvatarUrl());
            });
            participants.add(m);
            if ("PENDING".equals(mp.getStatus())) pending++;
            if (self) myStatus = mp.getStatus();
        }
        Map<String, Object> item = new LinkedHashMap<>();
        item.put("post", post);
        item.put("participants", participants);
        item.put("pendingCount", pending);
        // Phí và cọc của người đang xem (kèo giá nam / nữ khác nhau)
        if (viewer != null && !viewerIsHost) {
            userRepository.findById(viewer).ifPresent(u -> {
                item.put("myFee", MatchDepositService.feeFor(p, u.getGender()));
                item.put("myDeposit", MatchDepositService.depositFor(p, u.getGender()));
            });
        }
        item.put("isHost", viewerIsHost);
        item.put("myStatus", viewerIsHost ? "HOST" : myStatus);
        boolean chatAllowed = viewerIsHost || "APPROVED".equals(myStatus);
        item.put("canChat", chatAllowed);
        if (chatAllowed && viewer != null) {
            item.put("unreadMessages", chatService.unread(p.getId(), viewer));
            item.put("chatMuted", chatService.muted(p.getId(), viewer));
        }
        item.put("messageCount", matchMessageRepository.countByMatchId(p.getId()));
        if (viewerIsHost) {
            item.put("depositHeldTotal", depositService.heldTotal(p));
        }
        item.put("host", hostSummary);
        if ("COMPLETED".equals(p.getStatus()) && viewer != null && !viewerIsHost) {
            item.put("canReviewHost", reputationService.reviewBlockReason(p, viewer, LocalDateTime.now()) == null);
            reputationService.reviewOf(p.getId(), viewer)
                    .ifPresent(r -> item.put("myHostReview", HostReputationService.reviewMap(r)));
        } else {
            item.put("canReviewHost", false);
        }
        return item;
    }

    @GetMapping("/{matchId}")
    public ResponseEntity<?> getMatch(@PathVariable Long matchId) {
        return matchPostRepository.findById(matchId)
                .<ResponseEntity<?>>map(p -> ResponseEntity.ok(entryOf(p, viewerId())))
                .orElseGet(() -> ResponseEntity.status(404).body(Map.of("error", "Kèo này không còn tồn tại.")));
    }

    /** Kèo tôi tổ chức (hosting) và kèo tôi đã xin tham gia (joined), mới nhất trước. */
    @GetMapping("/mine")
    public ResponseEntity<?> myMatches() {
        Long me = viewerId();
        if (me == null) return ResponseEntity.status(401).body(Map.of("error", "Vui lòng đăng nhập."));
        List<Map<String, Object>> hosting = new ArrayList<>();
        for (MatchPost p : matchPostRepository.findByHostIdOrderByIdDesc(me)) hosting.add(entryOf(p, me));
        List<Map<String, Object>> joined = new ArrayList<>();
        for (MatchParticipant mp : matchParticipantRepository.findByUserIdOrderByIdDesc(me)) {
            matchPostRepository.findById(mp.getMatchId()).ifPresent(p -> joined.add(entryOf(p, me)));
        }
        int pending = hosting.stream().mapToInt(e -> (int) e.get("pendingCount")).sum();
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("hosting", hosting);
        res.put("joined", joined);
        res.put("pendingTotal", pending);
        return ResponseEntity.ok(res);
    }

    @GetMapping
    public List<Map<String, Object>> listMatches(@RequestParam(required = false) String skill) {
        List<MatchPost> posts = matchPostRepository.findAllByOrderByIdDesc();
        Long viewer = viewerId();
        List<Map<String, Object>> result = new ArrayList<>();
        for (MatchPost p : posts) {
            if (closed(p)) continue; // kèo đã hủy / đã xong chỉ còn ở "Kèo của tôi"
            if (skill != null && !skill.isBlank() && !"ALL".equalsIgnoreCase(skill)) {
                if (!p.getRequiredSkill().equalsIgnoreCase(skill) && !"ALL".equalsIgnoreCase(p.getRequiredSkill())) {
                    continue;
                }
            }
            result.add(entryOf(p, viewer));
        }
        return result;
    }

    @PostMapping
    @Transactional
    public ResponseEntity<?> createMatchPost(@RequestBody Map<String, Object> body) {
        Long hostId = CurrentUser.idOr(body.getOrDefault("hostId", 1));
        Long venueId = Long.parseLong(String.valueOf(body.getOrDefault("venueId", 1)));
        Long bookingId = body.get("bookingId") != null ? Long.parseLong(String.valueOf(body.get("bookingId"))) : null;

        User host = userRepository.findById(hostId).orElseThrow();
        Venue venue = venueRepository.findById(venueId).orElseThrow();

        MatchPost post = new MatchPost();
        post.setHostId(hostId);
        post.setHostName(host.getFullName());
        post.setHostSkill(host.getSkillLevel());
        post.setBookingId(bookingId);
        post.setVenueId(venueId);
        post.setVenueName(venue.getName());
        post.setVenueAddress(venue.getAddress());
        post.setCourtName(String.valueOf(body.getOrDefault("courtName", "Sân 2")));
        post.setTitle(String.valueOf(body.getOrDefault("title", "Giao lưu cầu lông vui vẻ - Tuyển thêm đồng đội")));
        post.setPlayDate(String.valueOf(body.getOrDefault("playDate", LocalDate.now().toString())));
        post.setStartTime(String.valueOf(body.getOrDefault("startTime", "18:00")));
        post.setEndTime(String.valueOf(body.getOrDefault("endTime", "20:00")));
        post.setRequiredSkill(String.valueOf(body.getOrDefault("requiredSkill", "TB_YEU")));
        post.setMaxPlayers(Integer.parseInt(String.valueOf(body.getOrDefault("maxPlayers", 6))));
        post.setCurrentPlayers(Integer.parseInt(String.valueOf(body.getOrDefault("currentPlayers", 3))));
        post.setFeePerPlayer(Double.parseDouble(String.valueOf(body.getOrDefault("feePerPlayer", 65000))));
        // Giá riêng cho nam / nữ (VD nam 70k, nữ 55k). Chỉ nhập một mức thì dùng cho cả hai.
        Double feeMale = moneyOrNull(body.get("feeMale"));
        Double feeFemale = moneyOrNull(body.get("feeFemale"));
        if (feeMale != null || feeFemale != null) {
            if (feeMale == null) feeMale = feeFemale;
            if (feeFemale == null) feeFemale = feeMale;
            if (feeMale < 0 || feeFemale < 0) {
                return ResponseEntity.badRequest().body(Map.of("error", "Phí cho nam / nữ không hợp lệ."));
            }
            post.setFeeMale(feeMale);
            post.setFeeFemale(feeFemale);
            post.setFeePerPlayer(Math.max(feeMale, feeFemale));
        }
        if (body.get("videoUrl") != null) {
            post.setVideoUrl(String.valueOf(body.get("videoUrl")));
        }
        int depositPercent = Integer.parseInt(String.valueOf(body.getOrDefault("depositPercent", 0)));
        if (!List.of(0, 50, 100).contains(depositPercent)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Mức cọc chỉ được chọn 0%, 50% hoặc 100%."));
        }
        post.setDepositPercent(depositPercent);
        post.setDepositAmount(MatchDepositService.depositFor(post.getFeePerPlayer(), depositPercent));
        post.setStatus("OPEN");
        post.setCreatedAt(LocalDateTime.now().format(FMT));

        post = matchPostRepository.save(post);
        return ResponseEntity.ok(post);
    }

    @PostMapping("/{matchId}/join")
    @Transactional
    public ResponseEntity<?> requestJoinMatch(@PathVariable Long matchId, @RequestBody Map<String, Object> body) {
        Long userId = CurrentUser.idOr(body.get("userId"));
        MatchPost post = matchPostRepository.findById(matchId).orElseThrow();
        if (userId.equals(post.getHostId())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Bạn là chủ kèo này."));
        }
        if (closed(post)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Kèo này đã kết thúc hoặc đã bị hủy."));
        }
        User user = userRepository.findById(userId).orElseThrow();

        Optional<MatchParticipant> existing = matchParticipantRepository.findByMatchIdAndUserId(matchId, userId);
        if (existing.isPresent()) {
            String msg = "REMOVED".equals(existing.get().getStatus())
                    ? "Chủ kèo đã mời bạn ra khỏi kèo này."
                    : "Bạn đã gửi yêu cầu tham gia kèo này rồi!";
            return ResponseEntity.badRequest().body(Map.of("error", msg));
        }
        if (post.getCurrentPlayers() >= post.getMaxPlayers()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Kèo giao lưu này đã đủ người!"));
        }

        if (MatchDepositService.splitFee(post) && user.getGender() == null) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "Kèo này có giá riêng cho nam và nữ. Vui lòng cập nhật giới tính trong hồ sơ trước khi xin tham gia."));
        }
        if (!depositService.canAfford(user, post)) {
            double need = MatchDepositService.depositFor(post, user.getGender());
            Map<String, Object> err = new LinkedHashMap<>();
            err.put("error", "Kèo yêu cầu cọc " + MatchDepositService.format(need) + " qua ví, số dư của bạn chỉ còn "
                    + MatchDepositService.format(user.getWalletBalance()) + ". Vui lòng nạp thêm.");
            err.put("needed", need);
            err.put("balance", user.getWalletBalance());
            return ResponseEntity.status(402).body(err);
        }

        MatchParticipant mp = new MatchParticipant();
        mp.setMatchId(matchId);
        mp.setUserId(userId);
        mp.setUserName(user.getFullName());
        mp.setUserSkill(user.getSkillLevel());
        mp.setUserPhone(user.getPhone());
        mp.setUserGender(user.getGender());
        mp.setStatus("PENDING");
        mp.setJoinedAt(LocalDateTime.now().format(FMT));
        mp = matchParticipantRepository.save(mp);
        depositService.hold(mp, post); // trừ cọc ngay, giữ hộ đến khi kèo kết thúc

        notificationService.notifyUser(
                post.getHostId(),
                "Có người xin tham gia Kèo giao lưu!",
                user.getFullName() + " (Trình độ: " + user.getSkillLevel() + ") vừa xin vào kèo '" + post.getTitle() + "'.",
                "MATCHMAKING",
                "S30", // mở thẳng chi tiết kèo để chủ kèo duyệt
                post.getId()
        );
        return ResponseEntity.ok(mp);
    }

    @PatchMapping("/{matchId}/participants/{participantId}")
    @Transactional
    public ResponseEntity<?> reviewParticipant(@PathVariable Long matchId,
                                               @PathVariable Long participantId,
                                               @RequestBody Map<String, String> body) {
        String decision = String.valueOf(body.getOrDefault("status", "APPROVED")).toUpperCase();
        String reason = body.get("reason") == null ? null : body.get("reason").trim();
        if (reason != null && reason.isEmpty()) reason = null;
        if (reason != null && reason.length() > 200) reason = reason.substring(0, 200);
        MatchPost post = matchPostRepository.findById(matchId).orElseThrow();
        MatchParticipant mp = matchParticipantRepository.findById(participantId).orElseThrow();
        // Chỉ chủ kèo được duyệt / từ chối người xin vào
        CurrentUser.requireSelfOrAdmin(post.getHostId());
        if (!matchId.equals(mp.getMatchId())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Người tham gia không thuộc kèo này."));
        }
        if (!List.of("APPROVED", "REJECTED").contains(decision)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Trạng thái duyệt không hợp lệ."));
        }
        if (!"PENDING".equals(mp.getStatus())) {
            return ResponseEntity.status(409).body(Map.of("error", "Yêu cầu này đã được xử lý trước đó."));
        }
        if ("APPROVED".equals(decision) && closed(post)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Kèo này đã kết thúc hoặc đã bị hủy."));
        }
        if ("APPROVED".equals(decision) && post.getCurrentPlayers() >= post.getMaxPlayers()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Kèo đã đủ người."));
        }

        mp.setStatus(decision);
        if ("REJECTED".equals(decision)) mp.setRejectReason(reason);
        matchParticipantRepository.save(mp);
        double refunded = "REJECTED".equals(decision) ? depositService.refundFull(mp, post, "chủ kèo từ chối") : 0;

        if ("APPROVED".equals(decision)) {
            post.setCurrentPlayers(Math.min(post.getMaxPlayers(), post.getCurrentPlayers() + 1));
            if (post.getCurrentPlayers() >= post.getMaxPlayers()) {
                post.setStatus("FULL");
            }
            matchPostRepository.save(post);

            notificationService.notifyUser(
                    mp.getUserId(),
                    "Chủ kèo đã duyệt bạn vào đội!",
                    "Bạn đã được duyệt tham gia kèo '" + post.getTitle() + "' tại " + post.getVenueName() + " (" + post.getStartTime() + "-" + post.getEndTime() + ").",
                    "MATCHMAKING",
                    "S30",
                    post.getId()
            );
        } else {
            notificationService.notifyUser(
                    mp.getUserId(),
                    "Yêu cầu ghép kèo chưa phù hợp",
                    "Chủ kèo '" + post.getTitle() + "' đã từ chối yêu cầu tham gia."
                            + (reason != null ? " Lý do: " + reason : " Bạn thử tìm kèo khác hợp trình độ nhé.")
                            + (refunded > 0 ? " Đã hoàn " + MatchDepositService.format(refunded) + " cọc vào ví." : ""),
                    "MATCHMAKING",
                    "S15",
                    post.getId()
            );
        }
        return ResponseEntity.ok(Map.of("post", post, "participant", mp, "entry", entryOf(post, viewerId())));
    }

    /** Giờ bắt đầu kèo (playDate yyyy-MM-dd + startTime HH:mm), null nếu dữ liệu sai. */
    public static LocalDateTime startOf(MatchPost p) {
        try {
            String t = p.getStartTime() == null ? "" : p.getStartTime().trim();
            if (t.length() == 4) t = "0" + t; // 9:00 -> 09:00
            return LocalDateTime.parse(p.getPlayDate().trim() + "T" + t.substring(0, 5));
        } catch (Exception e) {
            return null;
        }
    }

    /** Kèo đã hủy hoặc đã xong. */
    public static boolean closed(MatchPost p) {
        return "CANCELLED".equals(p.getStatus()) || "COMPLETED".equals(p.getStatus());
    }

    /** Giờ kết thúc kèo (playDate + endTime), null nếu dữ liệu sai. Giờ kết thúc nhỏ hơn giờ bắt đầu = qua ngày hôm sau. */
    public static LocalDateTime endOf(MatchPost p) {
        LocalDateTime start = startOf(p);
        if (start == null) return null;
        try {
            String t = p.getEndTime() == null ? "" : p.getEndTime().trim();
            if (t.length() == 4) t = "0" + t;
            LocalDateTime end = LocalDateTime.parse(p.getPlayDate().trim() + "T" + t.substring(0, 5));
            return end.isAfter(start) ? end : end.plusDays(1);
        } catch (Exception e) {
            return start.plusHours(2);
        }
    }

    private static boolean started(MatchPost p) {
        LocalDateTime start = startOf(p);
        return start != null && !LocalDateTime.now().isBefore(start);
    }

    /** Bớt một người khỏi kèo; kèo đang FULL thì mở lại. */
    private void freeSlot(MatchPost post) {
        post.setCurrentPlayers(Math.max(1, post.getCurrentPlayers() - 1));
        if ("FULL".equals(post.getStatus()) && post.getCurrentPlayers() < post.getMaxPlayers()) {
            post.setStatus("OPEN");
        }
        matchPostRepository.save(post);
    }

    private static String cleanReason(Object raw) {
        if (raw == null) return null;
        String r = String.valueOf(raw).trim();
        if (r.isEmpty()) return null;
        return r.length() > 200 ? r.substring(0, 200) : r;
    }

    /**
     * Người đang đăng nhập rút khỏi kèo:
     * đơn PENDING -> hủy đơn (có thể xin lại sau); APPROVED -> rời kèo, trả lại 1 chỗ và báo chủ kèo.
     */
    @PostMapping("/{matchId}/leave")
    @Transactional
    public ResponseEntity<?> leaveMatch(@PathVariable Long matchId) {
        Long me = viewerId();
        if (me == null) return ResponseEntity.status(401).body(Map.of("error", "Vui lòng đăng nhập."));
        MatchPost post = matchPostRepository.findById(matchId).orElse(null);
        if (post == null) return ResponseEntity.status(404).body(Map.of("error", "Kèo này không còn tồn tại."));
        MatchParticipant mp = matchParticipantRepository.findByMatchIdAndUserId(matchId, me).orElse(null);
        if (mp == null) return ResponseEntity.badRequest().body(Map.of("error", "Bạn chưa xin tham gia kèo này."));

        String status = mp.getStatus();
        if (closed(post)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Kèo này đã kết thúc hoặc đã bị hủy."));
        }
        if (!"PENDING".equals(status) && !"APPROVED".equals(status)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Đơn này đã được xử lý, không thể hủy."));
        }
        if ("APPROVED".equals(status)) {
            // Thành viên đã duyệt tự rời: hoàn cọc theo mốc giờ lúc rời (24h / 2h)
            if (started(post)) {
                return ResponseEntity.badRequest().body(Map.of("error", "Kèo đã bắt đầu, không thể rời kèo."));
            }
            double ratio = MatchDepositService.refundRatio(post, LocalDateTime.now());
            double refunded = depositService.settleWithRatio(mp, post, ratio, "tự rời kèo");
            matchParticipantRepository.delete(mp);
            freeSlot(post);
            notificationService.notifyUser(
                    post.getHostId(),
                    "Thành viên đã rời kèo",
                    mp.getUserName() + " đã tự rời kèo '" + post.getTitle() + "'. Kèo còn "
                            + (post.getMaxPlayers() - post.getCurrentPlayers()) + " chỗ trống.",
                    "MATCHMAKING",
                    "S30",
                    post.getId());
            Map<String, Object> res = new LinkedHashMap<>();
            res.put("left", status);
            res.put("refundedAmount", refunded);
            res.put("entry", entryOf(post, me));
            return ResponseEntity.ok(res);
        }
        double refunded = depositService.refundFull(mp, post, "tự hủy đơn");
        matchParticipantRepository.delete(mp);
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("left", status);
        res.put("refundedAmount", refunded);
        res.put("entry", entryOf(post, me));
        return ResponseEntity.ok(res);
    }

    /** Số tiền cọc được hoàn nếu hủy đơn / rời kèo ngay bây giờ: {deposit, refundAmount, forfeitAmount, rule}. */
    @GetMapping("/{matchId}/leave-preview")
    public ResponseEntity<?> leavePreview(@PathVariable Long matchId) {
        Long me = viewerId();
        if (me == null) return ResponseEntity.status(401).body(Map.of("error", "Vui lòng đăng nhập."));
        MatchPost post = matchPostRepository.findById(matchId).orElse(null);
        if (post == null) return ResponseEntity.status(404).body(Map.of("error", "Kèo này không còn tồn tại."));
        MatchParticipant mp = matchParticipantRepository.findByMatchIdAndUserId(matchId, me).orElse(null);
        if (mp == null) return ResponseEntity.badRequest().body(Map.of("error", "Bạn chưa xin tham gia kèo này."));
        return ResponseEntity.ok(depositService.leavePreview(mp, post, LocalDateTime.now()));
    }

    /** Thành viên đã duyệt của kèo do người đang đăng nhập làm chủ (hoặc lỗi). */
    private Object hostTarget(Long matchId, Long participantId) {
        MatchPost post = matchPostRepository.findById(matchId).orElse(null);
        if (post == null) return ResponseEntity.status(404).body(Map.of("error", "Kèo này không còn tồn tại."));
        CurrentUser.requireSelfOrAdmin(post.getHostId());
        MatchParticipant mp = matchParticipantRepository.findById(participantId).orElse(null);
        if (mp == null || !matchId.equals(mp.getMatchId())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Người tham gia không thuộc kèo này."));
        }
        if (!"APPROVED".equals(mp.getStatus())) {
            return ResponseEntity.status(409).body(Map.of("error", "Thành viên này không còn trong kèo."));
        }
        if (closed(post) || started(post)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Kèo đã bắt đầu hoặc đã đóng."));
        }
        return new Object[]{post, mp};
    }

    /** Số tiền hoàn nếu chủ kèo mời thành viên ra: {deposit, fullRefund, policyRefund (theo mốc 24h / 2h lúc này)}. */
    @GetMapping("/{matchId}/participants/{participantId}/remove-preview")
    public ResponseEntity<?> removePreview(@PathVariable Long matchId, @PathVariable Long participantId) {
        Object t = hostTarget(matchId, participantId);
        if (t instanceof ResponseEntity<?> err) return err;
        MatchPost post = (MatchPost) ((Object[]) t)[0];
        MatchParticipant mp = (MatchParticipant) ((Object[]) t)[1];
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("deposit", MatchDepositService.heldAmount(mp));
        res.put("fullRefund", MatchDepositService.heldAmount(mp));
        res.put("policyRefund", MatchDepositService.refundFor(mp, MatchDepositService.refundRatio(post, LocalDateTime.now())));
        return ResponseEntity.ok(res);
    }

    /** Chủ kèo mời một thành viên đã duyệt ra khỏi kèo (trả lại chỗ, người đó không xin lại được). */
    @PostMapping("/{matchId}/participants/{participantId}/remove")
    @Transactional
    public ResponseEntity<?> removeParticipant(@PathVariable Long matchId,
                                               @PathVariable Long participantId,
                                               @RequestBody(required = false) Map<String, Object> body) {
        MatchPost post = matchPostRepository.findById(matchId).orElse(null);
        if (post == null) return ResponseEntity.status(404).body(Map.of("error", "Kèo này không còn tồn tại."));
        CurrentUser.requireSelfOrAdmin(post.getHostId());
        MatchParticipant mp = matchParticipantRepository.findById(participantId).orElse(null);
        if (mp == null || !matchId.equals(mp.getMatchId())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Người tham gia không thuộc kèo này."));
        }
        if (!"APPROVED".equals(mp.getStatus())) {
            return ResponseEntity.status(409).body(Map.of("error", "Chỉ mời ra được thành viên đã duyệt."));
        }
        if (closed(post) || started(post)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Kèo đã bắt đầu hoặc đã đóng, không thể mời ra."));
        }
        String reason = cleanReason(body == null ? null : body.get("reason"));
        boolean policy = "POLICY".equalsIgnoreCase(String.valueOf(body == null ? "" : body.get("refundMode")));
        mp.setStatus("REMOVED");
        mp.setRejectReason(reason);
        double ratio = policy ? MatchDepositService.refundRatio(post, LocalDateTime.now()) : 1.0;
        matchParticipantRepository.save(mp);
        double refunded = policy
                ? depositService.settleWithRatio(mp, post, ratio, "chủ kèo mời ra")
                : depositService.refundFull(mp, post, "chủ kèo mời ra");
        freeSlot(post);

        notificationService.notifyUser(
                mp.getUserId(),
                "Bạn không còn trong kèo giao lưu",
                "Chủ kèo '" + post.getTitle() + "' đã mời bạn ra khỏi kèo."
                        + (reason != null ? " Lý do: " + reason : " Bạn thử tìm kèo khác nhé.")
                        + (refunded > 0 ? " Đã hoàn " + MatchDepositService.format(refunded) + " cọc vào ví." : ""),
                "MATCHMAKING",
                "S15",
                post.getId()
        );
        return ResponseEntity.ok(Map.of("post", post, "participant", mp, "entry", entryOf(post, viewerId())));
    }

    /** Chủ kèo hủy kèo (trước giờ bắt đầu). Mọi người đã xin / đã được duyệt nhận thông báo kèm lý do. */
    @PostMapping("/{matchId}/cancel")
    @Transactional
    public ResponseEntity<?> cancelMatch(@PathVariable Long matchId,
                                         @RequestBody(required = false) Map<String, Object> body) {
        MatchPost post = matchPostRepository.findById(matchId).orElse(null);
        if (post == null) return ResponseEntity.status(404).body(Map.of("error", "Kèo này không còn tồn tại."));
        CurrentUser.requireSelfOrAdmin(post.getHostId());
        if (closed(post)) {
            return ResponseEntity.status(409).body(Map.of("error", "Kèo này đã kết thúc hoặc đã bị hủy."));
        }
        if (started(post)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Kèo đã bắt đầu, không thể hủy."));
        }
        String reason = cleanReason(body == null ? null : body.get("reason"));
        post.setStatus("CANCELLED");
        matchPostRepository.save(post);

        for (MatchParticipant mp : matchParticipantRepository.findByMatchIdOrderByIdAsc(matchId)) {
            if (!"PENDING".equals(mp.getStatus()) && !"APPROVED".equals(mp.getStatus())) continue;
            double refunded = depositService.refundFull(mp, post, "chủ kèo hủy kèo");
            notificationService.notifyUser(
                    mp.getUserId(),
                    "Kèo giao lưu đã bị hủy",
                    "Chủ kèo đã hủy kèo '" + post.getTitle() + "' (" + post.getPlayDate() + " " + post.getStartTime() + ")."
                            + (reason != null ? " Lý do: " + reason : " Bạn thử tìm kèo khác nhé.")
                            + (refunded > 0 ? " Đã hoàn " + MatchDepositService.format(refunded) + " cọc vào ví." : ""),
                    "MATCHMAKING",
                    "S30",
                    post.getId()
            );
        }
        reputationService.recompute(post.getHostId()); // tỉ lệ hủy kèo
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("post", post);
        res.put("entry", entryOf(post, viewerId()));
        return ResponseEntity.ok(res);
    }

    /** Người đang xem có được vào nhóm chat không (chủ kèo, admin hoặc thành viên đã duyệt). */
    private boolean canChat(MatchPost post, Long me) {
        if (me == null) return false;
        if (me.equals(post.getHostId())) return true;
        if (CurrentUser.get().map(u -> "ADMIN".equals(u.role())).orElse(false)) return true;
        return matchParticipantRepository.findByMatchIdAndUserId(post.getId(), me)
                .map(mp -> "APPROVED".equals(mp.getStatus())).orElse(false);
    }

    private static Map<String, Object> messageOf(MatchMessage m, Long me) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("id", m.getId());
        r.put("userId", m.getUserId());
        r.put("userName", m.getUserName());
        r.put("content", m.getContent());
        r.put("createdAt", m.getCreatedAt());
        r.put("mine", me != null && me.equals(m.getUserId()));
        return r;
    }

    /** Tin nhắn nhóm (cũ -> mới). Có afterId thì chỉ trả tin mới hơn (app hỏi định kỳ). */
    @GetMapping("/{matchId}/messages")
    public ResponseEntity<?> listMessages(@PathVariable Long matchId, @RequestParam(required = false) Long afterId) {
        Long me = viewerId();
        if (me == null) return ResponseEntity.status(401).body(Map.of("error", "Vui lòng đăng nhập."));
        MatchPost post = matchPostRepository.findById(matchId).orElse(null);
        if (post == null) return ResponseEntity.status(404).body(Map.of("error", "Kèo này không còn tồn tại."));
        if (!canChat(post, me)) {
            return ResponseEntity.status(403).body(Map.of("error", "Chỉ chủ kèo và thành viên đã duyệt mới xem được nhóm chat."));
        }
        List<MatchMessage> rows;
        if (afterId != null) {
            rows = matchMessageRepository.findByMatchIdAndIdGreaterThanOrderByIdAsc(matchId, afterId);
        } else {
            rows = new ArrayList<>(matchMessageRepository.findTop100ByMatchIdOrderByIdDesc(matchId));
            Collections.reverse(rows);
        }
        List<Map<String, Object>> items = new ArrayList<>();
        for (MatchMessage m : rows) items.add(messageOf(m, me));
        long lastReadBefore = chatService.lastRead(matchId, me);
        chatService.markSeen(post, me, LocalDateTime.now()); // đang mở chat = đã đọc, không báo tin mới
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("items", items);
        res.put("closed", closed(post));
        res.put("lastReadBefore", lastReadBefore);
        res.put("muted", chatService.muted(matchId, me));
        return ResponseEntity.ok(res);
    }

    @PostMapping("/{matchId}/messages")
    @Transactional
    public ResponseEntity<?> sendMessage(@PathVariable Long matchId, @RequestBody Map<String, Object> body) {
        Long me = viewerId();
        if (me == null) return ResponseEntity.status(401).body(Map.of("error", "Vui lòng đăng nhập."));
        MatchPost post = matchPostRepository.findById(matchId).orElse(null);
        if (post == null) return ResponseEntity.status(404).body(Map.of("error", "Kèo này không còn tồn tại."));
        if (!canChat(post, me)) {
            return ResponseEntity.status(403).body(Map.of("error", "Chỉ chủ kèo và thành viên đã duyệt mới nhắn được trong nhóm."));
        }
        if ("CANCELLED".equals(post.getStatus())) {
            return ResponseEntity.badRequest().body(Map.of("error", "Kèo đã bị hủy, nhóm chat đã đóng."));
        }
        String content = body.get("content") == null ? "" : String.valueOf(body.get("content")).trim();
        if (content.isEmpty()) return ResponseEntity.badRequest().body(Map.of("error", "Tin nhắn trống."));
        if (content.length() > 500) content = content.substring(0, 500);

        MatchMessage m = new MatchMessage();
        m.setMatchId(matchId);
        m.setUserId(me);
        m.setUserName(userRepository.findById(me).map(User::getFullName).orElse("Thành viên"));
        m.setContent(content);
        m.setCreatedAt(LocalDateTime.now().format(FMT));
        m = matchMessageRepository.save(m);
        chatService.onMessage(post, m, LocalDateTime.now());
        return ResponseEntity.ok(messageOf(m, me));
    }

    /** Tắt / bật thông báo nhóm chat của kèo {muted: true|false}. */
    @PatchMapping("/{matchId}/chat-settings")
    public ResponseEntity<?> chatSettings(@PathVariable Long matchId, @RequestBody Map<String, Object> body) {
        Long me = viewerId();
        if (me == null) return ResponseEntity.status(401).body(Map.of("error", "Vui lòng đăng nhập."));
        MatchPost post = matchPostRepository.findById(matchId).orElse(null);
        if (post == null) return ResponseEntity.status(404).body(Map.of("error", "Kèo này không còn tồn tại."));
        if (!canChat(post, me)) {
            return ResponseEntity.status(403).body(Map.of("error", "Chỉ chủ kèo và thành viên đã duyệt mới dùng được nhóm chat."));
        }
        boolean muted = Boolean.parseBoolean(String.valueOf(body.getOrDefault("muted", false)));
        chatService.setMuted(matchId, me, muted);
        return ResponseEntity.ok(Map.of("muted", muted));
    }

    /** Thành viên đã duyệt đánh giá chủ kèo: {rating 1-5, skillAccuracy ACCURATE|HIGHER|LOWER, tags[], comment}. */
    @PostMapping("/{matchId}/host-review")
    @Transactional
    public ResponseEntity<?> reviewHost(@PathVariable Long matchId, @RequestBody Map<String, Object> body) {
        Long me = viewerId();
        if (me == null) return ResponseEntity.status(401).body(Map.of("error", "Vui lòng đăng nhập."));
        MatchPost post = matchPostRepository.findById(matchId).orElse(null);
        if (post == null) return ResponseEntity.status(404).body(Map.of("error", "Kèo này không còn tồn tại."));
        String blocked = reputationService.reviewBlockReason(post, me, LocalDateTime.now());
        if (blocked != null) {
            int code = blocked.startsWith("Chỉ thành viên") || blocked.startsWith("Bạn không thể") ? 403 : 400;
            return ResponseEntity.status(code).body(Map.of("error", blocked));
        }
        int rating;
        try {
            rating = Integer.parseInt(String.valueOf(body.get("rating")));
        } catch (Exception e) {
            rating = 0;
        }
        String accuracy = String.valueOf(body.getOrDefault("skillAccuracy", "")).toUpperCase();
        if (rating < 1 || rating > 5) {
            return ResponseEntity.badRequest().body(Map.of("error", "Vui lòng chọn từ 1 đến 5 sao."));
        }
        if (!HostReputationService.ACCURACY.contains(accuracy)) {
            return ResponseEntity.badRequest().body(Map.of("error", "Vui lòng cho biết trình độ nhóm có đúng như mô tả không."));
        }
        List<String> tags = new ArrayList<>();
        if (body.get("tags") instanceof List<?> list) for (Object t : list) tags.add(String.valueOf(t));
        User rater = userRepository.findById(me).orElseThrow();
        Object comment = body.get("comment");
        HostReview r = reputationService.submit(post, rater, rating, accuracy, tags, comment == null ? null : String.valueOf(comment));

        Map<String, Object> res = new LinkedHashMap<>();
        res.put("review", HostReputationService.reviewMap(r));
        res.put("entry", entryOf(post, me));
        return ResponseEntity.ok(res);
    }

    /** Hồ sơ uy tín của một chủ kèo. */
    @GetMapping("/hosts/{hostId}/profile")
    public ResponseEntity<?> hostProfile(@PathVariable Long hostId) {
        return userRepository.findById(hostId)
                .<ResponseEntity<?>>map(h -> ResponseEntity.ok(reputationService.profile(h)))
                .orElseGet(() -> ResponseEntity.status(404).body(Map.of("error", "Không tìm thấy chủ kèo.")));
    }

    /** Số tiền trong body (null nếu không gửi / để trống). */
    private static Double moneyOrNull(Object v) {
        if (v == null || String.valueOf(v).isBlank()) return null;
        try {
            return Double.parseDouble(String.valueOf(v));
        } catch (NumberFormatException e) {
            return -1.0;
        }
    }
}
