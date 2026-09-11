ALTER TABLE post_locations
    MODIFY COLUMN latitude DECIMAL(10,7) NULL COMMENT '按用户公开精度保存的纬度；不公开时为空',
    MODIFY COLUMN longitude DECIMAL(10,7) NULL COMMENT '按用户公开精度保存的经度；不公开时为空';

UPDATE post_locations
SET latitude = NULL, longitude = NULL, place_name = '', city = '', district = '',
    detailed_address = '', shooting_advice = ''
WHERE privacy_level = 'PRIVATE';

UPDATE post_locations
SET latitude = ROUND(latitude, 2), longitude = ROUND(longitude, 2),
    place_name = '模糊区域', district = '', detailed_address = '', shooting_advice = ''
WHERE privacy_level = 'APPROXIMATE';
