package com.badminton.v2.service;

import com.badminton.v2.controller.MatchmakingController;
import com.badminton.v2.entity.MatchParticipant;
import com.badminton.v2.entity.MatchPost;
import com.badminton.v2.entity.User;
import com.badminton.v2.entity.WalletTransaction;
import com.badminton.v2.repository.MatchParticipantRepository;
import com.badminton.v2.repository.UserRepository;
import com.badminton.v2.repository.WalletTransactionRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Cọc kèo giao lưu qua ví. Mọi lần chuyển tiền cọc đều đi qua lớp này.
 * <ul>
 *   <li>Xin tham gia: trừ ví ngay, giữ hộ (HELD).</li>
 *   <li>Bị từ chối / tự hủy đơn / bị mời ra / chủ kèo hủy kèo: hoàn 100%.</li>
 *   <li>Thành viên đã duyệt rời kèo: còn ≥ 24h hoàn 100%; 2–24h hoàn 50% (50% cho chủ kèo); &lt; 2h mất cọc.</li>
 *   <li>Kèo kết thúc: cọc của thành viên đã duyệt chuyển cho chủ kèo; đơn còn chờ duyệt được hoàn.</li>
 * </ul>
 * Mỗi khoản chỉ được xử lý khi đang HELD, nên gọi lại (VD tác vụ nền chạy 2 lần) không chuyển tiền 2 lần.
 */
@Service
public class MatchDepositService {

    public static final String HOLD = "MATCH_DEPOSIT_HOLD";
    public static final String REFUND = "MATCH_DEPOSIT_REFUND";
    public static final String PAYOUT = "MATCH_DEPOSIT_PAYOUT";

    static final Duration FULL_REFUND_BEFORE = Duration.ofHours(24);
    static final Duration HALF_REFUND_BEFORE = Duration.ofHours(2);
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final UserRepository userRepository;
    private final WalletTransactionRepository walletTransactionRepository;
    private final MatchParticipantRepository matchParticipantRepository;
    private final NotificationService notificationService;

    public MatchDepositService(UserRepository userRepository,
                               WalletTransactionRepository walletTransactionRepository,
                               MatchParticipantRepository matchParticipantRepository,
                               NotificationService notificationService) {
        this.userRepository = userRepository;
        this.walletTransactionRepository = walletTransactionRepository;
        this.matchParticipantRepository = matchParticipantRepository;
        this.notificationService = notificationService;
    }

    /** Số cọc mỗi người: phí × % rồi làm tròn lên bội số 1.000đ. */
    public static double depositFor(double feePerPlayer, int percent) {
        if (percent <= 0 || feePerPlayer <= 0) return 0;
        return Math.ceil(feePerPlayer * percent / 100.0 / 1000.0) * 1000.0;
    }

    public static double depositOf(MatchPost p) {
        return p.getDepositAmount() == null ? 0 : p.getDepositAmount();
    }

    private static double amountOf(MatchParticipant mp) {
        return mp.getDepositAmount() == null ? 0 : mp.getDepositAmount();
    }

    private static boolean held(MatchParticipant mp) {
        return "HELD".equals(mp.getDepositStatus()) && amountOf(mp) > 0;
    }

    private static String vnd(double v) {
        return String.format("%,d", (long) v).replace(',', '.') + "đ";
    }

    /** Cộng / trừ ví một người và ghi lịch sử giao dịch. */
    private void move(Long userId, double amount, String type, String title) {
        User u = userRepository.findById(userId).orElseThrow();
        u.setWalletBalance(u.getWalletBalance() + amount);
        userRepository.save(u);
        walletTransactionRepository.save(new WalletTransaction(
                userId, title, amount, type, u.getWalletBalance(), LocalDateTime.now().format(FMT)));
    }

    /** Ví có đủ cọc không (dùng trước khi tạo đơn). */
    public boolean canAfford(User user, MatchPost post) {
        return user.getWalletBalance() + 1e-6 >= depositOf(post);
    }

    /** Trừ cọc khi xin tham gia. Kèo không cọc thì chỉ đánh dấu NONE. */
    @Transactional
    public void hold(MatchParticipant mp, MatchPost post) {
        double amount = depositOf(post);
        mp.setRefundedAmount(0.0);
        if (amount <= 0) {
            mp.setDepositAmount(0.0);
            mp.setDepositStatus("NONE");
            matchParticipantRepository.save(mp);
            return;
        }
        move(mp.getUserId(), -amount, HOLD, "Cọc kèo '" + post.getTitle() + "' (giữ hộ đến khi kèo kết thúc)");
        mp.setDepositAmount(amount);
        mp.setDepositStatus("HELD");
        matchParticipantRepository.save(mp);
    }

    /** Hoàn 100% cọc (bị từ chối, tự hủy đơn, bị mời ra, chủ kèo hủy kèo, đơn chưa duyệt khi kèo kết thúc). */
    @Transactional
    public double refundFull(MatchParticipant mp, MatchPost post, String why) {
        if (!held(mp)) return 0;
        double amount = amountOf(mp);
        move(mp.getUserId(), amount, REFUND, "Hoàn cọc kèo '" + post.getTitle() + "' (" + why + ")");
        mp.setRefundedAmount(amount);
        mp.setDepositStatus("REFUNDED");
        matchParticipantRepository.save(mp);
        return amount;
    }

