package com.lumen.api.user;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.lumen.api.common.ApiException;
import org.junit.jupiter.api.Test;

class UsernameValidationTest {
    @Test
    void normalizesSupportedUsername() {
        assertThat(UserService.normalizeUsername("  Lumen_User01 "))
                .isEqualTo("lumen_user01");
    }

    @Test
    void rejectsInvalidUsername() {
        assertThatThrownBy(() -> UserService.normalizeUsername("1x"))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("用户名");
        assertThatThrownBy(() -> UserService.normalizeUsername("含中文"))
                .isInstanceOf(ApiException.class);
    }
}
