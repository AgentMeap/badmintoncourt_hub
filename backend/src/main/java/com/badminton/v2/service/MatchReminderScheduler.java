package com.badminton.v2.service;

import com.badminton.v2.controller.MatchmakingController;
import com.badminton.v2.entity.MatchParticipant;
import com.badminton.v2.entity.MatchPost;
import com.badminton.v2.repository.MatchParticipantRepository;
import com.badminton.v2.repository.MatchPostRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.LinkedHashSet;
import java.util.Set;

/**
 * Việc chạy nền của kèo giao lưu (5 phút / lần):
 * <ul>
 *   <li>Nhắc lịch: khoảng 2 giờ trước giờ đánh, báo chủ kèo + thành viên đã duyệt (mở S30). Mỗi kèo nhắc một lần.</li>
 *   <li>Đóng kèo: kèo OPEN / FULL đã qua giờ kết thúc chuyển sang COMPLETED, không còn trên bảng tin;
 *   <li>(đóng kèo) tiền cọc đang giữ hộ được chuyển cho chủ kèo (đơn chưa duyệt thì hoàn lại); mời thành viên đánh giá chủ kèo.</li>
 * </ul>
 */
@Component
public class MatchReminderScheduler {

    private static final Logger log = LoggerFactory.getLogger(MatchReminderScheduler.class);
    /** Nhắc khi giờ đánh còn trong khoảng này. */
    static final Duration LEAD = Duration.ofHours(2);

    private final MatchPostRepository matchPostRepository;
    private final MatchParticipantRepository matchParticipantRepository;
    private final NotificationService notificationService;
    private final MatchDepositService depositService;
    private final HostReputationService reputationService;

    public MatchReminderScheduler(MatchPostRepository matchPostRepository,
                                  MatchParticipantRepository matchParticipantRepository,
                                  NotificationService notificationService,
                                  MatchDepositService depositService,
                                  HostReputationService reputationService) {
        this.matchPostRepository = matchPostRepository;
        this.matchParticipantRepository = matchParticipantRepository;
        this.notificationService = notificationService;
        this.depositService = depositService;
        this.reputationService = reputationService;
    }

    @Scheduled(initialDelay = 60_000, fixedRate = 300_000)
    public void run() {
        LocalDateTime now = LocalDateTime.now();
        int sent = sendDueReminders(now);
        if (sent > 0) log.info("Đã nhắc lịch {} kèo giao lưu", sent);
        int closed = closeFinished(now);
        if (closed > 0) log.info("Đã đóng {} kèo giao lưu đã qua giờ", closed);
    }

    /** Gửi nhắc cho các kèo bắt đầu trong (now, now + 2h]. Trả về số kèo đã nhắc. */
    @Transactional
    public int sendDueReminders(LocalDateTime now) {
        int count = 0;
        for (MatchPost p : matchPostRepository.findAllByOrderByIdDesc()) {
            if (Boolean.TRUE.equals(p.getReminderSent())) continue;
            if (!"OPEN".equals(p.getStatus()) && !"FULL".equals(p.getStatus())) continue;
            LocalDateTime start = MatchmakingController.startOf(p);
            if (start == null || !start.isAfter(now) || start.isAfter(now.plus(LEAD))) continue;

            Set<Long> receivers = new LinkedHashSet<>();
            receivers.add(p.getHostId());
            for (MatchParticipant mp : matchParticipantRepository.findByMatchIdOrderByIdAsc(p.getId())) {
                if ("APPROVED".equals(mp.getStatus())) receivers.add(mp.getUserId());
            }
            long minutes = Duration.between(now, start).toMinutes();
            String when = minutes >= 60 ? (minutes / 60) + " giờ " + (minutes % 60 > 0 ? (minutes % 60) + " phút " : "")
                    : minutes + " phút ";
            for (Long uid : receivers) {
                notificationService.notifyUser(
                        uid,
                        "Sắp tới giờ đánh kèo giao lưu",
                        "Kèo '" + p.getTitle() + "' bắt đầu sau khoảng " + when + "(" + p.getStartTime() + ") tại "
                                + p.getVenueName() + ". Nhớ đến đúng giờ nhé!",
                        "MATCHMAKING",
                        "S30",
                        p.getId()
                );
            }
            p.setReminderSent(true);
            matchPostRepository.save(p);
            count++;
        }
        return count;
    }

    /** Chuyển kèo OPEN / FULL đã qua giờ kết thúc sang COMPLETED. Trả về số kèo đã đóng. */
    @Transactional
    public int closeFinished(LocalDateTime now) {
        int count = 0;
        for (MatchPost p : matchPostRepository.findAllByOrderByIdDesc()) {
            if (!"OPEN".equals(p.getStatus()) && !"FULL".equals(p.getStatus())) continue;
            LocalDateTime end = MatchmakingController.endOf(p);
            if (end == null || end.isAfter(now)) continue;
            p.setStatus("COMPLETED");
            matchPostRepository.save(p);
            depositService.settleCompleted(p); // trả cọc cho chủ kèo, hoàn đơn chưa duyệt
            reputationService.recompute(p.getHostId()); // số kèo đã tổ chức xong
            for (MatchParticipant mp : reputationService.approvedMembers(p)) {
                notificationService.notifyUser(
                        mp.getUserId(),
                        "Đánh giá chủ kèo " + p.getHostName(),
                        "Kèo '" + p.getTitle() + "' đã kết thúc. Chủ kèo tổ chức thế nào, trình độ nhóm có đúng mô tả không? "
                                + "Bạn có 7 ngày để đánh giá.",
                        "MATCHMAKING",
                        "S30",
                        p.getId()
                );
            }
            count++;
        }
        return count;
    }
}
