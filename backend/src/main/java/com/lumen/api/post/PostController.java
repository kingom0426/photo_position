package com.lumen.api.post;

import com.lumen.api.post.PostDtos.CommentList;
import com.lumen.api.post.PostDtos.CreateComment;
import com.lumen.api.post.PostDtos.CreatePostRequest;
import com.lumen.api.post.PostDtos.PostList;
import com.lumen.api.user.UserService;
import java.util.UUID;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/posts")
public class PostController {
    private final UserService users;
    private final PostService posts;

    public PostController(UserService users, PostService posts) {
        this.users = users;
        this.posts = posts;
    }

    @GetMapping
    PostList list(
            @RequestHeader(value = "x-user-id", required = false) String userId,
            @RequestParam(defaultValue = "20") int limit,
            @RequestParam(defaultValue = "0") int offset
    ) {
        var user = users.require(userId);
        int safeLimit = Math.min(Math.max(limit, 1), 50);
        int safeOffset = Math.max(offset, 0);
        var items = posts.list(user.id(), safeLimit, safeOffset);
        return new PostList(items, safeLimit, safeOffset, items.size() == safeLimit);
    }

    @GetMapping("/{id}")
    PostDtos.PostResponse get(
            @RequestHeader(value = "x-user-id", required = false) String userId,
            @PathVariable UUID id
    ) {
        var user = users.require(userId);
        return posts.get(id, user.id());
    }

    @PostMapping
    ResponseEntity<PostDtos.PostResponse> create(
            @RequestHeader(value = "x-user-id", required = false) String userId,
            @RequestBody CreatePostRequest request
    ) {
        var user = users.require(userId);
        return ResponseEntity.status(201).body(posts.create(request, user));
    }

    @PutMapping("/{id}/like")
    PostDtos.LikeResponse toggleLike(
            @RequestHeader(value = "x-user-id", required = false) String userId,
            @PathVariable UUID id
    ) {
        return posts.toggleLike(id, users.require(userId));
    }

    @GetMapping("/{id}/comments")
    CommentList comments(
            @RequestHeader(value = "x-user-id", required = false) String userId,
            @PathVariable UUID id
    ) {
        users.require(userId);
        return new CommentList(posts.comments(id));
    }

    @PostMapping("/{id}/comments")
    ResponseEntity<PostDtos.CommentResponse> addComment(
            @RequestHeader(value = "x-user-id", required = false) String userId,
            @PathVariable UUID id,
            @RequestBody CreateComment request
    ) {
        var user = users.require(userId);
        return ResponseEntity.status(201).body(
                posts.addComment(id, request == null ? null : request.content(), user)
        );
    }

    @PutMapping("/{id}/plan")
    PostDtos.PlanResponse togglePlan(
            @RequestHeader(value = "x-user-id", required = false) String userId,
            @PathVariable UUID id
    ) {
        return posts.togglePlan(id, users.require(userId));
    }
}
