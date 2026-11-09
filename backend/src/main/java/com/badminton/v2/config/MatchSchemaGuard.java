package com.badminton.v2.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

/**
 * Chặn ở tầng database một người có 2 đơn trong cùng một kèo (bấm "Xin tham gia" 2 lần liên tiếp
 * sẽ không bị trừ cọc 2 lần). Hibernate ddl-auto=update không tự thêm ràng buộc này cho SQLite nên tạo ở đây.
 */
@Component
public class MatchSchemaGuard {

    private static final Logger log = LoggerFactory.getLogger(MatchSchemaGuard.class);
    private final JdbcTemplate jdbc;

    public MatchSchemaGuard(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void ensureIndexes() {
        try {
            jdbc.execute("CREATE UNIQUE INDEX IF NOT EXISTS ux_match_participant_user "
                    + "ON match_participants(match_id, user_id)");
        } catch (Exception e) {
            // Dữ liệu cũ đang có bản trùng: vẫn chạy bình thường, kiểm tra trong code vẫn chặn trùng
            log.warn("Không tạo được unique index match_participants(match_id, user_id): {}", e.getMessage());
        }
    }
}
