ALTER TABLE users
    ADD COLUMN email VARCHAR(254) NULL,
    ADD COLUMN password_salt VARCHAR(64) NULL,
    ADD COLUMN password_hash VARCHAR(128) NULL,
    ADD UNIQUE KEY uq_users_email (email);

ALTER TABLE posts
    ADD COLUMN display_image_object_key VARCHAR(512) NULL AFTER image_url,
    ADD COLUMN thumbnail_object_key VARCHAR(512) NULL AFTER display_image_url;

CREATE TABLE user_sessions (
    id CHAR(36) PRIMARY KEY,
    user_id VARCHAR(64) NOT NULL,
    token_hash CHAR(64) NOT NULL,
    expires_at TIMESTAMP(3) NOT NULL,
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    UNIQUE KEY uq_user_sessions_token (token_hash),
    INDEX idx_user_sessions_user (user_id, expires_at),
    CONSTRAINT fk_sessions_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

DELETE FROM users
WHERE id IN ('me', 'u2', 'u3', 'u4')
  AND NOT EXISTS (SELECT 1 FROM posts WHERE posts.author_id = users.id);
