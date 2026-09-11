package com.lumen.api.admin;

import com.lumen.api.common.ApiException;
import com.lumen.api.user.AuthRateLimiter;
import com.lumen.api.user.UserService;
import jakarta.servlet.http.HttpServletRequest;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.HexFormat;
import java.util.Locale;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseCookie;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class AdminAuth {
    static final String COOKIE = "lumen_admin";
    private final UserService users;
    private final JdbcTemplate jdbc;
    private final AuthRateLimiter limits;
    private final String origin;

    public AdminAuth(UserService users, JdbcTemplate jdbc, AuthRateLimiter limits,
            @Value("${app.mail.public-base-url:https://chenxi-edu.com}") String origin) {
        this.users = users; this.jdbc = jdbc; this.limits = limits;
        this.origin = origin.replaceAll("/+$", "");
    }

    public void checkMutation(HttpServletRequest request) {
        // Browsers cannot send this custom header cross-origin without a CORS preflight.
        // Admin endpoints deliberately never allow credentialed cross-origin access.
        String source = request.getHeader("Origin");
        if (!"1".equals(request.getHeader("X-Lumen-Admin")) || (source != null && !source.equals(origin))) {
            throw new ApiException(HttpStatus.FORBIDDEN, "请求来源无效，请刷新后台后重试");
        }
    }

    public UserService.AuthResult login(String email, String password, HttpServletRequest request) {
        checkMutation(request);
        String account = email == null ? "" : email.trim().toLowerCase(Locale.ROOT);
        limits.check("login:ip:" + request.getRemoteAddr(), 60, 900);
        limits.check("login:account:" + account, 15, 900);
        var result = users.login(account, password);
        if (!isAdmin(result.user().id())) {
            users.logout("Bearer " + result.token());
            throw new ApiException(HttpStatus.FORBIDDEN, "该账号没有后台管理权限，请联系管理员");
        }
        // The database expiry, not only the browser cookie, limits this session to eight hours.
        jdbc.update("UPDATE user_sessions SET expires_at=TIMESTAMPADD(HOUR,8,CURRENT_TIMESTAMP(3)) WHERE token_hash=?", hash(result.token()));
        return result;
    }

    public UserService.User require(HttpServletRequest request) {
        var user = users.require(authorization(request));
        if (!isAdmin(user.id())) throw new ApiException(HttpStatus.FORBIDDEN, "该账号没有后台管理权限");
        return user;
    }

    private boolean isAdmin(String id) {
        return jdbc.queryForObject("SELECT COUNT(*) FROM admin_members a JOIN users u ON u.id=a.user_id "
                + "WHERE a.user_id=? AND u.email_verified_at IS NOT NULL AND u.status='ACTIVE'", Integer.class, id) > 0;
    }

    public void logout(HttpServletRequest request) {
        checkMutation(request);
        users.logout(authorization(request));
    }

    private String authorization(HttpServletRequest request) {
        if (request.getCookies() == null) return null;
        return Arrays.stream(request.getCookies()).filter(c -> COOKIE.equals(c.getName()))
                .map(c -> "Bearer " + c.getValue()).findFirst().orElse(null);
    }

    public String cookie(String token) {
        return ResponseCookie.from(COOKIE, token).httpOnly(true).secure(true).sameSite("Strict")
                .path("/api/admin").maxAge(token.isEmpty() ? 0 : 8 * 3600).build().toString();
    }

    private String hash(String token) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8))); }
        catch (Exception error) { throw new IllegalStateException(error); }
    }
}
