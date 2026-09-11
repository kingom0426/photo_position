CREATE TABLE IF NOT EXISTS post_tags (
    post_id CHAR(36) NOT NULL,
    tag VARCHAR(40) NOT NULL,
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (post_id, tag),
    CONSTRAINT fk_post_tags_post FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
    INDEX idx_post_tags_tag (tag, post_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS notifications (
    id CHAR(36) PRIMARY KEY,
    recipient_id VARCHAR(64) NOT NULL,
    actor_id VARCHAR(64) NOT NULL,
    type ENUM('ASSIGNMENT','COMMENT','LIKE','FOLLOW') NOT NULL,
    target_post_id CHAR(36) NULL,
    source_post_id CHAR(36) NULL,
    read_at TIMESTAMP(3) NULL,
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    CONSTRAINT fk_notifications_recipient FOREIGN KEY (recipient_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_notifications_actor FOREIGN KEY (actor_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_notifications_target_post FOREIGN KEY (target_post_id) REFERENCES posts(id) ON DELETE CASCADE,
    CONSTRAINT fk_notifications_source_post FOREIGN KEY (source_post_id) REFERENCES posts(id) ON DELETE CASCADE,
    INDEX idx_notifications_recipient (recipient_id, read_at, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT IGNORE INTO post_tags (post_id, tag)
SELECT id, '夜景'
FROM posts
WHERE deleted_at IS NULL
  AND (title LIKE '%夜%' OR description LIKE '%夜%' OR shooting_notes LIKE '%夜%');

INSERT IGNORE INTO post_tags (post_id, tag)
SELECT id, '建筑'
FROM posts
WHERE deleted_at IS NULL
  AND (title LIKE '%建筑%' OR description LIKE '%建筑%' OR title LIKE '%SOHO%' OR description LIKE '%楼%');

INSERT IGNORE INTO post_tags (post_id, tag)
SELECT p.id, '手机可拍'
FROM posts p
JOIN capture_metadata m ON m.post_id = p.id
WHERE p.deleted_at IS NULL
  AND (LOWER(m.camera_display) LIKE '%iphone%'
       OR LOWER(m.camera_display) LIKE '%huawei%'
       OR LOWER(m.camera_display) LIKE '%xiaomi%'
       OR LOWER(m.camera_display) LIKE '%oppo%'
       OR LOWER(m.camera_display) LIKE '%vivo%'
       OR LOWER(m.camera_display) LIKE '%pixel%');
