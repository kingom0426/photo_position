package com.lumen.api.user;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.lumen.api.common.ApiException;
import com.lumen.api.notification.NotificationService;
import com.lumen.api.oss.OssService;
import jakarta.mail.Multipart;
import jakarta.mail.Part;
import jakarta.mail.Session;
import jakarta.mail.internet.MimeMessage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.util.Properties;
import java.util.UUID;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.transaction.annotation.AnnotationTransactionAttributeSource;
import org.springframework.transaction.interceptor.TransactionInterceptor;

class EmailAuthFlowTest {
    JdbcTemplate jdbc;
    EmailAuthService mail;
    AuthRateLimiter limits;
    UserService users;
    JavaMailSender sender;
    LinkedBlockingQueue<DeliveredMail> sent;
    record DeliveredMail(String text, String html) { String getText() { return text; } }
    static final String EMAIL = "owner@example.com";
    static final String PASSWORD = "Initial-test-password9!";

    @BeforeEach
    void setup() {
        var ds = new DriverManagerDataSource("jdbc:h2:mem:" + UUID.randomUUID() + ";MODE=MySQL;DB_CLOSE_DELAY=-1", "sa", "");
        jdbc = new JdbcTemplate(ds);
        jdbc.execute("CREATE TABLE users (id VARCHAR(64) PRIMARY KEY, username VARCHAR(32), email VARCHAR(254) UNIQUE, "
                + "phone VARCHAR(20), nickname VARCHAR(80) UNIQUE, avatar_object_key VARCHAR(512), avatar_url VARCHAR(512), "
                + "city VARCHAR(80), bio VARCHAR(500), password_salt VARCHAR(64), password_hash VARCHAR(128), "
                + "status VARCHAR(16) DEFAULT 'ACTIVE', email_verified_at TIMESTAMP, updated_at TIMESTAMP)");
        jdbc.execute("CREATE TABLE user_sessions (id VARCHAR(36) PRIMARY KEY, user_id VARCHAR(64), token_hash CHAR(64), expires_at TIMESTAMP)");
        jdbc.execute("CREATE TABLE user_consent_acceptances (id VARCHAR(36),user_id VARCHAR(64),consent_type VARCHAR(64),consent_version VARCHAR(32),document_sha256 CHAR(64),accepted_ip VARCHAR(64))");
        jdbc.execute("CREATE TABLE email_auth_challenges (id CHAR(36) PRIMARY KEY,email VARCHAR(254),purpose VARCHAR(16),user_id VARCHAR(64),secret_hash CHAR(64),delivery_status VARCHAR(16) DEFAULT 'PENDING',expires_at TIMESTAMP,consumed_at TIMESTAMP,created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
        jdbc.execute("CREATE TABLE auth_rate_limits (bucket_key CHAR(64) PRIMARY KEY,hits INT,expires_at TIMESTAMP)");
        var manager = new DataSourceTransactionManager(ds);
        limits = new AuthRateLimiter(jdbc, manager);
        sender = mock(JavaMailSender.class);
        sent = new LinkedBlockingQueue<>();
        doAnswer(invocation -> { sent.add(new DeliveredMail(invocation.getArgument(0, SimpleMailMessage.class).getText(), null)); return null; })
                .when(sender).send(any(SimpleMailMessage.class));
        when(sender.createMimeMessage()).thenAnswer(invocation -> new MimeMessage(Session.getInstance(new Properties())));
        doAnswer(invocation -> {
            MimeMessage message = invocation.getArgument(0, MimeMessage.class);
            var wire = new ByteArrayOutputStream();
            message.saveChanges();
            message.writeTo(wire);
            var decoded = new MimeMessage(Session.getInstance(new Properties()), new ByteArrayInputStream(wire.toByteArray()));
            assertThat(decoded.getSubject()).isEqualTo("Lumen 密码重置");
            sent.add(new DeliveredMail(partText(decoded, "text/plain"), partText(decoded, "text/html")));
            return null;
        }).when(sender).send(any(MimeMessage.class));
        mail = new EmailAuthService(jdbc, limits, sender, manager, "lumen@example.com", "https://example.com", "test-only-hmac-secret");
        var target = new UserService(jdbc, mock(OssService.class), mock(NotificationService.class), new ConsentService(), mail);
        var factory = new ProxyFactory(target);
        factory.addAdvice(new TransactionInterceptor(manager, new AnnotationTransactionAttributeSource()));
        users = (UserService) factory.getProxy();
    }

    @AfterEach
    void close() { mail.close(); }

    private DeliveredMail awaitMail() throws Exception {
        var message = sent.poll(5, TimeUnit.SECONDS);
        assertThat(message).isNotNull();
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        while (jdbc.queryForObject("SELECT COUNT(*) FROM email_auth_challenges WHERE delivery_status='PENDING'", Integer.class) > 0
                && System.nanoTime() < deadline) Thread.sleep(5);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM email_auth_challenges WHERE delivery_status='PENDING'", Integer.class)).isZero();
        return message;
    }

    private static String partText(Part part, String mimeType) throws Exception {
        if (part.isMimeType(mimeType)) return (String) part.getContent();
        if (part.isMimeType("multipart/*")) {
            Multipart multipart = (Multipart) part.getContent();
            for (int i = 0; i < multipart.getCount(); i++) {
                String text = partText(multipart.getBodyPart(i), mimeType);
                if (text != null) return text;
            }
        }
        return null;
    }

    private String code() throws Exception {
        mail.request(EMAIL, "REGISTER", "test-ip");
        var matcher = Pattern.compile("[0-9]{6}").matcher(awaitMail().getText());
        assertThat(matcher.find()).isTrue();
        return matcher.group();
    }

    private UserService.AuthResult register(String code) {
        return users.register(EMAIL, PASSWORD, "测试用户", true, ConsentService.VERSION, "test-ip", code);
    }

    private String resetToken() throws Exception {
        jdbc.update("DELETE FROM auth_rate_limits");
        mail.request(EMAIL, "RESET", "test-ip");
        var message = awaitMail();
        var matcher = Pattern.compile("#token=([A-Za-z0-9_-]{43})").matcher(message.getText());
        assertThat(matcher.find()).isTrue();
        String link = "https://example.com/api/auth/reset-password#token=" + matcher.group(1);
        assertThat(message.html()).contains("href=\"" + link + "\"", ">重置密码</a>", "30 分钟", "完整复制");
        assertThat(message.html().split(Pattern.quote("href=\"" + link + "\""), -1)).hasSize(3);
        return matcher.group(1);
    }

    @Test
    void deliveryAndConsumptionPreserveTenMinuteExpiry() throws Exception {
        String value = code();
        assertThat(jdbc.queryForObject("SELECT TIMESTAMPDIFF(SECOND,created_at,expires_at) FROM email_auth_challenges", Long.class))
                .isEqualTo(600L);
        var expiry = jdbc.queryForObject("SELECT expires_at FROM email_auth_challenges", java.sql.Timestamp.class);
        register(value);
        assertThat(jdbc.queryForObject("SELECT expires_at FROM email_auth_challenges", java.sql.Timestamp.class)).isEqualTo(expiry);
        resetToken();
        assertThat(jdbc.queryForObject("SELECT TIMESTAMPDIFF(SECOND,created_at,expires_at) FROM email_auth_challenges WHERE purpose='RESET'", Long.class))
                .isEqualTo(1800L);
    }

    @Test
    void registeredEmailHasClearMessageEvenWithMissingCodeOrResendCooldown() throws Exception {
        register(code());
        assertThatThrownBy(() -> register(null)).isInstanceOf(ApiException.class)
                .hasMessage(EmailAuthService.EMAIL_REGISTERED_MESSAGE);
        assertThatThrownBy(() -> mail.request(EMAIL.toUpperCase(), "REGISTER", "test-ip"))
                .isInstanceOf(ApiException.class).hasMessage(EmailAuthService.EMAIL_REGISTERED_MESSAGE);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM email_auth_challenges", Integer.class)).isEqualTo(1);
    }

    @Test
    void registrationExplainsMissingWrongPendingFailedAndExpiredCodes() throws Exception {
        assertThatThrownBy(() -> register("123456")).hasMessage("请先获取邮箱验证码");
        String value = code();
        String wrong = value.equals("123456") ? "654321" : "123456";
        assertThatThrownBy(() -> register(wrong)).hasMessageContaining("验证码不正确");
        jdbc.update("UPDATE email_auth_challenges SET delivery_status='PENDING'");
        assertThatThrownBy(() -> register(value)).hasMessageContaining("正在发送");
        jdbc.update("UPDATE email_auth_challenges SET delivery_status='FAILED'");
        assertThatThrownBy(() -> register(value)).hasMessageContaining("发送失败");
        jdbc.update("UPDATE email_auth_challenges SET delivery_status='SENT',expires_at=TIMESTAMP '2000-01-01 00:00:00'");
        assertThatThrownBy(() -> register(value)).hasMessageContaining("已过期");
    }

    @Test
    void resetHtmlEscapesAttributeAndTextContent() {
        String html = EmailAuthService.resetHtml("https://example.com/reset?a=1&b=\"<test>\"");
        assertThat(html).contains("a=1&amp;b=&quot;&lt;test&gt;&quot;").doesNotContain("<test>");
        assertThat(html).doesNotContain("<script", "<img", "<form");
    }

    @Test
    void registerRequiresVerificationAndKeepsEmailPrivateFromNickname() throws Exception {
        assertThatThrownBy(() -> register("000000")).isInstanceOf(ApiException.class);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM users", Integer.class)).isZero();
        String code = code();
        var result = users.register(" OWNER@EXAMPLE.COM ", PASSWORD, "", true, ConsentService.VERSION, "test-ip", code);
        assertThat(result.user().email()).isEqualTo(EMAIL);
        assertThat(result.user().nickname()).startsWith("摄影者").doesNotContain("owner");
        assertThat(jdbc.queryForObject("SELECT email_verified_at FROM users", java.sql.Timestamp.class)).isNotNull();
        assertThat(jdbc.queryForObject("SELECT secret_hash FROM email_auth_challenges", String.class)).hasSize(64).isNotEqualTo(code);
        assertThatThrownBy(() -> register(code)).isInstanceOf(ApiException.class);
        assertThat(users.login("OWNER@example.com", PASSWORD).user().id()).isEqualTo(result.user().id());
    }

    @Test
    void passwordResetIsSingleUseAndRevokesEverySession() throws Exception {
        var account = register(code());
        var secondSession = users.login(EMAIL, PASSWORD);
        String token = resetToken();
        String replacement = "New-test-password9!";
        users.resetPassword(token, replacement);
        assertThat(users.optional("Bearer " + account.token())).isNull();
        assertThat(users.optional("Bearer " + secondSession.token())).isNull();
        assertThatThrownBy(() -> users.login(EMAIL, PASSWORD)).isInstanceOf(ApiException.class);
        assertThat(users.login(EMAIL, replacement).user().id()).isEqualTo(account.user().id());
        assertThatThrownBy(() -> users.resetPassword(token, "Another-password9!")).isInstanceOf(ApiException.class);
    }

    @Test
    void expiredAndAlteredTokensCannotChangePassword() throws Exception {
        register(code());
        String token = resetToken();
        assertThatThrownBy(() -> users.resetPassword("x" + token.substring(1, 42) + "z", "New-password9!"))
                .isInstanceOf(ApiException.class);
        jdbc.update("UPDATE email_auth_challenges SET expires_at=TIMESTAMP '2000-01-01 00:00:00' WHERE purpose='RESET'");
        assertThatThrownBy(() -> users.resetPassword(token, "New-password9!")).isInstanceOf(ApiException.class);
        assertThat(users.login(EMAIL, PASSWORD)).isNotNull();
    }

    @Test
    void wrongOldPasswordDoesNotLogOutUserButSuccessfulChangeDoes() throws Exception {
        var account = register(code());
        String token = resetToken();
        assertThatThrownBy(() -> users.changePassword("Bearer " + account.token(), "Wrong-password9!", "New-password9!"))
                .isInstanceOf(ApiException.class);
        assertThat(users.optional("Bearer " + account.token())).isNotNull();
        users.changePassword("Bearer " + account.token(), PASSWORD, "New-password9!");
        assertThat(users.optional("Bearer " + account.token())).isNull();
        assertThatThrownBy(() -> users.resetPassword(token, "Other-password9!")).isInstanceOf(ApiException.class);
        assertThat(users.login(EMAIL, "New-password9!")).isNotNull();
    }

    @Test
    void verificationFailuresRemainLimitedEvenWhenRegistrationRollsBack() throws Exception {
        String correct = code();
        String wrong = correct.equals("000000") ? "111111" : "000000";
        for (int i = 0; i < 5; i++) assertThatThrownBy(() -> register(wrong)).isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> register(correct)).isInstanceOf(ApiException.class).hasMessageContaining("频繁");
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM users", Integer.class)).isZero();
    }

