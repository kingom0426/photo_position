ALTER TABLE users
    ADD COLUMN phone VARCHAR(20) NULL AFTER email,
    ADD UNIQUE KEY uq_users_phone (phone);

CREATE TABLE sms_send_attempts (
    id CHAR(36) PRIMARY KEY,
    phone VARCHAR(20) NOT NULL,
    request_ip VARCHAR(64) NOT NULL,
    status ENUM('PENDING','SENT','FAILED') NOT NULL DEFAULT 'PENDING',
    provider_request_id VARCHAR(128) NULL,
    provider_message VARCHAR(500) NULL,
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    INDEX idx_sms_attempt_phone_time (phone, created_at),
    INDEX idx_sms_attempt_ip_time (request_ip, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='短信验证码发送尝试与限频审计';

CREATE TABLE sms_verification_codes (
    id CHAR(36) PRIMARY KEY,
    phone VARCHAR(20) NOT NULL,
    code_salt VARCHAR(64) NOT NULL,
    code_hash CHAR(64) NOT NULL,
    failed_attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
    expires_at TIMESTAMP(3) NOT NULL,
    consumed_at TIMESTAMP(3) NULL,
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    INDEX idx_sms_code_lookup (phone, created_at),
    INDEX idx_sms_code_expiry (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='一次性短信验证码，仅保存加盐摘要';

CREATE TABLE user_consent_acceptances (
    id CHAR(36) PRIMARY KEY,
    user_id VARCHAR(64) NOT NULL,
    consent_type VARCHAR(64) NOT NULL,
    consent_version VARCHAR(32) NOT NULL,
    document_sha256 CHAR(64) NOT NULL,
    accepted_ip VARCHAR(64) NOT NULL,
    accepted_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    UNIQUE KEY uq_user_consent_version (user_id, consent_type, consent_version),
    CONSTRAINT fk_consent_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='用户协议签署留痕';
