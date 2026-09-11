package com.lumen.api.user;

import com.lumen.api.common.ApiException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.Timestamp;
import java.time.Instant;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

/** Shared, atomic limits survive restarts and work across backend instances. */
@Service
public class AuthRateLimiter {
    private final JdbcTemplate jdbc;
    private final TransactionTemplate tx;

    public AuthRateLimiter(JdbcTemplate jdbc, PlatformTransactionManager manager) {
        this.jdbc = jdbc;
        this.tx = new TransactionTemplate(manager);
        tx.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    public void check(String scope, int maximum, int seconds) {
        long window = Instant.now().getEpochSecond() / seconds;
        String key = hash(scope + ":" + window);
        Integer hits = tx.execute(status -> {
            jdbc.update("INSERT INTO auth_rate_limits (bucket_key, hits, expires_at) VALUES (?, 1, ?) "
                    + "ON DUPLICATE KEY UPDATE hits = hits + 1", key,
                    Timestamp.from(Instant.ofEpochSecond((window + 1) * seconds)));
            return jdbc.queryForObject("SELECT hits FROM auth_rate_limits WHERE bucket_key = ?", Integer.class, key);
        });
        if (hits != null && hits > maximum) {
            throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "操作过于频繁，请稍后再试");
        }
    }

    static String hash(String value) {
        try {
            return java.util.HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception error) {
            throw new IllegalStateException("Unable to hash authentication key", error);
        }
    }
}
