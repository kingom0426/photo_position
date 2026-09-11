UPDATE post_locations
SET place_name = detailed_address,
    detailed_address = ''
WHERE TRIM(detailed_address) <> '';

ALTER TABLE post_locations
    MODIFY COLUMN place_name VARCHAR(500) NOT NULL DEFAULT '' COMMENT '用户在地图上选定的定位地址',
    MODIFY COLUMN detailed_address VARCHAR(500) NOT NULL DEFAULT '' COMMENT '用户手动输入的详细地址';
