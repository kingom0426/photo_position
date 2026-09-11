UPDATE post_locations
SET latitude = COALESCE(latitude, public_latitude),
    longitude = COALESCE(longitude, public_longitude)
WHERE latitude IS NULL
   OR longitude IS NULL;

ALTER TABLE post_locations
    DROP INDEX idx_location_public,
    DROP COLUMN public_latitude,
    DROP COLUMN public_longitude,
    MODIFY COLUMN latitude DECIMAL(10,7) NULL COMMENT '用户发布时选定的纬度',
    MODIFY COLUMN longitude DECIMAL(10,7) NULL COMMENT '用户发布时选定的经度',
    ADD INDEX idx_location_coordinates (city, latitude, longitude);
