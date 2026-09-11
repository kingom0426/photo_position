package com.lumen.api.user;

import com.lumen.api.common.ApiException;
import jakarta.annotation.PreDestroy;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.web.util.HtmlUtils;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@Service
public class EmailAuthService {
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final Logger LOG = LoggerFactory.getLogger(EmailAuthService.class);
    public static final String SENT_MESSAGE = "如果该邮箱符合条件，我们会发送邮件，请检查收件箱和垃圾邮件。";
    public static final String REGISTRATION_SENT_MESSAGE = "验证码邮件已提交发送，请检查收件箱和垃圾邮件。验证码 10 分钟内有效，请使用最新一封邮件中的验证码。";
    public static final String EMAIL_REGISTERED_MESSAGE = "该邮箱已注册，请直接登录；如果忘记密码，请通过“忘记密码”重置。";
    private final JdbcTemplate jdbc;
    private final AuthRateLimiter limits;
    private final JavaMailSender sender;
    private final String from;
    private final String baseUrl;
    private final String codeKey;
    private final TransactionTemplate tx;
    private final ThreadPoolExecutor delivery = new ThreadPoolExecutor(1, 2, 30, TimeUnit.SECONDS,
            new ArrayBlockingQueue<>(50), runnable -> {
                Thread thread = new Thread(runnable, "lumen-auth-mail");
                thread.setDaemon(true);
                return thread;
            });

    public EmailAuthService(JdbcTemplate jdbc, AuthRateLimiter limits, JavaMailSender sender,
            PlatformTransactionManager manager,
            @Value("${app.mail.from:}") String from,
            @Value("${app.mail.public-base-url:https://chenxi-edu.com}") String baseUrl,
            @Value("${spring.mail.password:}") String codeKey) {
        this.jdbc = jdbc;
        this.limits = limits;
        this.sender = sender;
        this.from = from;
        this.baseUrl = baseUrl.replaceAll("/+$", "");
        this.codeKey = codeKey;
        this.tx = new TransactionTemplate(manager);
    }

