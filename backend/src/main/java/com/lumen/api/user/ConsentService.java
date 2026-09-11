package com.lumen.api.user;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;

@Service
public class ConsentService {
    public static final String TYPE = "USER_INFORMED_CONSENT";
    public static final String VERSION = "3.0";
    public static final String TITLE = "Lumen 用户知情同意书";
    public static final String EFFECTIVE_DATE = "2026-09-02";

    private final String content;
    private final String documentSha256;

    public ConsentService() {
        try {
            content = new ClassPathResource("consent/user-informed-consent-v3.md")
                    .getContentAsString(StandardCharsets.UTF_8);
            documentSha256 = sha256(content);
        } catch (IOException error) {
            throw new IllegalStateException("Unable to load user consent document", error);
        }
    }

    public ConsentDocument current() {
        return new ConsentDocument(
                TYPE, VERSION, TITLE, EFFECTIVE_DATE, content, documentSha256
        );
    }

    public boolean isCurrentVersion(String version) {
        return VERSION.equals(version == null ? "" : version.trim());
    }

    public String documentSha256() {
        return documentSha256;
    }

    private static String sha256(String value) {
        try {
            return java.util.HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256")
                            .digest(value.getBytes(StandardCharsets.UTF_8))
            );
        } catch (Exception error) {
            throw new IllegalStateException("Unable to hash consent document", error);
        }
    }

    public record ConsentDocument(
            String type,
            String version,
            String title,
            String effectiveDate,
            String content,
            String documentSha256
    ) {}
}
