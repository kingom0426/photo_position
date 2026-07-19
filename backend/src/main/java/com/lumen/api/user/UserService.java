package com.lumen.api.user;

import com.lumen.api.common.ApiException;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class UserService {
    private final JdbcTemplate jdbc;

    public UserService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public User require(String userId) {
        if (userId == null || userId.isBlank()) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Missing x-user-id header");
        }
        List<User> users = jdbc.query(
                """
                SELECT id, nickname, avatar_url, city
                FROM users
                WHERE id = ? AND status = 'ACTIVE'
                LIMIT 1
                """,
                (rs, rowNum) -> new User(
                        rs.getString("id"),
                        rs.getString("nickname"),
                        rs.getString("avatar_url"),
                        rs.getString("city")
                ),
                userId.trim()
        );
        if (users.isEmpty()) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Unknown or inactive user");
        }
        return users.get(0);
    }

    public record User(String id, String nickname, String avatarUrl, String city) {}
}
