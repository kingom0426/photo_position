package com.lumen.api.post;

import static org.assertj.core.api.Assertions.*;
import com.lumen.api.common.ApiException;
import com.lumen.api.post.PostDtos.CreateLocation;
import org.junit.jupiter.api.Test;

class LocationPolicyTest {
    CreateLocation location(String privacy, Double lat, Double lon) {
        return new CreateLocation("家", "上海", "小区", "3号门501室", privacy, lat, lon, "从后门进入");
    }
    @Test void privateAndUnspecifiedDiscardAllLocationData() {
        for (String privacy : new String[]{"PRIVATE", null}) {
            var result = LocationPolicy.normalize(location(privacy, 31.234567, 121.456789));
            assertThat(result).isEqualTo(new CreateLocation("", "", "", "", "PRIVATE", null, null, ""));
        }
    }
    @Test void missingCoordinatesNeverBecomeDefaultBeijing() {
        assertThat(LocationPolicy.normalize(location("PRIVATE", null, null)).latitude()).isNull();
        for (String privacy : new String[]{"EXACT", "APPROXIMATE"}) {
            assertThatThrownBy(() -> LocationPolicy.normalize(location(privacy, null, null))).isInstanceOf(ApiException.class);
            assertThatThrownBy(() -> LocationPolicy.normalize(location(privacy, 31.0, null))).isInstanceOf(ApiException.class);
        }
    }
    @Test void approximateRemovesIdentifyingTextAndIsStableAcrossEdits() {
        var result = LocationPolicy.normalize(location("APPROXIMATE", 31.234567, 121.456789));
        assertThat(result).isEqualTo(new CreateLocation("模糊区域", "上海", "", "", "APPROXIMATE", 31.23, 121.46, ""));
        assertThat(LocationPolicy.normalize(result)).isEqualTo(result);
    }
    @Test void exactPreservesExplicitLocation() {
        var input = location("EXACT", 31.234567, 121.456789);
        assertThat(LocationPolicy.normalize(input)).isEqualTo(input);
    }
    @Test void rejectsInvalidCoordinatesAndPrivacy() {
        for (double value : new double[]{Double.NaN, Double.POSITIVE_INFINITY, 91, -91}) {
            assertThatThrownBy(() -> LocationPolicy.normalize(location("EXACT", value, 121.0))).isInstanceOf(ApiException.class);
        }
        assertThatThrownBy(() -> LocationPolicy.normalize(location("EXACT", 31.0, 181.0))).isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> LocationPolicy.normalize(location("INVALID", 31.0, 121.0))).isInstanceOf(ApiException.class);
    }
}
