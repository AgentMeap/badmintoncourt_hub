package com.badminton.v2.service;

import com.badminton.v2.controller.MatchmakingController;
import com.badminton.v2.entity.HostReview;
import com.badminton.v2.entity.MatchParticipant;
import com.badminton.v2.entity.MatchPost;
import com.badminton.v2.entity.User;
import com.badminton.v2.repository.HostReviewRepository;
import com.badminton.v2.repository.MatchParticipantRepository;
import com.badminton.v2.repository.MatchPostRepository;
import com.badminton.v2.repository.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;

/**
 * Uy tín chủ kèo: thành viên đã duyệt đánh giá chủ kèo sau khi kèo kết thúc (trong 7 ngày, sửa được).
 * Chỉ số được tính lại và lưu trên User để bảng tin đọc nhanh:
 * <ul>
 *   <li>score = (3 × 4.0 + tổng sao) / (3 + số đánh giá): chủ kèo mới có 1 đánh giá 5 sao không vượt ngay người nhiều đánh giá.</li>
 *   <li>skillAccuracy = tỉ lệ "đúng trình độ"; skillBias = hướng lệch phổ biến (HIGHER / LOWER).</li>
 *   <li>cancelRate = kèo bị hủy ÷ (kèo đã xong + bị hủy), chỉ tính kèo có người xin.</li>
 * </ul>
 * Huy hiệu TRUSTED: ≥ 5 đánh giá, điểm ≥ 4.5, đúng trình độ ≥ 80%, hủy &lt; 10%.
 * Cảnh báo SKILL_MISMATCH: ≥ 5 đánh giá và đúng trình độ &lt; 50%.
 */
@Service
public class HostReputationService {

    public static final Duration REVIEW_WINDOW = Duration.ofDays(7);
    public static final List<String> ACCURACY = List.of("ACCURATE", "HIGHER", "LOWER");
    public static final List<String> TAGS = List.of(
            "Đúng giờ", "Vui vẻ", "Chia tiền rõ ràng", "Cầu tốt", "Sân như mô tả",
            "Đến muộn", "Thiếu người", "Đổi giờ/đổi sân", "Thu thêm tiền");
    static final double PRIOR_MEAN = 4.0;
    static final int PRIOR_WEIGHT = 3;
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final HostReviewRepository reviewRepository;
    private final MatchPostRepository matchPostRepository;
    private final MatchParticipantRepository participantRepository;
    private final UserRepository userRepository;

    public HostReputationService(HostReviewRepository reviewRepository,
                                 MatchPostRepository matchPostRepository,
                                 MatchParticipantRepository participantRepository,
                                 UserRepository userRepository) {
        this.reviewRepository = reviewRepository;
        this.matchPostRepository = matchPostRepository;
        this.participantRepository = participantRepository;
        this.userRepository = userRepository;
    }

    /** Lý do không được đánh giá (null = được). */
    public String reviewBlockReason(MatchPost post, Long raterId, LocalDateTime now) {
        if (raterId == null) return "Vui lòng đăng nhập.";
        if (raterId.equals(post.getHostId())) return "Bạn không thể tự đánh giá kèo của mình.";
        if (!"COMPLETED".equals(post.getStatus())) return "Chỉ đánh giá được sau khi kèo kết thúc.";
        boolean member = participantRepository.findByMatchIdAndUserId(post.getId(), raterId)
                .map(mp -> "APPROVED".equals(mp.getStatus())).orElse(false);
        if (!member) return "Chỉ thành viên đã được duyệt vào kèo mới đánh giá được chủ kèo.";
        LocalDateTime end = MatchmakingController.endOf(post);
        if (end != null && now.isAfter(end.plus(REVIEW_WINDOW))) return "Đã quá 7 ngày sau khi kèo kết thúc.";
        return null;
    }

    /** Tạo hoặc sửa đánh giá rồi tính lại uy tín chủ kèo. */
    @Transactional
    public HostReview submit(MatchPost post, User rater, int rating, String skillAccuracy, List<String> tags, String comment) {
        if (rating < 1 || rating > 5) throw new IllegalArgumentException("rating");
        if (!ACCURACY.contains(skillAccuracy)) throw new IllegalArgumentException("skillAccuracy");
        String now = LocalDateTime.now().format(FMT);
        HostReview r = reviewRepository.findByMatchIdAndRaterId(post.getId(), rater.getId()).orElseGet(() -> {
            HostReview n = new HostReview();
            n.setMatchId(post.getId());
            n.setRaterId(rater.getId());
            n.setCreatedAt(now);
            return n;
        });
        r.setMatchTitle(post.getTitle());
        r.setHostId(post.getHostId());
        r.setRaterName(rater.getFullName());
        r.setRating(rating);
        r.setSkillAccuracy(skillAccuracy);
        List<String> clean = tags == null ? List.of()
                : tags.stream().map(String::trim).filter(TAGS::contains).distinct().toList();
        r.setTags(String.join(", ", clean));
        String c = comment == null ? "" : comment.trim();
        r.setComment(c.isEmpty() ? null : (c.length() > 300 ? c.substring(0, 300) : c));
        r.setUpdatedAt(now);
        r = reviewRepository.save(r);
        recompute(post.getHostId());
        return r;
    }

