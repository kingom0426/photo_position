package com.lumen.api.post;

import com.lumen.api.common.ApiException;
import com.lumen.api.post.PostDtos.CommentAuthor;
import com.lumen.api.post.PostDtos.CommentResponse;
import com.lumen.api.post.PostDtos.CreateImage;
import com.lumen.api.post.PostDtos.CreateLocation;
import com.lumen.api.post.PostDtos.CreateMetadata;
import com.lumen.api.post.PostDtos.CreatePostRequest;
import com.lumen.api.post.PostDtos.LikeResponse;
import com.lumen.api.post.PostDtos.PlanResponse;
import com.lumen.api.post.PostDtos.PostResponse;
import com.lumen.api.user.UserService.User;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class PostService {
    private static final Set<String> METADATA_SOURCES =
            Set.of("EXIF", "USER_CONFIRMED", "MANUAL");
    private static final Set<String> PRIVACY_LEVELS =
            Set.of("EXACT", "APPROXIMATE", "PRIVATE");
    private static final DateTimeFormatter EXIF_DATE =
            DateTimeFormatter.ofPattern("yyyy:MM:dd HH:mm:ss");

    private final JdbcTemplate jdbc;
    private final PostRepository posts;

    public PostService(JdbcTemplate jdbc, PostRepository posts) {
        this.jdbc = jdbc;
        this.posts = posts;
    }

    public List<PostResponse> list(String userId, int limit, int offset) {
        return posts.list(userId, limit, offset);
    }

    public PostResponse get(UUID id, String userId) {
        return posts.find(id, userId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Post not found"));
    }

    @Transactional
    public PostResponse create(CreatePostRequest request, User user) {
        if (request == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Missing request body");
        }
        String kind = "ASSIGNMENT".equals(request.kind()) ? "ASSIGNMENT" : "ORIGINAL";
        UUID originalId = "ASSIGNMENT".equals(kind) ? request.originalId() : null;
        if ("ASSIGNMENT".equals(kind) && originalId == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Missing originalId");
        }
        if (originalId != null && !remakeableForUpdate(originalId)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Original post cannot be remade");
        }

        CreateImage image = request.image() == null
                ? new CreateImage(null, null, null, null)
                : request.image();
        CreateMetadata metadata = request.metadata() == null
                ? new CreateMetadata(null, null, null, null, null, null, null, null, null, null, null)
                : request.metadata();
        CreateLocation location = request.location() == null
                ? new CreateLocation(null, null, null, null, null, null, null)
                : request.location();
        Coordinates coordinates = coordinates(location);
        UUID postId = UUID.randomUUID();

        jdbc.update(
                """
                INSERT INTO posts (
                  id, author_id, kind, original_post_id, title, description,
                  image_object_key, image_url, display_image_url, thumbnail_url,
                  allow_remake, shooting_notes, editing_notes, reused_notes,
                  adjusted_notes, assignment_notes
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                postId.toString(),
                user.id(),
                kind,
                originalId == null ? null : originalId.toString(),
                text(request.title(), 120, true),
                text(request.description(), 10_000, false),
                nullableText(image.objectKey(), 512),
                nullableText(image.originalUrl(), 1_000),
                nullableText(image.displayUrl(), 1_000),
                nullableText(image.thumbnailUrl(), 1_000),
                request.allowRemake() == null || request.allowRemake(),
                text(request.shootingNotes(), 10_000, false),
                text(request.editingNotes(), 10_000, false),
                text(request.reusedNotes(), 10_000, false),
                text(request.adjustedNotes(), 10_000, false),
                text(request.assignmentNotes(), 10_000, false)
        );

        jdbc.update(
                """
                INSERT INTO capture_metadata (
                  post_id, camera_make, camera_model, camera_display, lens_model,
                  focal_length_mm, aperture, shutter_seconds, iso,
                  exposure_compensation, captured_at, source
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                postId.toString(),
                text(metadata.cameraMake(), 120, false),
                text(metadata.cameraModel(), 160, false),
                text(metadata.camera(), 240, false),
                text(metadata.lens(), 240, false),
                number(metadata.focalLengthMm(), 0, Double.MAX_VALUE),
                number(metadata.aperture(), 0, Double.MAX_VALUE),
                number(metadata.shutterSeconds(), 0, Double.MAX_VALUE),
                integer(metadata.iso(), 0, 10_000_000),
                number(metadata.exposureCompensation(), -20, 20),
                capturedAt(metadata.capturedAt()),
                metadata.source() != null && METADATA_SOURCES.contains(metadata.source())
                        ? metadata.source()
                        : "MANUAL"
        );

        jdbc.update(
                """
                INSERT INTO post_locations (
                  post_id, place_name, city, district, privacy_level,
                  latitude, longitude, public_latitude, public_longitude, shooting_advice
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                postId.toString(),
                text(location.name(), 200, false),
                text(location.city(), 80, false),
                text(location.district(), 100, false),
                coordinates.privacy(),
                coordinates.latitude(),
                coordinates.longitude(),
                coordinates.publicLatitude(),
                coordinates.publicLongitude(),
                text(location.advice(), 300, false)
        );

        if (originalId != null) {
            jdbc.update(
                    """
                    INSERT INTO remake_plans (
                      id, user_id, original_post_id, status,
                      completed_assignment_id, completed_at
                    ) VALUES (?, ?, ?, 'COMPLETED', ?, CURRENT_TIMESTAMP(3))
                    ON DUPLICATE KEY UPDATE
                      status = 'COMPLETED',
                      completed_assignment_id = VALUES(completed_assignment_id),
                      completed_at = CURRENT_TIMESTAMP(3)
                    """,
                    UUID.randomUUID().toString(),
                    user.id(),
                    originalId.toString(),
                    postId.toString()
            );
        }
        return get(postId, user.id());
    }

    @Transactional
    public LikeResponse toggleLike(UUID postId, User user) {
        requirePostForUpdate(postId);
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM post_likes WHERE user_id = ? AND post_id = ?",
                Integer.class,
                user.id(),
                postId.toString()
        );
        boolean liked;
        if (count != null && count > 0) {
            jdbc.update(
                    "DELETE FROM post_likes WHERE user_id = ? AND post_id = ?",
                    user.id(),
                    postId.toString()
            );
            jdbc.update(
                    "UPDATE posts SET like_count = GREATEST(like_count - 1, 0) WHERE id = ?",
                    postId.toString()
            );
            liked = false;
        } else {
            jdbc.update(
                    "INSERT INTO post_likes (user_id, post_id) VALUES (?, ?)",
                    user.id(),
                    postId.toString()
            );
            jdbc.update(
                    "UPDATE posts SET like_count = like_count + 1 WHERE id = ?",
                    postId.toString()
            );
            liked = true;
        }
        Integer likeCount = jdbc.queryForObject(
                "SELECT like_count FROM posts WHERE id = ?",
                Integer.class,
                postId.toString()
        );
        return new LikeResponse(liked, likeCount == null ? 0 : likeCount);
    }

    public List<CommentResponse> comments(UUID postId) {
        return jdbc.query(
                """
                SELECT c.id, c.content, c.parent_id, c.created_at,
                  u.id AS author_id, u.nickname AS author_name, u.avatar_url AS author_avatar
                FROM comments c
                JOIN users u ON u.id = c.author_id
                WHERE c.post_id = ? AND c.status = 'VISIBLE'
                ORDER BY c.created_at ASC
                LIMIT 200
                """,
                (rs, rowNum) -> new CommentResponse(
                        UUID.fromString(rs.getString("id")),
                        rs.getString("content"),
                        rs.getString("parent_id") == null
                                ? null
                                : UUID.fromString(rs.getString("parent_id")),
                        rs.getTimestamp("created_at").toInstant().toString(),
                        new CommentAuthor(
                                rs.getString("author_id"),
                                rs.getString("author_name"),
                                rs.getString("author_avatar")
                        )
                ),
                postId.toString()
        );
    }

    @Transactional
    public CommentResponse addComment(UUID postId, String content, User user) {
        String normalized = text(content, 1_000, true);
        requirePostForUpdate(postId);
        UUID commentId = UUID.randomUUID();
        jdbc.update(
                "INSERT INTO comments (id, post_id, author_id, content) VALUES (?, ?, ?, ?)",
                commentId.toString(),
                postId.toString(),
                user.id(),
                normalized
        );
        jdbc.update(
                "UPDATE posts SET comment_count = comment_count + 1 WHERE id = ?",
                postId.toString()
        );
        return new CommentResponse(
                commentId,
                normalized,
                null,
                Instant.now().toString(),
                new CommentAuthor(user.id(), user.nickname(), user.avatarUrl())
        );
    }

    @Transactional
    public PlanResponse togglePlan(UUID postId, User user) {
        Integer eligible = jdbc.queryForObject(
                """
                SELECT COUNT(*) FROM posts
                WHERE id = ? AND allow_remake = TRUE
                  AND kind = 'ORIGINAL' AND deleted_at IS NULL
                """,
                Integer.class,
                postId.toString()
        );
        if (eligible == null || eligible == 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Post cannot be added to remake plans");
        }
        List<PlanRow> plans = jdbc.query(
                """
                SELECT id, status FROM remake_plans
                WHERE user_id = ? AND original_post_id = ?
                FOR UPDATE
                """,
                (rs, rowNum) -> new PlanRow(rs.getString("id"), rs.getString("status")),
                user.id(),
                postId.toString()
        );
        if (!plans.isEmpty() && "COMPLETED".equals(plans.get(0).status())) {
            return new PlanResponse(true);
        }
        if (!plans.isEmpty()) {
            jdbc.update("DELETE FROM remake_plans WHERE id = ?", plans.get(0).id());
            return new PlanResponse(false);
        }
        jdbc.update(
                "INSERT INTO remake_plans (id, user_id, original_post_id) VALUES (?, ?, ?)",
                UUID.randomUUID().toString(),
                user.id(),
                postId.toString()
        );
        return new PlanResponse(true);
    }

    private boolean remakeableForUpdate(UUID postId) {
        List<String> rows = jdbc.query(
                """
                SELECT id FROM posts
                WHERE id = ? AND allow_remake = TRUE
                  AND visibility = 'PUBLIC'
                  AND review_status = 'APPROVED'
                  AND deleted_at IS NULL
                FOR UPDATE
                """,
                (rs, rowNum) -> rs.getString("id"),
                postId.toString()
        );
        return !rows.isEmpty();
    }

    private void requirePostForUpdate(UUID postId) {
        List<String> rows = jdbc.query(
                "SELECT id FROM posts WHERE id = ? AND deleted_at IS NULL FOR UPDATE",
                (rs, rowNum) -> rs.getString("id"),
                postId.toString()
        );
        if (rows.isEmpty()) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Post not found");
        }
    }

    private Coordinates coordinates(CreateLocation location) {
        String privacy = location.privacy() != null && PRIVACY_LEVELS.contains(location.privacy())
                ? location.privacy()
                : "PRIVATE";
        Double latitude = number(location.latitude(), -90, 90);
        Double longitude = number(location.longitude(), -180, 180);
        if ("PRIVATE".equals(privacy) || latitude == null || longitude == null) {
            return new Coordinates(privacy, latitude, longitude, null, null);
        }
        if ("APPROXIMATE".equals(privacy)) {
            return new Coordinates(
                    privacy,
                    latitude,
                    longitude,
                    Math.round(latitude * 1_000d) / 1_000d,
                    Math.round(longitude * 1_000d) / 1_000d
            );
        }
        return new Coordinates(privacy, latitude, longitude, latitude, longitude);
    }

    private Timestamp capturedAt(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            return Timestamp.from(Instant.parse(value));
        } catch (DateTimeParseException ignored) {
            try {
                return Timestamp.from(OffsetDateTime.parse(value).toInstant());
            } catch (DateTimeParseException ignoredAgain) {
                try {
                    return Timestamp.valueOf(LocalDateTime.parse(value, EXIF_DATE));
                } catch (DateTimeParseException finalError) {
                    throw new ApiException(HttpStatus.BAD_REQUEST, "Invalid capturedAt");
                }
            }
        }
    }

    private String text(String value, int max, boolean required) {
        String normalized = value == null ? "" : value.trim();
        if (required && normalized.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Missing required text field");
        }
        if (normalized.length() > max) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Text exceeds " + max + " characters");
        }
        return normalized;
    }

    private String nullableText(String value, int max) {
        String normalized = text(value, max, false);
        return normalized.isEmpty() ? null : normalized;
    }

    private Double number(Double value, double min, double max) {
        if (value == null) {
            return null;
        }
        if (!Double.isFinite(value) || value < min || value > max) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Invalid numeric field");
        }
        return value;
    }

    private Integer integer(Integer value, int min, int max) {
        if (value == null) {
            return null;
        }
        if (value < min || value > max) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Invalid numeric field");
        }
        return value;
    }

    private record Coordinates(
            String privacy,
            Double latitude,
            Double longitude,
            Double publicLatitude,
            Double publicLongitude
    ) {}

    private record PlanRow(String id, String status) {}
}
