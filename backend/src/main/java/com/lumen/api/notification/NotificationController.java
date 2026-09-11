package com.lumen.api.notification;

import com.lumen.api.notification.NotificationService.NotificationItem;
import com.lumen.api.user.UserService;
import java.util.List;
import java.util.UUID;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/notifications")
public class NotificationController {
    private final UserService users;
    private final NotificationService notifications;

    public NotificationController(UserService users, NotificationService notifications) {
        this.users = users;
        this.notifications = notifications;
    }

    @GetMapping
    NotificationList list(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @RequestParam(defaultValue = "30") int limit,
            @RequestParam(defaultValue = "0") int offset
    ) {
        var user = users.require(authorization);
        return new NotificationList(
                notifications.list(user, limit, offset),
                notifications.unreadCount(user)
        );
    }

    @PutMapping("/{id}/read")
    ResponseEntity<Void> markRead(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @PathVariable UUID id
    ) {
        notifications.markRead(users.require(authorization), id);
        return ResponseEntity.noContent().build();
    }

    @PutMapping("/read-all")
    ResponseEntity<Void> markAllRead(
            @RequestHeader(value = "Authorization", required = false) String authorization
    ) {
        notifications.markAllRead(users.require(authorization));
        return ResponseEntity.noContent().build();
    }

    record NotificationList(List<NotificationItem> items, int unreadCount) {}
}
