package com.lumen.api.discovery;

import com.lumen.api.oss.OssService;
import com.lumen.api.post.PostDtos.PostResponse;
import com.lumen.api.post.PostRepository;
import com.lumen.api.post.PostRepository.FeedQuery;
import com.lumen.api.user.UserService;
import com.lumen.api.user.UserService.PublicUser;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/discovery")
public class DiscoveryController {
    private static final List<String> DEFAULT_TAGS = List.of(
            "夜景", "街拍", "建筑", "人像", "风光", "城市",
            "自然", "手机可拍", "黑白", "长曝光", "日出日落", "旅行"
    );

    private final UserService users;
    private final PostRepository posts;
    private final JdbcTemplate jdbc;
    private final OssService oss;

    public DiscoveryController(
            UserService users,
            PostRepository posts,
            JdbcTemplate jdbc,
            OssService oss
    ) {
        this.users = users;
        this.posts = posts;
        this.jdbc = jdbc;
        this.oss = oss;
    }

    @GetMapping("/tags")
    TagList tags() {
        List<TagResult> items = new ArrayList<>();
        for (String tag : DEFAULT_TAGS) {
            Integer count = jdbc.queryForObject(
                    "SELECT COUNT(*) FROM post_tags WHERE tag = ?",
                    Integer.class,
                    tag
            );
            items.add(new TagResult(tag, count == null ? 0 : count));
        }
        return new TagList(items);
    }

    @GetMapping("/search")
    SearchResult search(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @RequestParam String q
    ) {
        String keyword = q == null ? "" : q.trim();
        if (keyword.isEmpty()) {
            return new SearchResult(List.of(), List.of(), List.of(), List.of());
        }
        var user = users.optional(authorization);
        List<PostResponse> postItems = posts.list(
                user == null ? null : user.id(),
                8,
                0,
                new FeedQuery(
                        "recommended", null, null, null,
                        keyword, null, null, Set.of()
                )
        );
        String pattern = "%" + keyword.toLowerCase() + "%";
        List<LocationResult> locations = jdbc.query(
                """
                SELECT l.place_name, l.city,
                       AVG(l.latitude) AS latitude, AVG(l.longitude) AS longitude,
                       COUNT(*) AS post_count
                FROM post_locations l
                JOIN posts p ON p.id = l.post_id
                WHERE p.visibility = 'PUBLIC' AND p.review_status = 'APPROVED'
                  AND p.deleted_at IS NULL
                  AND l.privacy_level IN ('EXACT', 'APPROXIMATE')
                  AND l.latitude IS NOT NULL AND l.longitude IS NOT NULL
                  AND l.place_name <> '' AND l.place_name <> '地点未公开'
                  AND (LOWER(l.place_name) LIKE ? OR LOWER(l.city) LIKE ?)
                GROUP BY l.place_name, l.city
                ORDER BY post_count DESC
                LIMIT 8
                """,
                (rs, rowNum) -> new LocationResult(
                        rs.getString("place_name"),
                        rs.getString("city"),
                        number(rs.getBigDecimal("latitude")),
                        number(rs.getBigDecimal("longitude")),
                        rs.getInt("post_count")
                ),
                pattern,
                pattern
        );
        List<PublicUser> userItems = jdbc.query(
                """
                SELECT id, nickname, avatar_object_key, avatar_url, city, bio
                FROM users
                WHERE status = 'ACTIVE'
                  AND (LOWER(nickname) LIKE ? OR LOWER(city) LIKE ? OR LOWER(bio) LIKE ?)
                ORDER BY nickname
                LIMIT 8
                """,
                (rs, rowNum) -> new PublicUser(
                        rs.getString("id"),
                        rs.getString("nickname"),
                        first(
                                oss.createDownloadUrl(rs.getString("avatar_object_key")),
                                rs.getString("avatar_url")
                        ),
                        rs.getString("city"),
                        rs.getString("bio")
                ),
                pattern,
                pattern,
                pattern
        );
        List<TagResult> tagItems = jdbc.query(
                """
                SELECT tag, COUNT(*) AS usage_count
                FROM post_tags
                WHERE LOWER(tag) LIKE ?
                GROUP BY tag
                ORDER BY usage_count DESC, tag
                LIMIT 12
                """,
                (rs, rowNum) -> new TagResult(
                        rs.getString("tag"),
                        rs.getInt("usage_count")
                ),
                pattern
        );
        return new SearchResult(postItems, locations, userItems, tagItems);
    }

    private Double number(BigDecimal value) {
        return value == null ? null : value.doubleValue();
    }

    private String first(String preferred, String fallback) {
        return preferred == null || preferred.isBlank() ? fallback : preferred;
    }

    record TagResult(String name, int usageCount) {}
    record TagList(List<TagResult> items) {}
    record LocationResult(
            String name,
            String city,
            Double latitude,
            Double longitude,
            int postCount
    ) {}
    record SearchResult(
            List<PostResponse> posts,
            List<LocationResult> locations,
            List<PublicUser> users,
            List<TagResult> tags
    ) {}
}
