INSERT INTO post_locations (
    post_id,
    place_name,
    city,
    district,
    detailed_address,
    privacy_level,
    latitude,
    longitude,
    shooting_advice,
    safety_status
)
SELECT
    p.id,
    '默认拍摄点',
    COALESCE(NULLIF(u.city, ''), '北京'),
    '',
    '',
    'EXACT',
    39.9042000,
    116.4074000,
    '',
    'NORMAL'
FROM posts p
JOIN users u ON u.id = p.author_id
LEFT JOIN post_locations l ON l.post_id = p.id
WHERE l.post_id IS NULL;

UPDATE post_locations
SET latitude = COALESCE(latitude, 39.9042000),
    longitude = COALESCE(longitude, 116.4074000),
    privacy_level = 'EXACT';

ALTER TABLE post_locations
    MODIFY COLUMN latitude DECIMAL(10,7) NOT NULL COMMENT '用户发布时选定的纬度',
    MODIFY COLUMN longitude DECIMAL(10,7) NOT NULL COMMENT '用户发布时选定的经度';
