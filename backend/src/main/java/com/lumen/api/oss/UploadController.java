package com.lumen.api.oss;

import com.lumen.api.user.UserService;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/uploads")
public class UploadController {
    private final UserService users;
    private final OssService oss;

    public UploadController(UserService users, OssService oss) {
        this.users = users;
        this.oss = oss;
    }

    @PostMapping("/presign")
    OssService.UploadSignature presign(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @RequestBody(required = false) UploadRequest body
    ) {
        var user = users.require(authorization);
        UploadRequest request = body == null
                ? new UploadRequest("photo.jpg", "image/jpeg", "original")
                : body;
        return oss.createUploadSignature(
                user.id(),
                value(request.fileName(), "photo.jpg"),
                value(request.mimeType(), "image/jpeg"),
                value(request.variant(), "original")
        );
    }

    private String value(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }

    public record UploadRequest(String fileName, String mimeType, String variant) {}
}
