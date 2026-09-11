package com.lumen.api.user;

import com.lumen.api.common.ApiException;
import com.lumen.api.notification.NotificationService;
import com.lumen.api.oss.OssService;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;
import org.springframework.http.HttpStatus;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class UserService {
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final int PASSWORD_ITERATIONS = 120_000;
    private final JdbcTemplate jdbc;
    private final OssService oss;
    private final NotificationService notifications;
    private final ConsentService consents;
    private final EmailAuthService emailAuth;

    public UserService(JdbcTemplate jdbc, OssService oss, NotificationService notifications,
                       ConsentService consents, EmailAuthService emailAuth) {
        this.jdbc = jdbc;
        this.oss = oss;
        this.notifications = notifications;
        this.consents = consents;
        this.emailAuth = emailAuth;
    }

    public User require(String authorization) {
        User user = optional(authorization);
        if (user == null) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Please sign in");
        }
        return user;
    }

    public User optional(String authorization) {
        String token = bearerToken(authorization);
        if (token == null) {
            return null;
        }
        List<User> users = jdbc.query(
                """
                SELECT u.id, u.username, u.email, u.phone, u.nickname,
                       u.avatar_object_key, u.avatar_url, u.city, u.bio
                FROM user_sessions s
                JOIN users u ON u.id = s.user_id
                WHERE s.token_hash = ? AND s.expires_at > CURRENT_TIMESTAMP(3)
                  AND u.status = 'ACTIVE'
                LIMIT 1
                """,
                (rs, rowNum) -> mapUser(
                        rs.getString("id"), rs.getString("username"),
                        rs.getString("email"), rs.getString("phone"),
                        rs.getString("nickname"), rs.getString("avatar_object_key"),
                        rs.getString("avatar_url"),
                        rs.getString("city"), rs.getString("bio")
                ),
                sha256(token)
        );
        return users.isEmpty() ? null : users.get(0);
    }

    @Transactional
    public AuthResult register(String email, String password, String nickname,
                               boolean consentAccepted, String consentVersion,
                               String acceptedIp, String verificationCode) {
        String normalizedEmail = EmailAuthService.normalizeEmail(email);
        validatePassword(password);
        String normalizedName = nickname == null || nickname.isBlank()
                ? "摄影者" + UUID.randomUUID().toString().substring(0, 8)
                : text(nickname, 80, "昵称不能为空且不能超过 80 个字符");
        if (!consentAccepted || !consents.isCurrentVersion(consentVersion)) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "注册前，请阅读并同意当前版本的用户知情同意书");
        }
        Integer existing = jdbc.queryForObject(
                "SELECT COUNT(*) FROM users WHERE email = ?",
                Integer.class,
                normalizedEmail
        );
        if (existing != null && existing > 0) {
            throw new ApiException(HttpStatus.CONFLICT, EmailAuthService.EMAIL_REGISTERED_MESSAGE);
        }
        emailAuth.consumeRegistration(normalizedEmail, verificationCode);
        if (nicknameExists(normalizedName, null)) {
            throw new ApiException(HttpStatus.CONFLICT, "昵称已被使用");
        }
        String salt = randomToken(16);
        String id = UUID.randomUUID().toString();
        try {
            jdbc.update(
                    """
                    INSERT INTO users (
                      id, email, password_salt, password_hash, nickname, bio, city, email_verified_at
                    ) VALUES (?, ?, ?, ?, ?, '', '', CURRENT_TIMESTAMP(3))
                    """,
                    id, normalizedEmail, salt, passwordHash(password, salt), normalizedName
            );
        } catch (DuplicateKeyException error) {
            throw new ApiException(HttpStatus.CONFLICT, "邮箱或昵称已被使用");
        }
        jdbc.update(
                """
                INSERT INTO user_consent_acceptances
                  (id, user_id, consent_type, consent_version, document_sha256, accepted_ip)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                UUID.randomUUID().toString(), id, ConsentService.TYPE,
                ConsentService.VERSION, consents.documentSha256(), normalizeIp(acceptedIp)
        );
        User user = new User(id, null, normalizedEmail, null, normalizedName,
                null, "", "");
        return createSession(user, true);
    }

    @Transactional
    public AuthResult login(String username, String password) {
        validatePassword(password);
        boolean usingEmail = username != null && username.contains("@");
        String normalizedUsername = usingEmail ? EmailAuthService.normalizeEmail(username) : normalizeUsername(username);
        List<CredentialRow> rows = jdbc.query(
                """
                SELECT id, username, email, phone, nickname,
                       avatar_object_key, avatar_url, city, bio,
                       password_salt, password_hash
                FROM users
                WHERE %s = ? AND status = 'ACTIVE'
                LIMIT 1 FOR UPDATE
                """.formatted(usingEmail ? "email" : "username"),
                (rs, rowNum) -> new CredentialRow(
                        mapUser(rs.getString("id"), rs.getString("username"),
                                rs.getString("email"), rs.getString("phone"),
                                rs.getString("nickname"), rs.getString("avatar_object_key"),
                                rs.getString("avatar_url"),
                                rs.getString("city"), rs.getString("bio")),
                        rs.getString("password_salt"),
                        rs.getString("password_hash")
                ),
                normalizedUsername
        );
        if (rows.isEmpty() || rows.get(0).salt() == null || rows.get(0).passwordHash() == null
                || !MessageDigest.isEqual(
                        passwordHash(password, rows.get(0).salt()).getBytes(StandardCharsets.UTF_8),
                        rows.get(0).passwordHash().getBytes(StandardCharsets.UTF_8))) {
            // Equalize the expensive password work for unknown accounts as well.
            if (rows.isEmpty() || rows.get(0).salt() == null || rows.get(0).passwordHash() == null) {
                passwordHash(password, Base64.getUrlEncoder().withoutPadding().encodeToString(new byte[16]));
            }
            throw new ApiException(HttpStatus.UNAUTHORIZED, "邮箱或密码错误");
        }
        return createSession(rows.get(0).user());
    }

    @Transactional
    public void resetPassword(String token, String password) {
        validatePassword(password);
        String userId = emailAuth.consumeReset(token);
        replacePassword(userId, password);
        jdbc.update("UPDATE users SET email_verified_at=COALESCE(email_verified_at,CURRENT_TIMESTAMP(3)) WHERE id=?", userId);
    }

    @Transactional
    public void changePassword(String authorization, String oldPassword, String newPassword) {
        User user = require(authorization);
        validatePassword(oldPassword);
        validatePassword(newPassword);
        var rows = jdbc.query("SELECT password_salt,password_hash FROM users WHERE id=? AND status='ACTIVE' FOR UPDATE",
                (rs, n) -> new String[]{rs.getString(1), rs.getString(2)}, user.id());
        // Recheck after the user row lock, since a simultaneous reset may have revoked this session.
        var activeSessions = jdbc.query("SELECT id FROM user_sessions WHERE user_id=? AND token_hash=? "
                        + "AND expires_at>CURRENT_TIMESTAMP(3) FOR UPDATE",
                (rs, n) -> rs.getString(1), user.id(), sha256(bearerToken(authorization)));
        if (activeSessions.isEmpty()) throw new ApiException(HttpStatus.UNAUTHORIZED, "Please sign in");
        if (rows.isEmpty() || rows.get(0)[0] == null || rows.get(0)[1] == null
                || !MessageDigest.isEqual(passwordHash(oldPassword, rows.get(0)[0]).getBytes(StandardCharsets.UTF_8),
                rows.get(0)[1].getBytes(StandardCharsets.UTF_8))) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "原密码不正确；未设置密码的旧账号请使用邮件找回");
        }
        replacePassword(user.id(), newPassword);
    }

    private void replacePassword(String userId, String password) {
        String salt = randomToken(16);
        jdbc.update("UPDATE users SET password_salt=?,password_hash=?,updated_at=CURRENT_TIMESTAMP(3) WHERE id=?",
                salt, passwordHash(password, salt), userId);
        jdbc.update("DELETE FROM user_sessions WHERE user_id=?", userId);
        jdbc.update("UPDATE email_auth_challenges SET consumed_at=CURRENT_TIMESTAMP(3) WHERE user_id=? AND consumed_at IS NULL", userId);
    }

    public void logout(String authorization) {
        String token = bearerToken(authorization);
        if (token != null) {
            jdbc.update("DELETE FROM user_sessions WHERE token_hash = ?", sha256(token));
        }
    }

    public List<PublicUser> following(String authorization) {
        User current = require(authorization);
        return jdbc.query(
                """
                SELECT u.id, u.nickname, u.avatar_object_key, u.avatar_url, u.city, u.bio
                FROM follows f
                JOIN users u ON u.id = f.following_id
                WHERE f.follower_id = ? AND u.status = 'ACTIVE'
                ORDER BY u.nickname
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
                current.id()
        );
    }

    @Transactional
    public FollowResult toggleFollow(String authorization, String followingId) {
        User current = require(authorization);
        String targetId = followingId == null ? "" : followingId.trim();
        if (targetId.isEmpty() || targetId.equals(current.id())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "不能关注自己");
        }
        Integer targetCount = jdbc.queryForObject(
                "SELECT COUNT(*) FROM users WHERE id = ? AND status = 'ACTIVE'",
                Integer.class,
                targetId
        );
        if (targetCount == null || targetCount == 0) {
            throw new ApiException(HttpStatus.NOT_FOUND, "用户不存在");
        }
        int removed = jdbc.update(
                "DELETE FROM follows WHERE follower_id = ? AND following_id = ?",
                current.id(),
                targetId
        );
        if (removed > 0) {
            return new FollowResult(false);
        }
        jdbc.update(
                "INSERT INTO follows (follower_id, following_id) VALUES (?, ?)",
                current.id(),
                targetId
        );
        notifications.create(targetId, current.id(), "FOLLOW", null, null);
        return new FollowResult(true);
    }

    @Transactional
    public User updateAvatar(String authorization, String objectKey, String avatarUrl) {
        User current = require(authorization);
        String key = objectKey == null ? "" : objectKey.trim();
        String expectedOwner = "/" + current.id() + "/";
        if (!key.startsWith("photos/") || !key.contains(expectedOwner)
                || !key.matches(".*-avatar\\.(jpg|jpeg|png|webp|heic|heif)$")) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Invalid avatar object");
        }
        String fallbackUrl = avatarUrl == null ? "" : avatarUrl.trim();
        if (fallbackUrl.length() > 500) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Avatar URL is too long");
        }
        jdbc.update(
                "UPDATE users SET avatar_object_key = ?, avatar_url = ? WHERE id = ?",
                key, fallbackUrl, current.id()
        );
        return new User(
                current.id(), current.username(), current.email(), current.phone(),
                current.nickname(),
                first(oss.createDownloadUrl(key), fallbackUrl),
                current.city(), current.bio()
        );
    }

    @Transactional
    public User updateNickname(String authorization, String nickname) {
        User current = require(authorization);
        String normalizedName = text(nickname, 80, "昵称不能为空且不能超过 80 个字符");
        if (normalizedName.equals(current.nickname())) {
            return current;
        }
        if (nicknameExists(normalizedName, current.id())) {
            throw new ApiException(HttpStatus.CONFLICT, "昵称已被使用");
        }
        try {
            jdbc.update(
                    "UPDATE users SET nickname = ? WHERE id = ?",
                    normalizedName, current.id()
            );
        } catch (DuplicateKeyException error) {
            throw new ApiException(HttpStatus.CONFLICT, "昵称已被使用");
        }
        return new User(
                current.id(), current.username(), current.email(), current.phone(), normalizedName,
                current.avatarUrl(), current.city(), current.bio()
        );
    }

    @Transactional
    public User updateBio(String authorization, String bio) {
        User current = require(authorization);
        String normalizedBio = bio == null ? "" : bio.trim();
        if (normalizedBio.length() > 300) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "自我介绍不能超过 300 个字符");
        }
        jdbc.update(
                "UPDATE users SET bio = ? WHERE id = ?",
                normalizedBio, current.id()
        );
        return new User(
                current.id(), current.username(), current.email(), current.phone(),
                current.nickname(),
                current.avatarUrl(), current.city(), normalizedBio
        );
    }

    private AuthResult createSession(User user) {
        return createSession(user, false);
    }

    private AuthResult createSession(User user, boolean newlyRegistered) {
        String token = randomToken(32);
        Instant expiresAt = Instant.now().plus(30, ChronoUnit.DAYS);
        jdbc.update(
                "INSERT INTO user_sessions (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)",
                UUID.randomUUID().toString(), user.id(), sha256(token),
                java.sql.Timestamp.from(expiresAt)
        );
        return new AuthResult(token, expiresAt.toString(), user, newlyRegistered);
    }

    static String normalizeUsername(String username) {
        String value = username == null ? "" : username.trim().toLowerCase(Locale.ROOT);
        if (!value.matches("^[a-z][a-z0-9_]{3,23}$")) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "用户名须为 4–24 位，以字母开头，仅可包含小写字母、数字和下划线");
        }
        return value;
    }

    private boolean nicknameExists(String nickname, String excludedUserId) {
        Integer count;
        if (excludedUserId == null) {
            count = jdbc.queryForObject(
                    "SELECT COUNT(*) FROM users WHERE nickname = ?",
                    Integer.class,
                    nickname
            );
        } else {
            count = jdbc.queryForObject(
                    "SELECT COUNT(*) FROM users WHERE nickname = ? AND id <> ?",
                    Integer.class,
                    nickname,
                    excludedUserId
            );
        }
        return count != null && count > 0;
    }

    private void validatePassword(String password) {
        if (password == null || password.length() < 8 || password.length() > 128) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "密码须为 8–128 个字符");
        }
    }

    private String text(String value, int max, String message) {
        String normalized = value == null ? "" : value.trim();
        if (normalized.isEmpty() || normalized.length() > max) {
            throw new ApiException(HttpStatus.BAD_REQUEST, message);
        }
        return normalized;
    }

    private String passwordHash(String password, String salt) {
        try {
            PBEKeySpec spec = new PBEKeySpec(
                    password.toCharArray(),
                    Base64.getUrlDecoder().decode(salt),
                    PASSWORD_ITERATIONS,
                    256
            );
            byte[] hash = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
                    .generateSecret(spec).getEncoded();
            return Base64.getUrlEncoder().withoutPadding().encodeToString(hash);
        } catch (Exception error) {
            throw new IllegalStateException("Unable to hash password", error);
        }
    }

    private String randomToken(int bytes) {
        byte[] value = new byte[bytes];
        RANDOM.nextBytes(value);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(value);
    }

    private String sha256(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8));
            return java.util.HexFormat.of().formatHex(digest);
        } catch (Exception error) {
            throw new IllegalStateException("Unable to hash session token", error);
        }
    }

    private String bearerToken(String authorization) {
        if (authorization == null || !authorization.startsWith("Bearer ")) {
            return null;
        }
        String token = authorization.substring(7).trim();
        return token.isEmpty() ? null : token;
    }

    private String normalizeIp(String value) {
        String ip = value == null || value.isBlank() ? "unknown" : value.trim();
        return ip.length() > 64 ? ip.substring(0, 64) : ip;
    }

    private User mapUser(String id, String username, String email, String phone, String nickname,
                         String avatarObjectKey, String avatarUrl, String city, String bio) {
        return new User(
                id, username, email, phone, nickname,
                first(oss.createDownloadUrl(avatarObjectKey), avatarUrl),
                city, bio
        );
    }

    private String first(String preferred, String fallback) {
        return preferred == null || preferred.isBlank() ? fallback : preferred;
    }

    public record User(String id, String username, String email, String phone,
                       String nickname, String avatarUrl, String city, String bio) {}
    public record PublicUser(String id, String nickname, String avatarUrl,
                             String city, String bio) {}
    public record FollowResult(boolean following) {}
    public record AuthResult(String token, String expiresAt, User user,
                             boolean newlyRegistered) {}
    private record CredentialRow(User user, String salt, String passwordHash) {}
}
