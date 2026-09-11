package com.lumen.api.notification;

import com.lumen.api.common.ApiException;
import com.lumen.api.oss.OssService;
import com.lumen.api.user.UserService.User;
import java.sql.Timestamp;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class NotificationService {
    private final JdbcTemplate jdbc;
    private final OssService oss;

    public NotificationService(JdbcTemplate jdbc, OssService oss) {
        this.jdbc = jdbc;
        this.oss = oss;
    }

    public void create(
            String recipientId,
            String actorId,
            String type,
            UUID targetPostId,
            UUID sourcePostId
    ) {
        if (recipientId == null || actorId == null || recipientId.equals(actorId)) {
            return;
        }
        jdbc.update(
                """
                INSERT INTO notifications (
                  id, recipient_id, actor_id, type, target_post_id, source_post_id
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                UUID.randomUUID().toString(),
                recipientId,
                actorId,
                type,
                targetPostId == null ? null : targetPostId.toString(),
                sourcePostId == null ? null : sourcePostId.toString()
        );
    }

    public List<NotificationItem> list(User user, int limit, int offset) {
        return jdbc.query(
                """
                SELECT n.id, n.type, n.target_post_id, n.source_post_id,
                       n.read_at, n.created_at,
                       u.id AS actor_id, u.nickname AS actor_name,
                       u.avatar_object_key, u.avatar_url,
                       COALESCE(source.title, target.title, '') AS post_title
                FROM notifications n
                JOIN users u ON u.id = n.actor_id
                LEFT JOIN posts target ON target.id = n.target_post_id
                LEFT JOIN posts source ON source.id = n.source_post_id
                WHERE n.recipient_id = ?
                ORDER BY n.created_at DESC
                LIMIT ? OFFSET ?
                """,
                (rs, rowNum) -> {
                    String type = rs.getString("type");
                    String actorName = rs.getString("actor_name");
                    String postTitle = rs.getString("post_title");
                    String title = switch (type) {
                        case "ASSIGNMENT" -> "收到新作业";
                        case "COMMENT" -> "收到新评论";
                        case "LIKE" -> "作品获得点赞";
                        case "FOLLOW" -> "有新的关注";
                        default -> "新通知";
                    };
                    String body = switch (type) {
                        case "ASSIGNMENT" -> actorName + " 提交了「" + postTitle + "」的复刻作业";
                        case "COMMENT" -> actorName + " 评论了「" + postTitle + "」";
                        case "LIKE" -> actorName + " 赞了「" + postTitle + "」";
                        case "FOLLOW" -> actorName + " 关注了你";
                        default -> actorName + " 与你产生了新的互动";
                    };
                    return new NotificationItem(
                            UUID.fromString(rs.getString("id")),
                            type,
                            title,
                            body,
                            new Actor(
                                    rs.getString("actor_id"),
                                    actorName,
                                    first(
                                            oss.createDownloadUrl(rs.getString("avatar_object_key")),
                                            rs.getString("avatar_url")
                                    )
                            ),
                            uuid(rs.getString("target_post_id")),
                            uuid(rs.getString("source_post_id")),
                            rs.getTimestamp("read_at") != null,
                            instant(rs.getTimestamp("created_at"))
                    );
                },
                user.id(),
                Math.min(Math.max(limit, 1), 50),
                Math.max(offset, 0)
        );
    }

    public int unreadCount(User user) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM notifications WHERE recipient_id = ? AND read_at IS NULL",
                Integer.class,
                user.id()
        );
        return count == null ? 0 : count;
    }

    public void markRead(User user, UUID notificationId) {
        int updated = jdbc.update(
                """
                UPDATE notifications SET read_at = COALESCE(read_at, CURRENT_TIMESTAMP(3))
                WHERE id = ? AND recipient_id = ?
                """,
                notificationId.toString(),
                user.id()
        );
        if (updated == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "通知不存在");
        }
    }

    public void markAllRead(User user) {
        jdbc.update(
                """
                UPDATE notifications SET read_at = CURRENT_TIMESTAMP(3)
                WHERE recipient_id = ? AND read_at IS NULL
                """,
                user.id()
        );
    }

    private UUID uuid(String value) {
        return value == null ? null : UUID.fromString(value);
    }

    private String instant(Timestamp value) {
        return value == null ? null : value.toInstant().toString();
    }

    private String first(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }

    public record Actor(String id, String name, String avatarUrl) {}

    public record NotificationItem(
            UUID id,
            String type,
            String title,
            String body,
            Actor actor,
            UUID targetPostId,
            UUID sourcePostId,
            boolean read,
            String createdAt
    ) {}
}
