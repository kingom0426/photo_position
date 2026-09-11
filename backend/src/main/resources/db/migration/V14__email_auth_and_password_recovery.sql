ALTER TABLE users
    ADD COLUMN email_verified_at TIMESTAMP(3) NULL COMMENT '邮箱完成所有权验证的时间';

CREATE TABLE email_auth_challenges (
    id CHAR(36) PRIMARY KEY,
    email VARCHAR(254) NOT NULL,
    purpose VARCHAR(16) NOT NULL,
    user_id VARCHAR(64) NULL,
    secret_hash CHAR(64) NOT NULL,
    delivery_status VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    expires_at TIMESTAMP(3) NOT NULL,
    consumed_at TIMESTAMP(3) NULL,
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    INDEX idx_email_challenge (email, purpose, created_at),
    INDEX idx_email_secret (secret_hash),
    INDEX idx_email_expiry (expires_at),
    CONSTRAINT fk_email_challenge_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE auth_rate_limits (
    bucket_key CHAR(64) PRIMARY KEY,
    hits INT NOT NULL,
    expires_at TIMESTAMP(3) NOT NULL,
    INDEX idx_auth_rate_expiry (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
