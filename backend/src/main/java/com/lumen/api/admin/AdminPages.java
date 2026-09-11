package com.lumen.api.admin;

import org.springframework.core.io.ClassPathResource;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class AdminPages {
    @GetMapping(value={"/admin","/admin/"},produces="text/html")
    ResponseEntity<ClassPathResource> page() { return asset("index.html","text/html"); }
    @GetMapping(value="/admin/admin.js",produces="text/javascript")
    ResponseEntity<ClassPathResource> script() { return asset("admin.js","text/javascript"); }
    @GetMapping(value="/admin/admin.css",produces="text/css")
    ResponseEntity<ClassPathResource> style() { return asset("admin.css","text/css"); }
    private ResponseEntity<ClassPathResource> asset(String name,String type) {
        return ResponseEntity.ok().header("Content-Type",type+";charset=UTF-8")
                .header("Cache-Control","no-store").header("X-Content-Type-Options","nosniff")
                .header("Referrer-Policy","no-referrer").header("X-Frame-Options","DENY")
                .header("Content-Security-Policy","default-src 'none'; script-src 'self'; style-src 'self'; img-src https: data:; connect-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'")
                .body(new ClassPathResource("admin/"+name));
    }
}
