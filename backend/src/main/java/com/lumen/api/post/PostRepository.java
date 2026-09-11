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
import java.util.Set;
import java.util.UUID;
import java.util.ArrayList;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class PostRepository {
    private static final String SELECT = """
            SELECT
              p.id, p.kind, p.original_post_id AS originalId, p.author_id AS authorId,
              u.nickname AS authorName, u.avatar_object_key AS authorAvatarObjectKey,
              u.avatar_url AS authorAvatar, u.city AS authorCity,
              p.title, p.description, p.image_object_key AS imageObjectKey,
              p.image_url AS imageUrl,
              p.display_image_object_key AS displayImageObjectKey,
              p.display_image_url AS displayImageUrl,
              p.thumbnail_object_key AS thumbnailObjectKey,
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
              l.detailed_address AS detailedAddress,
              l.privacy_level AS locationPrivacy, l.latitude,
              l.longitude, l.shooting_advice AS shootingAdvice,
              (SELECT GROUP_CONCAT(pt.tag ORDER BY pt.tag SEPARATOR '\u001F')
                 FROM post_tags pt WHERE pt.post_id = p.id) AS tags,
              %s AS distanceKm,
              EXISTS(SELECT 1 FROM post_likes pl
                WHERE pl.post_id = p.id AND pl.user_id = ?) AS liked,
              EXISTS(SELECT 1 FROM remake_plans rp
                WHERE rp.original_post_id = p.id AND rp.user_id = ?
                  AND rp.status = 'PLANNED') AS planned
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
        return list(userId, limit, offset, FeedQuery.defaults());
    }

    public List<PostResponse> list(
            String userId,
            int limit,
            int offset,
            FeedQuery query
    ) {
        boolean hasCoordinate = query.latitude() != null && query.longitude() != null;
        String distanceSql = hasCoordinate ? distanceSql() : "NULL";
        StringBuilder where = new StringBuilder("""
                 WHERE p.visibility = 'PUBLIC'
                   AND p.review_status = 'APPROVED'
                   AND p.deleted_at IS NULL
                """);
        List<Object> parameters = new ArrayList<>();
        if (hasCoordinate) {
            addDistanceParameters(parameters, query.latitude(), query.longitude());
        }
        parameters.add(userId);
        parameters.add(userId);

        if ("following".equals(query.feed()) && userId != null) {
            where.append("""
                 AND EXISTS (
                   SELECT 1 FROM follows f
                   WHERE f.follower_id = ? AND f.following_id = p.author_id
                 )
                """);
            parameters.add(userId);
        }
        if (query.authorId() != null && !query.authorId().isBlank()) {
            where.append(" AND p.author_id = ?\n");
            parameters.add(query.authorId().trim());
        }
        if (query.search() != null && !query.search().isBlank()) {
            where.append("""
                 AND (
                   LOWER(p.title) LIKE ? OR LOWER(p.description) LIKE ?
                   OR LOWER(u.nickname) LIKE ? OR LOWER(l.place_name) LIKE ?
                   OR LOWER(l.city) LIKE ?
                   OR EXISTS (
                     SELECT 1 FROM post_tags search_tag
                     WHERE search_tag.post_id = p.id AND LOWER(search_tag.tag) LIKE ?
                   )
                 )
                """);
            String pattern = "%" + query.search().trim().toLowerCase() + "%";
            for (int i = 0; i < 6; i++) {
                parameters.add(pattern);
            }
        }
        if (query.tag() != null && !query.tag().isBlank()) {
            where.append("""
                 AND EXISTS (
                   SELECT 1 FROM post_tags exact_tag
                   WHERE exact_tag.post_id = p.id AND exact_tag.tag = ?
                 )
                """);
            parameters.add(query.tag().trim());
        }
        appendQuickFilters(where, parameters, query.filters());

        boolean distanceLimited = hasCoordinate
                && (query.radiusKm() != null || "nearby".equals(query.feed()));
        if (distanceLimited) {
            where.append(" AND ").append(distanceSql()).append(" <= ?\n");
            addDistanceParameters(parameters, query.latitude(), query.longitude());
            parameters.add(query.radiusKm() == null ? 5.0 : query.radiusKm());
        }

        String order = hasCoordinate && ("nearby".equals(query.feed())
                || query.filters().contains("distance"))
                ? " ORDER BY distanceKm ASC, p.created_at DESC\n"
                : " ORDER BY p.created_at DESC\n";
        parameters.add(limit);
        parameters.add(offset);
        return jdbc.query(
                SELECT.formatted(distanceSql) + where + order + " LIMIT ? OFFSET ?",
                this::map,
                parameters.toArray()
        );
    }

    public Optional<PostResponse> find(UUID id, String userId) {
        List<PostResponse> posts = jdbc.query(
                SELECT.formatted("NULL") + """
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

    public Optional<PostResponse> findForAdmin(UUID id) {
        return jdbc.query(SELECT.formatted("NULL") + " WHERE p.id=? LIMIT 1", this::map,
                null, null, id.toString()).stream().findFirst();
    }

    private PostResponse map(ResultSet rs, int rowNum) throws SQLException {
        String objectKey = rs.getString("imageObjectKey");
        String originalUrl = first(
                oss.createDownloadUrl(objectKey),
                rs.getString("imageUrl")
        );
        String displayUrl = first(
                oss.createDownloadUrl(rs.getString("displayImageObjectKey")),
                first(rs.getString("displayImageUrl"), originalUrl)
        );
        String thumbnailUrl = first(
                oss.createDownloadUrl(rs.getString("thumbnailObjectKey")),
                first(rs.getString("thumbnailUrl"), displayUrl)
        );

        return new PostResponse(
                uuid(rs.getString("id")),
                rs.getString("kind"),
                uuid(rs.getString("originalId")),
                new Author(
                        rs.getString("authorId"),
                        rs.getString("authorName"),
                        first(
                                oss.createDownloadUrl(rs.getString("authorAvatarObjectKey")),
                                rs.getString("authorAvatar")
                        ),
                        rs.getString("authorCity")
                ),
                rs.getString("title"),
                rs.getString("description"),
                new Image(objectKey, originalUrl, displayUrl, thumbnailUrl),
                tags(rs.getString("tags")),
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
                        value(rs.getString("detailedAddress")),
                        first(rs.getString("locationPrivacy"), "PRIVATE"),
                        number(rs.getBigDecimal("latitude")),
                        number(rs.getBigDecimal("longitude")),
                        value(rs.getString("shootingAdvice"))
                ),
                number(rs.getBigDecimal("distanceKm"))
        );
    }

    private void appendQuickFilters(
            StringBuilder where,
            List<Object> parameters,
            Set<String> filters
    ) {
        List<String> tagFilters = new ArrayList<>();
        if (filters.contains("night")) tagFilters.add("夜景");
        if (filters.contains("street")) tagFilters.add("街拍");
        if (filters.contains("architecture")) tagFilters.add("建筑");
        if (!tagFilters.isEmpty()) {
            where.append("""
                 AND EXISTS (
                   SELECT 1 FROM post_tags quick_tag
                   WHERE quick_tag.post_id = p.id AND quick_tag.tag IN (
                """);
            where.append(String.join(",", java.util.Collections.nCopies(tagFilters.size(), "?")));
            where.append("))\n");
            parameters.addAll(tagFilters);
        }
        if (filters.contains("mobile")) {
            where.append("""
                 AND (
                   LOWER(m.camera_display) LIKE '%iphone%'
                   OR LOWER(m.camera_display) LIKE '%huawei%'
                   OR LOWER(m.camera_display) LIKE '%xiaomi%'
                   OR LOWER(m.camera_display) LIKE '%oppo%'
                   OR LOWER(m.camera_display) LIKE '%vivo%'
                   OR LOWER(m.camera_display) LIKE '%pixel%'
                   OR EXISTS (
                     SELECT 1 FROM post_tags mobile_tag
                     WHERE mobile_tag.post_id = p.id AND mobile_tag.tag = '手机可拍'
                   )
                 )
                """);
        }
        if (filters.contains("complete")) {
            where.append("""
                 AND m.camera_display <> '' AND m.lens_model <> ''
                 AND m.focal_length_mm IS NOT NULL AND m.aperture IS NOT NULL
                 AND m.shutter_seconds IS NOT NULL AND m.iso IS NOT NULL
                 AND p.shooting_notes <> ''
                """);
        }
    }

    private String distanceSql() {
        return """
                (6371 * 2 * ASIN(SQRT(
                  POWER(SIN(RADIANS(l.latitude - ?) / 2), 2)
                  + COS(RADIANS(?)) * COS(RADIANS(l.latitude))
                  * POWER(SIN(RADIANS(l.longitude - ?) / 2), 2)
                )))
                """;
    }

    private void addDistanceParameters(List<Object> parameters, double latitude, double longitude) {
        parameters.add(latitude);
        parameters.add(latitude);
        parameters.add(longitude);
    }

    private List<String> tags(String value) {
        if (value == null || value.isBlank()) {
            return List.of();
        }
        return List.of(value.split("\u001F"));
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

    public record FeedQuery(
            String feed,
            Double latitude,
            Double longitude,
            Double radiusKm,
            String search,
            String tag,
            String authorId,
            Set<String> filters
    ) {
        public static FeedQuery defaults() {
            return new FeedQuery("recommended", null, null, null, null, null, null, Set.of());
        }
    }
}