    public static String normalizeEmail(String raw) {
        String email = raw == null ? "" : raw.trim().toLowerCase(Locale.ROOT);
        if (email.length() > 254 || !email.matches("^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$")
                || email.indexOf('@') > 64 || email.startsWith(".") || email.contains("..") || email.contains(".@")) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "请输入有效的邮箱地址");
        }
        return email;
    }

    public void request(String rawEmail, String purpose, String ip) {
        String email = normalizeEmail(rawEmail);
        if (!List.of("REGISTER", "RESET").contains(purpose)) throw new IllegalArgumentException("Invalid mail purpose");
        limits.check("mail:ip:" + ip, 15, 3600);
        Integer existing = jdbc.queryForObject("SELECT COUNT(*) FROM users WHERE email = ?", Integer.class, email);
        if (purpose.equals("REGISTER") && existing != null && existing > 0) {
            throw new ApiException(HttpStatus.CONFLICT, EMAIL_REGISTERED_MESSAGE);
        }
        limits.check("mail:email:minute:" + email, 1, 60);
        limits.check("mail:email:hour:" + email, 5, 3600);
        limits.check("mail:global", 200, 3600);
        if (from.isBlank() || codeKey.isBlank() || !baseUrl.startsWith("https://")) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "邮件服务暂不可用，请稍后再试");
        }
        List<String> accounts = jdbc.query("SELECT id FROM users WHERE email = ? AND status = 'ACTIVE'",
                (rs, n) -> rs.getString(1), email);
        if (purpose.equals("RESET") && accounts.isEmpty()) return;
        String id = UUID.randomUUID().toString();
        boolean registration = purpose.equals("REGISTER");
        String secret = registration ? String.format(Locale.ROOT, "%06d", RANDOM.nextInt(1_000_000)) : randomToken();
        String digest = registration ? codeHash(id, secret) : AuthRateLimiter.hash(secret);
        tx.executeWithoutResult(status -> {
            jdbc.update("UPDATE email_auth_challenges SET consumed_at = CURRENT_TIMESTAMP(3) "
                    + "WHERE email = ? AND purpose = ? AND consumed_at IS NULL", email, purpose);
            // Share the database clock for creation and expiry, independent of JDBC time zones.
            jdbc.update("INSERT INTO email_auth_challenges (id,email,purpose,user_id,secret_hash,expires_at) "
                            + "VALUES (?,?,?,?,?,TIMESTAMPADD(SECOND,?,CURRENT_TIMESTAMP(3)))",
                    id, email, purpose, registration ? null : accounts.get(0), digest,
                    registration ? 600 : 1800);
        });
        String resetLink = baseUrl + "/api/auth/reset-password#token=" + secret;
        String body = registration
                ? "你的 Lumen 注册验证码：" + secret + "\n\n10 分钟内有效，请勿分享给他人。如果不是你本人操作，请忽略此邮件。"
                : "请打开以下链接，为你的 Lumen 账号设置新密码：\n\n" + resetLink
                    + "\n\n链接 30 分钟内有效，只能使用一次。重置后所有设备需要重新登录。"
                    + "\n如果不是你本人操作，请忽略此邮件，你的密码不会改变。";
        // Only hashes are persisted; the raw code/token lives in this bounded delivery task.
        try {
            delivery.execute(() -> deliver(id, email, registration ? "Lumen 邮箱注册验证码" : "Lumen 密码重置",
                    body, registration ? null : resetHtml(resetLink)));
        } catch (java.util.concurrent.RejectedExecutionException error) {
            jdbc.update("UPDATE email_auth_challenges SET delivery_status='FAILED' WHERE id=?", id);
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "邮件服务繁忙，请稍后再试");
        }
    }

    private void deliver(String id, String email, String subject, String body, String html) {
        try {
            if (html == null) {
                SimpleMailMessage message = new SimpleMailMessage();
                message.setFrom(from);
                message.setTo(email);
                message.setSubject(subject);
                message.setText(body);
                sender.send(message);
            } else {
                var message = sender.createMimeMessage();
                var helper = new MimeMessageHelper(message, MimeMessageHelper.MULTIPART_MODE_MIXED, "UTF-8");
                helper.setFrom(from, "Lumen");
                helper.setTo(email);
                helper.setSubject(subject);
                helper.setSentDate(new java.util.Date());
                // Explicit HTML anchors work even when the mailbox does not auto-link plain URLs.
                // Keep a plain-text alternative for clients that cannot render HTML.
                helper.setText(body, html);
                sender.send(message);
            }
            jdbc.update("UPDATE email_auth_challenges SET delivery_status='SENT' WHERE id=?", id);
            LOG.info("Authentication mail submitted: {}", id);
        } catch (Exception error) {
            jdbc.update("UPDATE email_auth_challenges SET delivery_status='FAILED' WHERE id=?", id);
            // Provider exceptions may contain email content or credentials; never log them.
            LOG.warn("Authentication mail delivery failed: {} ({})", id, error.getClass().getSimpleName());
        }
    }

    static String resetHtml(String resetLink) {
        String link = HtmlUtils.htmlEscape(resetLink, "UTF-8");
        return """
                <!doctype html>
                <html lang="zh-CN"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
                <body style="margin:0;padding:24px;background:#f5f5f3;font-family:Arial,'PingFang SC','Microsoft YaHei',sans-serif;color:#252525;">
                  <table role="presentation" width="100%%" cellpadding="0" cellspacing="0"><tr><td align="center">
                    <table role="presentation" width="100%%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:16px;"><tr><td style="padding:32px 24px;">
                      <p style="font-size:13px;letter-spacing:4px;color:#777777;">LUMEN</p>
                      <h1 style="font-size:24px;line-height:1.4;">重置你的密码</h1>
                      <p style="font-size:16px;line-height:1.7;">请点击下方按钮，为你的 Lumen 账号设置新密码。</p>
                      <table role="presentation" cellpadding="0" cellspacing="0" style="margin:24px 0;"><tr><td bgcolor="#292a28" style="border-radius:8px;">
                        <a href="%s" target="_blank" rel="noopener noreferrer" style="display:inline-block;padding:16px 32px;background:#292a28;border-radius:8px;color:#ffffff;text-decoration:none;font-size:16px;font-weight:bold;">重置密码</a>
                      </td></tr></table>
                      <p style="font-size:14px;line-height:1.7;">链接 30 分钟内有效，只能使用一次。重置后所有设备需要重新登录。</p>
                      <p style="font-size:14px;line-height:1.7;color:#666666;">如果按钮无法打开，请点击下方网址，或完整复制到浏览器地址栏：</p>
                      <p style="font-size:13px;line-height:1.7;word-break:break-all;overflow-wrap:anywhere;"><a href="%s" target="_blank" rel="noopener noreferrer" style="color:#245bba;text-decoration:underline;word-break:break-all;">%s</a></p>
                      <p style="font-size:13px;line-height:1.7;color:#777777;">如果不是你本人操作，请忽略此邮件，你的密码不会改变。请勿转发此邮件或分享重置链接。</p>
                    </td></tr></table>
                  </td></tr></table>
                </body></html>
                """.formatted(link, link, link);
    }

    /** Called inside registration's transaction; only successful registration consumes the code. */
    public void consumeRegistration(String email, String code) {
        limits.check("verify:email:" + email, 5, 600);
        if (code == null || !code.matches("^[0-9]{6}$")) throw codeError("请输入 6 位数字验证码");
        var rows = jdbc.query("SELECT id,secret_hash,delivery_status,consumed_at IS NOT NULL AS consumed,"
                + "expires_at<=CURRENT_TIMESTAMP(3) AS expired FROM email_auth_challenges WHERE email=? AND purpose='REGISTER' "
                + "ORDER BY created_at DESC LIMIT 1 FOR UPDATE", (rs, n) -> new RegistrationChallenge(
                        rs.getString("id"), rs.getString("secret_hash"), rs.getString("delivery_status"),
                        rs.getBoolean("consumed"), rs.getBoolean("expired")), email);
        if (rows.isEmpty()) throw codeError("请先获取邮箱验证码");
        var challenge = rows.get(0);
        if (challenge.consumed()) throw codeError("验证码已使用或失效，请重新获取");
        if (challenge.expired()) throw codeError("验证码已过期，请重新获取");
        if (challenge.status().equals("FAILED")) throw codeError("验证码邮件发送失败，请稍后重新获取");
        if (!challenge.status().equals("SENT")) throw codeError("验证码邮件正在发送，请稍后再试");
        if (!MessageDigest.isEqual(challenge.hash().getBytes(StandardCharsets.US_ASCII),
                codeHash(challenge.id(), code).getBytes(StandardCharsets.US_ASCII))) {
            throw codeError("验证码不正确，请输入最新一封邮件中的 6 位验证码");
        }
        jdbc.update("UPDATE email_auth_challenges SET consumed_at=CURRENT_TIMESTAMP(3) WHERE id=?", challenge.id());
    }

    private record RegistrationChallenge(String id, String hash, String status, boolean consumed, boolean expired) {}

    /** Locks token within the same transaction as password replacement and session revocation. */
    public String consumeReset(String token) {
        if (token == null || !token.matches("^[A-Za-z0-9_-]{43}$")) throw invalidToken();
        var rows = jdbc.query("SELECT c.id,c.user_id FROM email_auth_challenges c JOIN users u ON u.id=c.user_id "
                + "WHERE c.secret_hash=? AND c.purpose='RESET' AND c.delivery_status='SENT' "
                + "AND c.consumed_at IS NULL AND c.expires_at>CURRENT_TIMESTAMP(3) AND u.status='ACTIVE' "
                + "AND u.email=c.email LIMIT 1 FOR UPDATE",
                (rs, n) -> new String[]{rs.getString(1), rs.getString(2)}, AuthRateLimiter.hash(token));
        if (rows.isEmpty()) throw invalidToken();
        jdbc.update("UPDATE email_auth_challenges SET consumed_at=CURRENT_TIMESTAMP(3) WHERE id=?", rows.get(0)[0]);
        return rows.get(0)[1];
    }

    private String codeHash(String id, String code) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(codeKey.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return java.util.HexFormat.of().formatHex(mac.doFinal((id + ":" + code).getBytes(StandardCharsets.UTF_8)));
        } catch (Exception error) {
            throw new IllegalStateException("Unable to protect verification code", error);
        }
    }

    private String randomToken() {
        byte[] bytes = new byte[32];
        RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private ApiException codeError(String message) { return new ApiException(HttpStatus.BAD_REQUEST, message); }
    private ApiException invalidToken() { return new ApiException(HttpStatus.BAD_REQUEST, "重置链接无效或已过期，请重新申请"); }

    @PreDestroy
    public void close() { delivery.shutdown(); }
}
