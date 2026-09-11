ALTER TABLE post_locations
    ADD COLUMN detailed_address VARCHAR(500) NOT NULL DEFAULT '' AFTER district;
