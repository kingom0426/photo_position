package com.lumen.api.post;

import com.lumen.api.common.ApiException;
import com.lumen.api.post.PostDtos.CreateLocation;
import org.springframework.http.HttpStatus;

/** Persist only the location precision the author has chosen to publish. */
final class LocationPolicy {
    private LocationPolicy() {}

    static CreateLocation normalize(CreateLocation input) {
        String privacy = input.privacy() == null ? "PRIVATE" : input.privacy();
        if (privacy.equals("PRIVATE")) {
            return new CreateLocation("", "", "", "", "PRIVATE", null, null, "");
        }
        if (!privacy.equals("EXACT") && !privacy.equals("APPROXIMATE")) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Invalid location privacy");
        }
        Double lat = input.latitude(), lon = input.longitude();
        if (lat == null || lon == null || !Double.isFinite(lat) || !Double.isFinite(lon)
                || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "请选择实际拍摄地点，或设置为不公开");
        }
        if (privacy.equals("APPROXIMATE")) {
            // Stable grid: repeated editing does not accumulate jitter or expose the original point.
            return new CreateLocation("模糊区域", input.city(), "", "", privacy,
                    grid(lat), grid(lon), "");
        }
        return input;
    }

    private static double grid(double value) {
        return java.math.BigDecimal.valueOf(value).setScale(2, java.math.RoundingMode.HALF_UP).doubleValue();
    }
}
