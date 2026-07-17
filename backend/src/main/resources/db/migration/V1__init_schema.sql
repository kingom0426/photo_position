CREATE TABLE IF NOT EXISTS users (
    id VARCHAR(64) PRIMARY KEY,
    nickname VARCHAR(80) NOT NULL,
    avatar_url VARCHAR(500) NULL,
    bio VARCHAR(500) NOT NULL DEFAULT '',
    city VARCHAR(80) NOT NULL DEFAULT '',
    status ENUM('ACTIVE','SUSPENDED','DELETED') NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS posts (
    id CHAR(36) PRIMARY KEY,
    author_id VARCHAR(64) NOT NULL,
    kind ENUM('ORIGINAL','ASSIGNMENT') NOT NULL,
    original_post_id CHAR(36) NULL,
    title VARCHAR(120) NOT NULL,
    description TEXT NOT NULL,
    image_object_key VARCHAR(512) NULL,
    image_url VARCHAR(1000) NULL,
    display_image_url VARCHAR(1000) NULL,
    thumbnail_url VARCHAR(1000) NULL,
    allow_remake BOOLEAN NOT NULL DEFAULT TRUE,
    visibility ENUM('PUBLIC','PRIVATE') NOT NULL DEFAULT 'PUBLIC',
    review_status ENUM('PENDING','APPROVED','REJECTED') NOT NULL DEFAULT 'APPROVED',
    shooting_notes TEXT NOT NULL,
    editing_notes TEXT NOT NULL,
    reused_notes TEXT NOT NULL,
    adjusted_notes TEXT NOT NULL,
    assignment_notes TEXT NOT NULL,
    is_recommended BOOLEAN NOT NULL DEFAULT FALSE,
    like_count INT UNSIGNED NOT NULL DEFAULT 0,
    comment_count INT UNSIGNED NOT NULL DEFAULT 0,
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at TIMESTAMP(3) NULL,
    CONSTRAINT fk_posts_author FOREIGN KEY (author_id) REFERENCES users(id),
    CONSTRAINT fk_posts_original FOREIGN KEY (original_post_id) REFERENCES posts(id),
    INDEX idx_posts_feed (visibility, review_status, deleted_at, created_at),
    INDEX idx_posts_author (author_id, created_at),
    INDEX idx_posts_original (original_post_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS capture_metadata (
    post_id CHAR(36) PRIMARY KEY,
    camera_make VARCHAR(120) NOT NULL DEFAULT '',
    camera_model VARCHAR(160) NOT NULL DEFAULT '',
    camera_display VARCHAR(240) NOT NULL DEFAULT '',
    lens_model VARCHAR(240) NOT NULL DEFAULT '',
    focal_length_mm DECIMAL(8,2) NULL,
    aperture DECIMAL(6,2) NULL,
    shutter_seconds DECIMAL(14,8) NULL,
    iso INT UNSIGNED NULL,
    exposure_compensation DECIMAL(6,2) NULL,
    captured_at DATETIME NULL,
    source ENUM('EXIF','USER_CONFIRMED','MANUAL') NOT NULL DEFAULT 'MANUAL',
    raw_exif JSON NULL,
    CONSTRAINT fk_metadata_post FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS post_locations (
    post_id CHAR(36) PRIMARY KEY,
    place_name VARCHAR(200) NOT NULL DEFAULT '',
    city VARCHAR(80) NOT NULL DEFAULT '',
    district VARCHAR(100) NOT NULL DEFAULT '',
    privacy_level ENUM('EXACT','APPROXIMATE','PRIVATE') NOT NULL DEFAULT 'PRIVATE',
    latitude DECIMAL(10,7) NULL,
    longitude DECIMAL(10,7) NULL,
    public_latitude DECIMAL(10,7) NULL,
    public_longitude DECIMAL(10,7) NULL,
    shooting_advice VARCHAR(300) NOT NULL DEFAULT '',
    safety_status ENUM('NORMAL','CAUTION','RESTRICTED') NOT NULL DEFAULT 'NORMAL',
    CONSTRAINT fk_location_post FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
    INDEX idx_location_public (city, privacy_level, public_latitude, public_longitude)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS post_likes (
    user_id VARCHAR(64) NOT NULL,
    post_id CHAR(36) NOT NULL,
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (user_id, post_id),
    CONSTRAINT fk_likes_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_likes_post FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS favorites (
    user_id VARCHAR(64) NOT NULL,
    post_id CHAR(36) NOT NULL,
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (user_id, post_id),
    CONSTRAINT fk_favorites_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_favorites_post FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS comments (
    id CHAR(36) PRIMARY KEY,
    post_id CHAR(36) NOT NULL,
    author_id VARCHAR(64) NOT NULL,
    parent_id CHAR(36) NULL,
    content VARCHAR(1000) NOT NULL,
    status ENUM('VISIBLE','HIDDEN','DELETED') NOT NULL DEFAULT 'VISIBLE',
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    CONSTRAINT fk_comments_post FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE,
    CONSTRAINT fk_comments_author FOREIGN KEY (author_id) REFERENCES users(id),
    CONSTRAINT fk_comments_parent FOREIGN KEY (parent_id) REFERENCES comments(id),
    INDEX idx_comments_post (post_id, status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS follows (
    follower_id VARCHAR(64) NOT NULL,
    following_id VARCHAR(64) NOT NULL,
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (follower_id, following_id),
    CONSTRAINT fk_follows_follower FOREIGN KEY (follower_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_follows_following FOREIGN KEY (following_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS remake_plans (
    id CHAR(36) PRIMARY KEY,
    user_id VARCHAR(64) NOT NULL,
    original_post_id CHAR(36) NOT NULL,
    status ENUM('PLANNED','COMPLETED') NOT NULL DEFAULT 'PLANNED',
    completed_assignment_id CHAR(36) NULL,
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    completed_at TIMESTAMP(3) NULL,
    UNIQUE KEY uq_remake_plan (user_id, original_post_id),
    CONSTRAINT fk_plans_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_plans_original FOREIGN KEY (original_post_id) REFERENCES posts(id) ON DELETE CASCADE,
    CONSTRAINT fk_plans_assignment FOREIGN KEY (completed_assignment_id) REFERENCES posts(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS content_reports (
    id CHAR(36) PRIMARY KEY,
    reporter_id VARCHAR(64) NOT NULL,
    target_type ENUM('POST','COMMENT','USER','LOCATION') NOT NULL,
    target_id VARCHAR(64) NOT NULL,
    reason VARCHAR(80) NOT NULL,
    description VARCHAR(1000) NOT NULL DEFAULT '',
    status ENUM('OPEN','RESOLVED','REJECTED') NOT NULL DEFAULT 'OPEN',
    created_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    handled_at TIMESTAMP(3) NULL,
    CONSTRAINT fk_reports_user FOREIGN KEY (reporter_id) REFERENCES users(id),
    INDEX idx_reports_status (status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO users (id, nickname, bio, city) VALUES
    ('me', '小野同学', '用镜头记录城市光线', '上海'),
    ('u2', '林屿', '城市风光摄影师', '上海'),
    ('u3', '沈禾', '自然风光摄影爱好者', '杭州'),
    ('u4', '周野', '街头摄影爱好者', '上海')
ON DUPLICATE KEY UPDATE
    nickname = VALUES(nickname),
    bio = VALUES(bio),
    city = VALUES(city);
