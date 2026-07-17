package com.lumen.api.post;

import com.lumen.api.oss.OssService;
import com.lumen.api.post.PostDtos.Author;
import com.lumen.api.post.PostDtos.Image;
import com.lumen.api.post.PostDtos.Location;
import com.lumen.api.post.PostDtos.Metadata;
import com.lumen.api.post.PostDtos.PostResponse;
import java.math.BigDecimal;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class PostRepository {
    private static final String SELECT = """
            SELECT
              p.id, p.kind, p.original_post_id AS originalId, p.author_id AS authorId,
              u.nickname AS authorName, u.avatar_url AS authorAvatar, u.city AS authorCity,
              p.title, p.description, p.image_object_key AS imageObjectKey,
              p.image_url AS imageUrl, p.display_image_url AS displayImageUrl,
              p.thumbnail_url AS thumbnailUrl, p.allow_remake AS allowRemake,
              p.shooting_notes AS shootingNotes, p.editing_notes AS editingNotes,
              p.reused_notes AS reusedNotes, p.adjusted_notes AS adjustedNotes,
              p.assignment_notes AS assignmentNotes, p.is_recommended AS isRecommended,
              p.like_count AS likeCount, p.comment_count AS commentCount, p.created_at AS createdAt,
              m.camera_make AS cameraMake, m.camera_model AS cameraModel,
              m.camera_display AS camera, m.lens_model AS lens,
              m.focal_length_mm AS focalLengthMm, m.aperture,
              m.shutter_seconds AS shutterSeconds, m.iso,
              m.exposure_compensation AS exposureCompensation,
              m.captured_at AS capturedAt, m.source AS metadataSource,
              l.place_name AS placeName, l.city AS locationCity, l.district,
              l.privacy_level AS locationPrivacy, l.public_latitude AS latitude,
              l.public_longitude AS longitude, l.shooting_advice AS shootingAdvice,
              EXISTS(SELECT 1 FROM post_likes pl
                WHERE pl.post_id = p.id AND pl.user_id = ?) AS liked,
              EXISTS(SELECT 1 FROM remake_plans rp
                WHERE rp.original_post_id = p.id AND rp.user_id = ?) AS planned
            FROM posts p
            JOIN users u ON u.id = p.author_id
            LEFT JOIN capture_metadata m ON m.post_id = p.id
            LEFT JOIN post_locations l ON l.post_id = p.id
            """;

    private final JdbcTemplate jdbc;
    private final OssService oss;

    public PostRepository(JdbcTemplate jdbc, OssService oss) {
        this.jdbc = jdbc;
        this.oss = oss;
    }

    public List<PostResponse> list(String userId, int limit, int offset) {
        return jdbc.query(
                SELECT + """
                 WHERE p.visibility = 'PUBLIC'
                   AND p.review_status = 'APPROVED'
                   AND p.deleted_at IS NULL
                 ORDER BY p.created_at DESC
                 LIMIT ? OFFSET ?
                """,
                this::map,
                userId,
                userId,
                limit,
                offset
        );
    }

    public Optional<PostResponse> find(UUID id, String userId) {
        List<PostResponse> posts = jdbc.query(
                SELECT + """
                 WHERE p.id = ?
                   AND p.visibility = 'PUBLIC'
                   AND p.review_status = 'APPROVED'
                   AND p.deleted_at IS NULL
                 LIMIT 1
                """,
                this::map,
                userId,
                userId,
                id.toString()
        );
        return posts.stream().findFirst();
    }

    private PostResponse map(ResultSet rs, int rowNum) throws SQLException {
        String objectKey = rs.getString("imageObjectKey");
        String signedUrl = oss.createDownloadUrl(objectKey);
        String originalUrl = signedUrl != null ? signedUrl : rs.getString("imageUrl");
        String displayUrl = signedUrl != null ? signedUrl
                : first(rs.getString("displayImageUrl"), originalUrl);
        String thumbnailUrl = signedUrl != null ? signedUrl
                : first(rs.getString("thumbnailUrl"), displayUrl);

        return new PostResponse(
                uuid(rs.getString("id")),
                rs.getString("kind"),
                uuid(rs.getString("originalId")),
                new Author(
                        rs.getString("authorId"),
                        rs.getString("authorName"),
                        rs.getString("authorAvatar"),
                        rs.getString("authorCity")
                ),
                rs.getString("title"),
                rs.getString("description"),
                new Image(objectKey, originalUrl, displayUrl, thumbnailUrl),
                rs.getBoolean("allowRemake"),
                value(rs.getString("shootingNotes")),
                value(rs.getString("editingNotes")),
                value(rs.getString("reusedNotes")),
                value(rs.getString("adjustedNotes")),
                value(rs.getString("assignmentNotes")),
                rs.getBoolean("isRecommended"),
                rs.getInt("likeCount"),
                rs.getInt("commentCount"),
                rs.getBoolean("liked"),
                rs.getBoolean("planned"),
                instant(rs.getTimestamp("createdAt")),
                new Metadata(
                        value(rs.getString("cameraMake")),
                        value(rs.getString("cameraModel")),
                        value(rs.getString("camera")),
                        value(rs.getString("lens")),
                        number(rs.getBigDecimal("focalLengthMm")),
                        number(rs.getBigDecimal("aperture")),
                        number(rs.getBigDecimal("shutterSeconds")),
                        integer(rs, "iso"),
                        number(rs.getBigDecimal("exposureCompensation")),
                        instant(rs.getTimestamp("capturedAt")),
                        first(rs.getString("metadataSource"), "MANUAL")
                ),
                new Location(
                        value(rs.getString("placeName")),
                        value(rs.getString("locationCity")),
                        value(rs.getString("district")),
                        first(rs.getString("locationPrivacy"), "PRIVATE"),
                        number(rs.getBigDecimal("latitude")),
                        number(rs.getBigDecimal("longitude")),
                        value(rs.getString("shootingAdvice"))
                )
        );
    }

    private Integer integer(ResultSet rs, String column) throws SQLException {
        int value = rs.getInt(column);
        return rs.wasNull() ? null : value;
    }

    private Double number(BigDecimal value) {
        return value == null ? null : value.doubleValue();
    }

    private String instant(Timestamp value) {
        return value == null ? null : value.toInstant().toString();
    }

    private UUID uuid(String value) {
        return value == null ? null : UUID.fromString(value);
    }

    private String value(String value) {
        return value == null ? "" : value;
    }

    private String first(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }
}
