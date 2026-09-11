CREATE TABLE admin_members (
    user_id VARCHAR(64) PRIMARY KEY,
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    CONSTRAINT fk_admin_member_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE admin_audit_logs (
    id CHAR(36) PRIMARY KEY,
    actor_id VARCHAR(64) NOT NULL,
    target_type VARCHAR(16) NOT NULL,
    target_id CHAR(36) NOT NULL,
    action VARCHAR(16) NOT NULL,
    target_label VARCHAR(200) NOT NULL,
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    INDEX idx_admin_audit_target (target_type, target_id),
    INDEX idx_admin_audit_time (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
