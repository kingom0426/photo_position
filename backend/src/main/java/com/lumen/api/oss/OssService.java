package com.lumen.api.oss;

import com.aliyun.oss.ClientBuilderConfiguration;
import com.aliyun.oss.HttpMethod;
import com.aliyun.oss.OSS;
import com.aliyun.oss.OSSClientBuilder;
import com.aliyun.oss.common.auth.DefaultCredentialProvider;
import com.aliyun.oss.common.comm.SignVersion;
import com.aliyun.oss.model.GeneratePresignedUrlRequest;
import com.lumen.api.common.ApiException;
import com.lumen.api.config.AppProperties;
import jakarta.annotation.PreDestroy;
import java.net.URL;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Date;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

@Service
public class OssService {
    private static final Set<String> VARIANTS = Set.of("original", "display", "thumbnail");
    private static final Map<String, String> EXTENSIONS = Map.of(
            "image/jpeg", ".jpg",
            "image/png", ".png",
            "image/heic", ".heic",
            "image/heif", ".heif",
            "image/webp", ".webp"
    );

    private final AppProperties.Oss properties;
    private final Clock clock;
    private final OSS client;

    @Autowired
    public OssService(AppProperties properties) {
        this(properties.oss(), Clock.systemUTC());
    }

    OssService(AppProperties.Oss properties, Clock clock) {
        this.properties = properties;
        this.clock = clock;
        this.client = properties.configured() ? buildClient(properties) : null;
    }

    public boolean configured() {
        return client != null;
    }

    public UploadSignature createUploadSignature(
            String userId,
            String fileName,
            String mimeType,
            String variant
    ) {
        requireConfigured();
        String normalizedMime = normalizeMime(mimeType);
        String normalizedVariant = variant == null || variant.isBlank() ? "original" : variant;
        if (!VARIANTS.contains(normalizedVariant)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Invalid image variant");
        }

        Instant now = clock.instant();
        String month = DateTimeFormatter.ofPattern("yyyy/MM")
                .withZone(ZoneOffset.UTC)
                .format(now);
        String objectKey = "photos/%s/%s/%s-%s%s".formatted(
                month,
                userId,
                UUID.randomUUID(),
                normalizedVariant,
                extension(fileName, normalizedMime)
        );
        Date expiration = Date.from(now.plus(Duration.ofMinutes(10)));
        GeneratePresignedUrlRequest request =
                new GeneratePresignedUrlRequest(properties.bucket(), objectKey, HttpMethod.PUT);
        request.setExpiration(expiration);
        Map<String, String> signedHeaders = new HashMap<>();
        signedHeaders.put("Content-Type", normalizedMime);
        request.setHeaders(signedHeaders);
        URL signedUrl = client.generatePresignedUrl(request);

        return new UploadSignature(
                objectKey,
                signedUrl.toString(),
                objectUrl(objectKey),
                600,
                "PUT",
                Map.of("Content-Type", normalizedMime)
        );
    }

    public String createDownloadUrl(String objectKey) {
        if (objectKey == null || objectKey.isBlank() || !configured()) {
            return null;
        }
        GeneratePresignedUrlRequest request =
                new GeneratePresignedUrlRequest(properties.bucket(), objectKey, HttpMethod.GET);
        request.setExpiration(Date.from(clock.instant().plus(Duration.ofHours(1))));
        return client.generatePresignedUrl(request).toString();
    }

    private OSS buildClient(AppProperties.Oss properties) {
        ClientBuilderConfiguration configuration = new ClientBuilderConfiguration();
        configuration.setSignatureVersion(SignVersion.V4);
        return OSSClientBuilder.create()
                .endpoint(properties.resolvedEndpoint())
                .credentialsProvider(new DefaultCredentialProvider(
                        properties.accessKeyId(),
                        properties.accessKeySecret()
                ))
                .clientConfiguration(configuration)
                .region(properties.sdkRegion())
                .build();
    }

    private void requireConfigured() {
        if (!configured()) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "OSS is not configured");
        }
    }

    private String normalizeMime(String mimeType) {
        String value = mimeType == null ? "" : mimeType.trim().toLowerCase(Locale.ROOT);
        if (!EXTENSIONS.containsKey(value)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Unsupported image type");
        }
        return value;
    }

    private String extension(String fileName, String mimeType) {
        String lower = fileName == null ? "" : fileName.toLowerCase(Locale.ROOT);
        return EXTENSIONS.values().stream()
                .filter(lower::endsWith)
                .findFirst()
                .orElse(EXTENSIONS.get(mimeType));
    }

    private String objectUrl(String objectKey) {
        String base = properties.publicBaseUrl();
        if (base.isBlank()) {
            base = (properties.secure() ? "https://" : "http://")
                    + properties.bucket() + "." + properties.region() + ".aliyuncs.com";
        }
        return base.replaceAll("/+$", "") + "/" + objectKey;
    }

    @PreDestroy
    void shutdown() {
        if (client != null) {
            client.shutdown();
        }
    }

    public record UploadSignature(
            String objectKey,
            String uploadUrl,
            String objectUrl,
            int expiresIn,
            String method,
            Map<String, String> headers
    ) {}
}