    @Test
    void invalidNicknameRollsBackVerificationConsumption() throws Exception {
        String value = code();
        jdbc.update("INSERT INTO users(id,email,nickname) VALUES('other','other@example.com','测试用户')");
        assertThatThrownBy(() -> register(value)).isInstanceOf(ApiException.class).hasMessageContaining("昵称");
        assertThat(jdbc.queryForObject("SELECT consumed_at FROM email_auth_challenges", java.sql.Timestamp.class)).isNull();
        assertThat(users.register(EMAIL, PASSWORD, "另一个昵称", true, ConsentService.VERSION, "test-ip", value)).isNotNull();
    }

    @Test
    void unknownResetAccountDoesNotSendMailAndIsStillRateLimited() {
        mail.request(EMAIL, "RESET", "test-ip");
        verifyNoInteractions(sender);
        assertThatThrownBy(() -> mail.request(EMAIL, "RESET", "test-ip")).isInstanceOf(ApiException.class).hasMessageContaining("频繁");
    }

    @Test
    void malformedEmailsAreRejected() {
        for (String email : new String[]{"x", "a@localhost", "a..b@example.com", ".a@example.com", "a@-example.com", "a@example.com\r\nBcc:victim@example.com"}) {
            assertThatThrownBy(() -> EmailAuthService.normalizeEmail(email)).isInstanceOf(ApiException.class);
        }
        assertThat(EmailAuthService.normalizeEmail(" Person+tag@Example.com ")).isEqualTo("person+tag@example.com");
    }

    @Test
    void smtpFailureNeverActivatesChallenge() throws Exception {
        doThrow(new org.springframework.mail.MailSendException("test failure")).when(sender).send(any(SimpleMailMessage.class));
        mail.request(EMAIL, "REGISTER", "test-ip");
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        while (jdbc.queryForObject("SELECT COUNT(*) FROM email_auth_challenges WHERE delivery_status='FAILED'", Integer.class) == 0
                && System.nanoTime() < deadline) Thread.sleep(5);
        assertThat(jdbc.queryForObject("SELECT delivery_status FROM email_auth_challenges", String.class)).isEqualTo("FAILED");
        assertThatThrownBy(() -> register("000000")).isInstanceOf(ApiException.class);
    }
}