    /** Tính lại toàn bộ chỉ số uy tín của một chủ kèo và lưu lên User. */
    @Transactional
    public void recompute(Long hostId) {
        User host = userRepository.findById(hostId).orElse(null);
        if (host == null) return;
        List<HostReview> reviews = reviewRepository.findByHostIdOrderByIdDesc(hostId);
        int n = reviews.size();
        double sum = reviews.stream().mapToInt(HostReview::getRating).sum();
        long accurate = reviews.stream().filter(r -> "ACCURATE".equals(r.getSkillAccuracy())).count();
        long higher = reviews.stream().filter(r -> "HIGHER".equals(r.getSkillAccuracy())).count();
        long lower = reviews.stream().filter(r -> "LOWER".equals(r.getSkillAccuracy())).count();

        int completed = 0, cancelled = 0;
        for (MatchPost p : matchPostRepository.findByHostIdOrderByIdDesc(hostId)) {
            boolean hadRequests = !participantRepository.findByMatchIdOrderByIdAsc(p.getId()).isEmpty();
            if ("COMPLETED".equals(p.getStatus())) completed++;
            else if ("CANCELLED".equals(p.getStatus()) && hadRequests) cancelled++;
        }
        host.setHostReviewCount(n);
        host.setHostRatingScore(n == 0 ? null : round2((PRIOR_WEIGHT * PRIOR_MEAN + sum) / (PRIOR_WEIGHT + n)));
        host.setHostSkillAccuracy(n == 0 ? null : round2((double) accurate / n));
        host.setHostSkillBias(higher + lower == 0 ? null : higher >= lower ? "HIGHER" : "LOWER");
        host.setHostCancelRate(completed + cancelled == 0 ? null : round2((double) cancelled / (completed + cancelled)));
        host.setHostCompletedCount(completed);
        userRepository.save(host);
    }

    private static double round2(double v) {
        return Math.round(v * 100.0) / 100.0;
    }

    /** Huy hiệu theo chỉ số: TRUSTED, SKILL_MISMATCH hoặc null. */
    public static String badgeOf(User h) {
        int n = h.getHostReviewCount() == null ? 0 : h.getHostReviewCount();
        if (n < 5) return null;
        double acc = h.getHostSkillAccuracy() == null ? 0 : h.getHostSkillAccuracy();
        if (acc < 0.5) return "SKILL_MISMATCH";
        double score = h.getHostRatingScore() == null ? 0 : h.getHostRatingScore();
        double cancel = h.getHostCancelRate() == null ? 0 : h.getHostCancelRate();
        if (score >= 4.5 && acc >= 0.8 && cancel < 0.1) return "TRUSTED";
        return null;
    }

    /** Tóm tắt uy tín để gắn vào thẻ kèo: {score, count, skillAccuracy, skillBias, cancelRate, completed, badge}. */
    public static Map<String, Object> summaryOf(User h) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("count", h.getHostReviewCount() == null ? 0 : h.getHostReviewCount());
        m.put("score", h.getHostRatingScore());
        m.put("skillAccuracy", h.getHostSkillAccuracy());
        m.put("skillBias", h.getHostSkillBias());
        m.put("cancelRate", h.getHostCancelRate());
        m.put("completed", h.getHostCompletedCount() == null ? 0 : h.getHostCompletedCount());
        m.put("badge", badgeOf(h));
        return m;
    }

    public static Map<String, Object> reviewMap(HostReview r) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", r.getId());
        m.put("matchId", r.getMatchId());
        m.put("matchTitle", r.getMatchTitle());
        m.put("raterId", r.getRaterId());
        m.put("raterName", r.getRaterName());
        m.put("rating", r.getRating());
        m.put("skillAccuracy", r.getSkillAccuracy());
        m.put("tags", r.getTags() == null || r.getTags().isBlank() ? List.of() : List.of(r.getTags().split(",\\s*")));
        m.put("comment", r.getComment());
        m.put("createdAt", r.getCreatedAt());
        m.put("updatedAt", r.getUpdatedAt());
        return m;
    }

    /** Hồ sơ chủ kèo: tóm tắt + 20 đánh giá gần nhất (hiện tên người đánh giá). */
    public Map<String, Object> profile(User host) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("hostId", host.getId());
        m.put("hostName", host.getFullName());
        m.put("hostSkill", host.getSkillLevel());
        m.put("summary", summaryOf(host));
        List<Map<String, Object>> list = new ArrayList<>();
        for (HostReview r : reviewRepository.findTop20ByHostIdOrderByIdDesc(host.getId())) list.add(reviewMap(r));
        m.put("reviews", list);
        m.put("tags", TAGS);
        return m;
    }

    public Optional<HostReview> reviewOf(Long matchId, Long raterId) {
        return raterId == null ? Optional.empty() : reviewRepository.findByMatchIdAndRaterId(matchId, raterId);
    }

    /** Thành viên đã duyệt của kèo (để gửi lời mời đánh giá). */
    public List<MatchParticipant> approvedMembers(MatchPost post) {
        return participantRepository.findByMatchIdOrderByIdAsc(post.getId()).stream()
                .filter(mp -> "APPROVED".equals(mp.getStatus())).toList();
    }
}
