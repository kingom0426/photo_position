ALTER TABLE users
    ADD COLUMN username VARCHAR(32) NULL AFTER id,
    ADD UNIQUE KEY uq_users_username (username);

ALTER TABLE users
    MODIFY COLUMN password_salt VARCHAR(64) NULL COMMENT 'PBKDF2 密码盐',
    MODIFY COLUMN password_hash VARCHAR(128) NULL COMMENT 'PBKDF2 密码哈希';
