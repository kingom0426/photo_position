package com.lumen.api.user;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class ConsentServiceTest {
    @Test
    void loadsVersionedConsentAndStableDigest() {
        ConsentService service = new ConsentService();

        assertThat(service.current().version()).isEqualTo("3.0");
        assertThat(service.current().content()).contains("邮箱和密码", "密码摘要", "网易 163");
        assertThat(service.current().documentSha256()).hasSize(64);
        assertThat(service.current().documentSha256()).isEqualTo(service.documentSha256());
    }
}