    /** Tỉ lệ hoàn khi thành viên đã duyệt tự rời kèo lúc [now]. */
    public static double refundRatio(MatchPost post, LocalDateTime now) {
        LocalDateTime start = MatchmakingController.startOf(post);
        if (start == null) return 1.0;
        Duration left = Duration.between(now, start);
        if (left.compareTo(FULL_REFUND_BEFORE) >= 0) return 1.0;
        if (left.compareTo(HALF_REFUND_BEFORE) >= 0) return 0.5;
        return 0.0;
    }

    /** Xem trước số tiền hoàn nếu rời / hủy đơn ngay bây giờ (để app hiện trước khi xác nhận). */
    public Map<String, Object> leavePreview(MatchParticipant mp, MatchPost post, LocalDateTime now) {
        double amount = amountOf(mp);
        double ratio = !held(mp) ? 0 : "APPROVED".equals(mp.getStatus()) ? refundRatio(post, now) : 1.0;
        double refund = Math.round(amount * ratio / 1000.0) * 1000.0;
        if (refund > amount) refund = amount;
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("deposit", held(mp) ? amount : 0);
        r.put("refundAmount", held(mp) ? refund : 0);
        r.put("forfeitAmount", held(mp) ? amount - refund : 0);
        r.put("rule", !held(mp) ? "Kèo không cọc."
                : !"APPROVED".equals(mp.getStatus()) ? "Đơn chưa được duyệt: hoàn đủ cọc."
                : ratio >= 1 ? "Còn từ 24 giờ trở lên: hoàn đủ cọc."
                : ratio > 0 ? "Còn 2–24 giờ: hoàn 50%, 50% còn lại chuyển cho chủ kèo."
                : "Còn dưới 2 giờ: không hoàn cọc, tiền cọc chuyển cho chủ kèo.");
        return r;
    }

    /** Thành viên đã duyệt rời kèo: hoàn theo mốc giờ, phần còn lại trả chủ kèo. Trả về số tiền đã hoàn. */
    @Transactional
    public double settleLeave(MatchParticipant mp, MatchPost post, LocalDateTime now) {
        if (!held(mp)) return 0;
        double amount = amountOf(mp);
        double refund = ((Number) leavePreview(mp, post, now).get("refundAmount")).doubleValue();
        double forfeit = amount - refund;
        if (refund > 0) {
            move(mp.getUserId(), refund, REFUND, "Hoàn cọc kèo '" + post.getTitle() + "' (rời kèo)");
        }
        if (forfeit > 0) {
            move(post.getHostId(), forfeit, PAYOUT, "Nhận cọc của " + mp.getUserName() + " (rời kèo sát giờ) – kèo '" + post.getTitle() + "'");
            notificationService.notifyUser(post.getHostId(), "Bạn nhận " + vnd(forfeit) + " tiền cọc",
                    mp.getUserName() + " rời kèo '" + post.getTitle() + "' sát giờ nên tiền cọc được chuyển cho bạn.",
                    "WALLET", "S18", post.getId());
        }
        mp.setRefundedAmount(refund);
        mp.setDepositStatus(refund >= amount ? "REFUNDED" : refund > 0 ? "PARTIAL" : "FORFEITED");
        matchParticipantRepository.save(mp);
        return refund;
    }

    /** Kèo kết thúc: chuyển cọc của thành viên đã duyệt cho chủ kèo, hoàn cọc đơn còn chờ duyệt. Trả về tổng đã trả chủ kèo. */
    @Transactional
    public double settleCompleted(MatchPost post) {
        double paid = 0;
        int people = 0;
        for (MatchParticipant mp : matchParticipantRepository.findByMatchIdOrderByIdAsc(post.getId())) {
            if (!held(mp)) continue;
            if ("APPROVED".equals(mp.getStatus())) {
                paid += amountOf(mp);
                people++;
                mp.setDepositStatus("RELEASED");
                matchParticipantRepository.save(mp);
            } else {
                double back = refundFull(mp, post, "kèo đã kết thúc khi đơn chưa được duyệt");
                if (back > 0) {
                    notificationService.notifyUser(mp.getUserId(), "Đã hoàn " + vnd(back) + " cọc",
                            "Kèo '" + post.getTitle() + "' đã kết thúc khi đơn của bạn chưa được duyệt.",
                            "WALLET", "S18", post.getId());
                }
            }
        }
        if (paid > 0) {
            move(post.getHostId(), paid, PAYOUT, "Nhận cọc " + people + " người – kèo '" + post.getTitle() + "'");
            notificationService.notifyUser(post.getHostId(), "Bạn nhận " + vnd(paid) + " tiền cọc",
                    "Kèo '" + post.getTitle() + "' đã kết thúc. Tiền cọc của " + people + " thành viên đã vào ví của bạn.",
                    "WALLET", "S18", post.getId());
        }
        return paid;
    }

    /** Tổng cọc đang giữ hộ của một kèo (hiện cho chủ kèo). */
    public double heldTotal(MatchPost post) {
        return matchParticipantRepository.findByMatchIdOrderByIdAsc(post.getId()).stream()
                .filter(mp -> held(mp) && "APPROVED".equals(mp.getStatus()))
                .mapToDouble(MatchDepositService::amountOf).sum();
    }

    public static String format(double v) {
        return vnd(v);
    }
}
