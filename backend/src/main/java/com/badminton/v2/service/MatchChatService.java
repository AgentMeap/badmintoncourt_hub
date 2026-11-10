package com.badminton.v2.service;

import com.badminton.v2.entity.MatchChatRead;
import com.badminton.v2.entity.MatchMessage;
import com.badminton.v2.entity.MatchParticipant;
import com.badminton.v2.entity.MatchPost;
import com.badminton.v2.entity.NotificationItem;
import com.badminton.v2.repository.MatchChatReadRepository;
import com.badminton.v2.repository.MatchMessageRepository;
import com.badminton.v2.repository.MatchParticipantRepository;
import com.badminton.v2.repository.NotificationRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashSet;
import java.util.Set;

/**
 * Thông báo tin nhắn mới của nhóm chat kèo.
 * <ul>
 *   <li>Mỗi thành viên chỉ có MỘT thông báo chat chưa đọc cho mỗi kèo: tin mới thay thông báo cũ
 *       ("3 tin nhắn mới · Kèo X", "Minh: mai mang cầu nhé") và nằm đầu danh sách.</li>
 *   <li>Không báo cho: người gửi, người đang mở khung chat (app hỏi tin trong 15 giây gần nhất), người đã tắt thông báo nhóm.</li>
 *   <li>Mở chat (hỏi tin) = đã đọc tới tin mới nhất, thông báo chat của kèo được đánh dấu đã đọc.</li>
 * </ul>
 */
@Service
public class MatchChatService {

    public static final String TYPE = "CHAT";
    static final Duration ACTIVE_WINDOW = Duration.ofSeconds(15);
    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final MatchChatReadRepository readRepository;
    private final MatchMessageRepository messageRepository;
    private final MatchParticipantRepository participantRepository;
    private final NotificationRepository notificationRepository;
    private final PushService pushService;

    public MatchChatService(MatchChatReadRepository readRepository,
                            MatchMessageRepository messageRepository,
                            MatchParticipantRepository participantRepository,
                            NotificationRepository notificationRepository,
                            PushService pushService) {
        this.readRepository = readRepository;
        this.messageRepository = messageRepository;
        this.participantRepository = participantRepository;
        this.notificationRepository = notificationRepository;
        this.pushService = pushService;
    }

    private MatchChatRead stateOf(Long matchId, Long userId) {
        return readRepository.findByMatchIdAndUserId(matchId, userId)
                .orElseGet(() -> new MatchChatRead(matchId, userId));
    }

    /** Chủ kèo + thành viên đã duyệt. */
    private Set<Long> members(MatchPost post) {
        Set<Long> ids = new LinkedHashSet<>();
        ids.add(post.getHostId());
        for (MatchParticipant mp : participantRepository.findByMatchIdOrderByIdAsc(post.getId())) {
            if ("APPROVED".equals(mp.getStatus())) ids.add(mp.getUserId());
        }
        return ids;
    }

    private static boolean activeNow(MatchChatRead r, LocalDateTime now) {
        if (r.getLastSeenAt() == null) return false;
        try {
            return Duration.between(LocalDateTime.parse(r.getLastSeenAt(), FMT), now).compareTo(ACTIVE_WINDOW) <= 0;
        } catch (Exception e) {
            return false;
        }
    }

    /** Số tin chưa đọc của [userId] (không tính tin của chính mình). */
    public long unread(Long matchId, Long userId) {
        MatchChatRead r = readRepository.findByMatchIdAndUserId(matchId, userId).orElse(null);
        long after = r == null ? 0L : r.getLastReadMessageId();
        return messageRepository.countByMatchIdAndIdGreaterThanAndUserIdNot(matchId, after, userId);
    }

    public boolean muted(Long matchId, Long userId) {
        return readRepository.findByMatchIdAndUserId(matchId, userId).map(MatchChatRead::isMuted).orElse(false);
    }

    public long lastRead(Long matchId, Long userId) {
        return readRepository.findByMatchIdAndUserId(matchId, userId).map(MatchChatRead::getLastReadMessageId).orElse(0L);
    }

    /** Có tin mới: tạo / thay thông báo chat cho các thành viên khác. Trả về số người được báo. */
    @Transactional
    public int onMessage(MatchPost post, MatchMessage msg, LocalDateTime now) {
        // Người gửi coi như đã đọc tới tin của mình
        MatchChatRead mine = stateOf(post.getId(), msg.getUserId());
        mine.setLastReadMessageId(msg.getId());
        readRepository.save(mine);

        int notified = 0;
        String preview = msg.getContent().length() > 40 ? msg.getContent().substring(0, 40) + "…" : msg.getContent();
        for (Long uid : members(post)) {
            if (uid.equals(msg.getUserId())) continue;
            MatchChatRead r = stateOf(post.getId(), uid);
            if (r.isMuted() || activeNow(r, now)) continue;
            long count = messageRepository.countByMatchIdAndIdGreaterThanAndUserIdNot(post.getId(), r.getLastReadMessageId(), uid);
            // Gộp: xoá thông báo chat chưa đọc cũ của kèo này rồi tạo cái mới ở đầu danh sách
            notificationRepository.deleteAll(
                    notificationRepository.findByUserIdAndTypeAndReferenceIdAndIsReadFalse(uid, TYPE, post.getId()));
            NotificationItem saved = notificationRepository.save(new NotificationItem(
                    uid,
                    (count > 1 ? count + " tin nhắn mới" : "Tin nhắn mới") + " · " + post.getTitle(),
                    msg.getUserName() + ": " + preview,
                    TYPE,
                    "S30",
                    post.getId(),
                    false,
                    now.format(FMT)));
            pushService.pushAsync(saved); // trên máy: tin cùng kèo thay nhau (tag chat-<id>)
            notified++;
        }
        return notified;
    }

    /** Thành viên mở / đang xem chat: đã đọc tới tin mới nhất, đánh dấu đọc thông báo chat của kèo. */
    @Transactional
    public void markSeen(MatchPost post, Long userId, LocalDateTime now) {
        MatchChatRead r = stateOf(post.getId(), userId);
        messageRepository.findTopByMatchIdOrderByIdDesc(post.getId())
                .ifPresent(m -> r.setLastReadMessageId(Math.max(r.getLastReadMessageId(), m.getId())));
        r.setLastSeenAt(now.format(FMT));
        readRepository.save(r);
        for (NotificationItem n : notificationRepository.findByUserIdAndTypeAndReferenceIdAndIsReadFalse(userId, TYPE, post.getId())) {
            n.setRead(true);
            notificationRepository.save(n);
        }
    }

    @Transactional
    public void setMuted(Long matchId, Long userId, boolean muted) {
        MatchChatRead r = stateOf(matchId, userId);
        r.setMuted(muted);
        readRepository.save(r);
    }
}
