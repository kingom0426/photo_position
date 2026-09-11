-- With explicit_defaults_for_timestamp=OFF, the first TIMESTAMP acquired an
-- implicit ON UPDATE clause, expiring a challenge as soon as SMTP completed.
-- Explicit defaults remove that clause; missing expiry fails closed (expires now).
ALTER TABLE email_auth_challenges
    MODIFY COLUMN expires_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3);
ALTER TABLE auth_rate_limits
    MODIFY COLUMN expires_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3);
ALTER TABLE user_sessions
    MODIFY COLUMN expires_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) COMMENT '会话过期时间';
