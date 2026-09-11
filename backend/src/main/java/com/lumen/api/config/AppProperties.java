package com.lumen.api.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app")
public record AppProperties(Oss oss, String allowedOrigins) {
    public AppProperties {
        oss = oss == null ? new Oss("", "", "", "", "", true, "") : oss;
        allowedOrigins = allowedOrigins == null ? "" : allowedOrigins;
    }

    public record Oss(
            String region,
            String bucket,
            String endpoint,
            String accessKeyId,
            String accessKeySecret,
            boolean secure,
            String publicBaseUrl
    ) {
        public Oss {
            region = value(region);
            bucket = value(bucket);
            endpoint = value(endpoint);
            accessKeyId = value(accessKeyId);
            accessKeySecret = value(accessKeySecret);
            publicBaseUrl = value(publicBaseUrl);
        }

        public boolean configured() {
            return !region.isBlank() && !bucket.isBlank()
                    && !accessKeyId.isBlank() && !accessKeySecret.isBlank();
        }

        public String resolvedEndpoint() {
            if (!endpoint.isBlank()) {
                return endpoint.startsWith("http") ? endpoint
                        : (secure ? "https://" : "http://") + endpoint;
            }
            return (secure ? "https://" : "http://") + region + ".aliyuncs.com";
        }

        public String sdkRegion() {
            return region.startsWith("oss-") ? region.substring(4) : region;
        }

        private static String value(String value) {
            return value == null ? "" : value.trim();
        }
    }

}
