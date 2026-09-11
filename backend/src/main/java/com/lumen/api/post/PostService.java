package com.lumen.api.post;

import com.lumen.api.common.ApiException;
import com.lumen.api.notification.NotificationService;
import com.lumen.api.oss.OssService;
import com.lumen.api.post.PostDtos.CommentAuthor;
import com.lumen.api.post.PostDtos.CommentResponse;
import com.lumen.api.post.PostDtos.CreateImage;
import com.lumen.api.post.PostDtos.CreateLocation;
import com.lumen.api.post.PostDtos.CreateMetadata;
import com.lumen.api.post.PostDtos.CreatePostRequest;
import com.lumen.api.post.PostDtos.LikeResponse;
import com.lumen.api.post.PostDtos.PlanResponse;
import com.lumen.api.post.PostDtos.PostResponse;
import com.lumen.api.post.PostRepository.FeedQuery;
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
    private static final DateTimeFormatter EXIF_DATE =
            DateTimeFormatter.ofPattern("yyyy:MM:dd HH:mm:ss");

    private final JdbcTemplate jdbc;
    private final PostRepository posts;
    private final OssService oss;
    private final NotificationService notifications;

    public PostService(
            JdbcTemplate jdbc,
            PostRepository posts,
            OssService oss,
            NotificationService notifications
    ) {
        this.jdbc = jdbc;
        this.posts = posts;
        this.oss = oss;
        this.notifications = notifications;
    }

    public List<PostResponse> list(String userId, int limit, int offset) {
        return posts.list(userId, limit, offset);
    }

    public List<PostResponse> list(String userId, int limit, int offset, FeedQuery query) {
        return posts.list(userId, limit, offset, query);
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
                ? new CreateImage(null, null, null, null, null, null)
                : request.image();
        CreateMetadata metadata = request.metadata() == null
                ? new CreateMetadata(null, null, null, null, null, null, null, null, null, null, null)
                : request.metadata();
        CreateLocation location = request.location() == null
                ? new CreateLocation(null, null, null, null, null, null, null, null)
                : request.location();
        location = LocationPolicy.normalize(location);
        Coordinates coordinates = new Coordinates(location.privacy(), location.latitude(), location.longitude());
        UUID postId = UUID.randomUUID();

        jdbc.update(
                """
                INSERT INTO posts (
                  id, author_id, kind, original_post_id, title, description,
                  image_object_key, image_url, display_image_object_key,
                  display_image_url, thumbnail_object_key, thumbnail_url,
                  allow_remake, shooting_notes, editing_notes, reused_notes,
                  adjusted_notes, assignment_notes
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                postId.toString(),
                user.id(),
                kind,
                originalId == null ? null : originalId.toString(),
                text(request.title(), 120, true),
                text(request.description(), 10_000, false),
                nullableText(image.objectKey(), 512),
                nullableText(image.originalUrl(), 1_000),
                nullableText(image.displayObjectKey(), 512),
                nullableText(image.displayUrl(), 1_000),
                nullableText(image.thumbnailObjectKey(), 512),
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
                  post_id, place_name, city, district, detailed_address, privacy_level,
                  latitude, longitude, shooting_advice
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                postId.toString(),
                text(location.name(), 500, false),
                text(location.city(), 80, false),
                text(location.district(), 100, false),
                text(location.detailedAddress(), 500, false),
                coordinates.privacy(),
                coordinates.latitude(),
                coordinates.longitude(),
                text(location.advice(), 300, false)
        );
        replaceTags(postId, request.tags());

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
            String originalAuthorId = postAuthorId(originalId);
            notifications.create(
                    originalAuthorId,
                    user.id(),
                    "ASSIGNMENT",
                    originalId,
                    postId
            );
        }
        return get(postId, user.id());
    }

    @Transactional
    public PostResponse update(UUID postId, CreatePostRequest request, User user) {
        if (request == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Missing request body");
        }
        Integer owned = jdbc.queryForObject(
                "SELECT COUNT(*) FROM posts WHERE id = ? AND author_id = ? AND deleted_at IS NULL FOR UPDATE",
                Integer.class,
                postId.toString(),
                user.id()
        );
        if (owned == null || owned == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Post not found");
        }

        CreateMetadata metadata = request.metadata() == null
                ? new CreateMetadata(null, null, null, null, null, null, null, null, null, null, null)
                : request.metadata();
        CreateLocation location = request.location() == null
                ? new CreateLocation(null, null, null, null, null, null, null, null)
                : request.location();
        location = LocationPolicy.normalize(location);
        Coordinates coordinates = new Coordinates(location.privacy(), location.latitude(), location.longitude());
        CreateImage image = request.image();

        jdbc.update(
                """
                UPDATE posts SET
                  title = ?, description = ?, allow_remake = ?,
                  shooting_notes = ?, editing_notes = ?, reused_notes = ?,
                  adjusted_notes = ?, assignment_notes = ?,
                  image_object_key = COALESCE(?, image_object_key),
                  image_url = COALESCE(?, image_url),
                  display_image_object_key = COALESCE(?, display_image_object_key),
                  display_image_url = COALESCE(?, display_image_url),
                  thumbnail_object_key = COALESCE(?, thumbnail_object_key),
                  thumbnail_url = COALESCE(?, thumbnail_url)
                WHERE id = ?
                """,
                text(request.title(), 120, true),
                text(request.description(), 10_000, false),
                request.allowRemake() == null || request.allowRemake(),
                text(request.shootingNotes(), 10_000, false),
                text(request.editingNotes(), 10_000, false),
                text(request.reusedNotes(), 10_000, false),
                text(request.adjustedNotes(), 10_000, false),
                text(request.assignmentNotes(), 10_000, false),
                image == null ? null : nullableText(image.objectKey(), 512),
                image == null ? null : nullableText(image.originalUrl(), 1_000),
                image == null ? null : nullableText(image.displayObjectKey(), 512),
                image == null ? null : nullableText(image.displayUrl(), 1_000),
                image == null ? null : nullableText(image.thumbnailObjectKey(), 512),
                image == null ? null : nullableText(image.thumbnailUrl(), 1_000),
                postId.toString()
        );

        jdbc.update(
                """
                UPDATE capture_metadata SET
                  camera_make = ?, camera_model = ?, camera_display = ?, lens_model = ?,
                  focal_length_mm = ?, aperture = ?, shutter_seconds = ?, iso = ?,
                  exposure_compensation = ?, captured_at = ?, source = ?
                WHERE post_id = ?
                """,
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
                        : "MANUAL",
                postId.toString()
        );

        jdbc.update(
                """
                UPDATE post_locations SET
                  place_name = ?, city = ?, district = ?, detailed_address = ?, privacy_level = ?,
                  latitude = ?, longitude = ?, shooting_advice = ?
                WHERE post_id = ?
                """,
                text(location.name(), 500, false),
                text(location.city(), 80, false),
                text(location.district(), 100, false),
                text(location.detailedAddress(), 500, false),
                coordinates.privacy(),
                coordinates.latitude(),
                coordinates.longitude(),
                text(location.advice(), 300, false),
                postId.toString()
        );
        replaceTags(postId, request.tags());
        return get(postId, user.id());
    }

    @Transactional
    public void delete(UUID postId, User user) {
        int deleted = jdbc.update(
                """
                UPDATE posts
                SET deleted_at = CURRENT_TIMESTAMP(3)
                WHERE id = ? AND author_id = ? AND deleted_at IS NULL
                """,
                postId.toString(),
                user.id()
        );
        if (deleted == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Post not found");
        }
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
            notifications.create(
                    postAuthorId(postId),
                    user.id(),
                    "LIKE",
                    postId,
                    null
            );
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
                  u.id AS author_id, u.nickname AS author_name,
                  u.avatar_object_key AS author_avatar_object_key,
                  u.avatar_url AS author_avatar
                FROM comments c
                JOIN users u ON u.id = c.author_id
                JOIN posts p ON p.id = c.post_id
                WHERE c.post_id = ? AND c.status = 'VISIBLE' AND p.deleted_at IS NULL
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
                                first(
                                        oss.createDownloadUrl(rs.getString("author_avatar_object_key")),
                                        rs.getString("author_avatar")
                                )
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
        notifications.create(
                postAuthorId(postId),
                user.id(),
                "COMMENT",
                postId,
                null
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
                  AND author_id <> ?
                """,
                Integer.class,
                postId.toString(),
                user.id()
        );
        if (eligible == null || eligible == 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "不能将自己的作品加入拍摄计划");
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

    private void replaceTags(UUID postId, List<String> rawTags) {
        jdbc.update("DELETE FROM post_tags WHERE post_id = ?", postId.toString());
        if (rawTags == null) {
            return;
        }
        rawTags.stream()
                .filter(java.util.Objects::nonNull)
                .map(String::trim)
                .filter(tag -> !tag.isEmpty())
                .distinct()
                .limit(5)
                .forEach(tag -> jdbc.update(
                        "INSERT INTO post_tags (post_id, tag) VALUES (?, ?)",
                        postId.toString(),
                        text(tag, 40, false)
                ));
    }

    private String postAuthorId(UUID postId) {
        return jdbc.queryForObject(
                "SELECT author_id FROM posts WHERE id = ?",
                String.class,
                postId.toString()
        );
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

    private String first(String preferred, String fallback) {
        return preferred == null || preferred.isBlank() ? fallback : preferred;
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
            Double longitude
    ) {}

    private record PlanRow(String id, String status) {}
}
