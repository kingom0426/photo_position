package com.lumen.api;

import com.lumen.api.oss.OssService;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class HealthController {
    private final JdbcTemplate jdbc;
    private final OssService oss;

    public HealthController(JdbcTemplate jdbc, OssService oss) {
        this.jdbc = jdbc;
        this.oss = oss;
    }

    @GetMapping("/health")
    Map<String, String> health() {
        jdbc.queryForObject("SELECT 1", Integer.class);
        return Map.of(
                "status", "ok",
                "database", "connected",
                "oss", oss.configured() ? "configured" : "missing_config"
        );
    }
}
