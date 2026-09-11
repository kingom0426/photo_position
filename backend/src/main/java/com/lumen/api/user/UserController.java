package com.lumen.api.user;

import com.lumen.api.user.UserService.FollowResult;
import com.lumen.api.user.UserService.PublicUser;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/users")
public class UserController {
    private final UserService users;

    public UserController(UserService users) {
        this.users = users;
    }

    @GetMapping("/following")
    UserList following(
            @RequestHeader(value = "Authorization", required = false) String authorization
    ) {
        return new UserList(users.following(authorization));
    }

    @PutMapping("/{id}/follow")
    FollowResult toggleFollow(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @PathVariable String id
    ) {
        return users.toggleFollow(authorization, id);
    }

    record UserList(List<PublicUser> items) {}
}
