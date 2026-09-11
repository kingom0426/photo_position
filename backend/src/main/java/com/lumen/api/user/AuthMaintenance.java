package com.lumen.api.user;

import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;

@Configuration
@EnableScheduling
public class AuthMaintenance {
    private final JdbcTemplate jdbc;
    public AuthMaintenance(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    @Scheduled(initialDelay = 60000, fixedDelay = 3600000)
    public void purgeExpiredAuthenticationRecords() {
        jdbc.update("DELETE FROM auth_rate_limits WHERE expires_at < CURRENT_TIMESTAMP(3) - INTERVAL 1 DAY");
        jdbc.update("DELETE FROM email_auth_challenges WHERE expires_at < CURRENT_TIMESTAMP(3) - INTERVAL 7 DAY");
    }
}
