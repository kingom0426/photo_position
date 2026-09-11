package com.lumen.api.config;

import java.util.Arrays;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebConfig implements WebMvcConfigurer {
    private final List<String> allowedOrigins;
    private final String adminOrigin;

    public WebConfig(AppProperties properties,
            @Value("${app.mail.public-base-url:https://chenxi-edu.com}") String adminOrigin) {
        this.adminOrigin = adminOrigin.replaceAll("/+$", "");
        this.allowedOrigins = Arrays.stream(properties.allowedOrigins().split(","))
                .map(String::trim)
                .filter(value -> !value.isBlank())
                .toList();
    }

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        // Nginx terminates HTTPS; servlet requests arrive over HTTP. Explicitly allow
        // the one public origin without granting credentialed cross-origin access.
        registry.addMapping("/api/admin/**")
                .allowedOrigins(adminOrigin)
                .allowedMethods("GET", "POST", "DELETE", "OPTIONS")
                .allowedHeaders("Content-Type", "X-Lumen-Admin")
                .allowCredentials(false);
        var registration = registry.addMapping("/api/**")
                .allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
                .allowedHeaders("Content-Type", "Authorization");
        if (allowedOrigins.isEmpty()) {
            registration.allowedOriginPatterns("*");
        } else {
            registration.allowedOrigins(allowedOrigins.toArray(String[]::new));
        }
    }
}
