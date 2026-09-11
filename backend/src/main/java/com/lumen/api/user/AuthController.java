package com.lumen.api.user;

import com.lumen.api.user.UserService.AuthResult;
import com.lumen.api.user.UserService.User;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.MediaType;
import java.util.Map;

@RestController
@RequestMapping("/api/auth")
public class AuthController {
    private final UserService users;
    private final ConsentService consents;
    private final EmailAuthService mail;
    private final AuthRateLimiter limits;

    public AuthController(UserService users, ConsentService consents, EmailAuthService mail, AuthRateLimiter limits) {
        this.users = users;
        this.consents = consents;
        this.mail = mail;
        this.limits = limits;
    }

    @GetMapping("/consent")
    ConsentService.ConsentDocument consent() {
        return consents.current();
    }

    @PostMapping("/register")
    ResponseEntity<AuthResult> register(
            @RequestBody RegisterRequest request,
            HttpServletRequest servletRequest
    ) {
        limits.check("register:ip:" + clientIp(servletRequest), 20, 3600);
        AuthResult result = users.register(
                request == null ? null : request.email(),
                request == null ? null : request.password(),
                request == null ? null : request.nickname(),
                request != null && request.consentAccepted(),
                request == null ? null : request.consentVersion(),
                clientIp(servletRequest),
                request == null ? null : request.verificationCode()
        );
        return ResponseEntity.status(201).body(result);
    }

    @PostMapping("/login")
    AuthResult login(@RequestBody LoginRequest request, HttpServletRequest servletRequest) {
        String account = request == null ? "" : (request.email() != null ? request.email() : request.username());
        limits.check("login:ip:" + clientIp(servletRequest), 60, 900);
        limits.check("login:account:" + (account == null ? "" : account.trim().toLowerCase(java.util.Locale.ROOT)), 15, 900);
        return users.login(
                account,
                request == null ? null : request.password()
        );
    }

    @PostMapping("/email-code")
    Map<String, String> emailCode(@RequestBody EmailRequest request, HttpServletRequest servletRequest) {
        mail.request(request == null ? null : request.email(), "REGISTER", clientIp(servletRequest));
        return Map.of("message", EmailAuthService.REGISTRATION_SENT_MESSAGE);
    }

    @PostMapping("/forgot-password")
    Map<String, String> forgotPassword(@RequestBody EmailRequest request, HttpServletRequest servletRequest) {
        mail.request(request == null ? null : request.email(), "RESET", clientIp(servletRequest));
        return Map.of("message", EmailAuthService.SENT_MESSAGE);
    }

    @PostMapping("/reset-password")
    Map<String, String> resetPassword(@RequestBody ResetRequest request, HttpServletRequest servletRequest) {
        limits.check("reset:ip:" + clientIp(servletRequest), 30, 900);
        users.resetPassword(request == null ? null : request.token(), request == null ? null : request.password());
        return Map.of("message", "密码已重置，请返回 Lumen 使用邮箱和新密码登录");
    }

    @PutMapping("/me/password")
    Map<String, String> changePassword(@RequestHeader(value="Authorization", required=false) String authorization,
            @RequestBody ChangePasswordRequest request, HttpServletRequest servletRequest) {
        var user = users.require(authorization);
        limits.check("change:user:" + user.id(), 10, 900);
        limits.check("change:ip:" + clientIp(servletRequest), 30, 900);
        users.changePassword(authorization, request == null ? null : request.oldPassword(), request == null ? null : request.newPassword());
        return Map.of("message", "密码已修改，请重新登录");
    }

    @GetMapping(value="/reset-password", produces=MediaType.TEXT_HTML_VALUE)
    ResponseEntity<ClassPathResource> resetPage() {
        return ResponseEntity.ok().header("Cache-Control", "no-store")
                .header("Referrer-Policy", "no-referrer")
                .header("X-Content-Type-Options", "nosniff")
                .header("Content-Security-Policy", "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
                .body(new ClassPathResource("auth/reset-password.html"));
    }

    @GetMapping(value="/reset-password.js", produces="text/javascript")
    ResponseEntity<ClassPathResource> resetScript() {
        return ResponseEntity.ok().header("Cache-Control", "no-store").header("X-Content-Type-Options", "nosniff")
                .body(new ClassPathResource("auth/reset-password.js"));
    }

    @GetMapping("/me")
    User me(@RequestHeader(value = "Authorization", required = false) String authorization) {
        return users.require(authorization);
    }

    @PutMapping("/me/avatar")
    User updateAvatar(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @RequestBody AvatarRequest request
    ) {
        return users.updateAvatar(
                authorization,
                request == null ? null : request.objectKey(),
                request == null ? null : request.avatarUrl()
        );
    }

    @PutMapping("/me/profile")
    User updateProfile(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @RequestBody ProfileRequest request
    ) {
        return users.updateNickname(
                authorization,
                request == null ? null : request.nickname()
        );
    }

    @PutMapping("/me/bio")
    User updateBio(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @RequestBody BioRequest request
    ) {
        return users.updateBio(
                authorization,
                request == null ? null : request.bio()
        );
    }

    @PostMapping("/logout")
    ResponseEntity<Void> logout(
            @RequestHeader(value = "Authorization", required = false) String authorization
    ) {
        users.logout(authorization);
        return ResponseEntity.noContent().build();
    }

    private String clientIp(HttpServletRequest request) {
        String remote = request == null ? "" : request.getRemoteAddr();
        if ("127.0.0.1".equals(remote) || "0:0:0:0:0:0:0:1".equals(remote)
                || "::1".equals(remote)) {
            String forwarded = request.getHeader("X-Forwarded-For");
            if (forwarded != null && !forwarded.isBlank()) {
                return forwarded.split(",", 2)[0].trim();
            }
        }
        return remote == null || remote.isBlank() ? "unknown" : remote;
    }

    record RegisterRequest(
            String email,
            String password,
            String nickname,
            boolean consentAccepted,
            String consentVersion,
            String verificationCode
    ) {}
    record LoginRequest(String email, String password, String username) {}
    record EmailRequest(String email) {}
    record ResetRequest(String token, String password) {}
    record ChangePasswordRequest(String oldPassword, String newPassword) {}
    record AvatarRequest(String objectKey, String avatarUrl) {}
    record ProfileRequest(String nickname) {}
    record BioRequest(String bio) {}
}
