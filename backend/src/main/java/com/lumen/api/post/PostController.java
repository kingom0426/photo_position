package com.lumen.api.post;

import com.lumen.api.post.PostDtos.CommentList;
import com.lumen.api.post.PostDtos.CreateComment;
import com.lumen.api.post.PostDtos.CreatePostRequest;
import com.lumen.api.post.PostDtos.PostList;
import com.lumen.api.user.UserService;
import com.lumen.api.post.PostRepository.FeedQuery;
import java.util.UUID;
import java.util.Arrays;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
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
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @RequestParam(defaultValue = "20") int limit,
            @RequestParam(defaultValue = "0") int offset,
            @RequestParam(defaultValue = "recommended") String feed,
            @RequestParam(required = false) Double latitude,
            @RequestParam(required = false) Double longitude,
            @RequestParam(required = false) Double radiusKm,
            @RequestParam(required = false) String q,
            @RequestParam(required = false) String tag,
            @RequestParam(required = false) String authorId,
            @RequestParam(required = false) String filters
    ) {
        var user = "following".equals(feed)
                ? users.require(authorization)
                : users.optional(authorization);
        int safeLimit = Math.min(Math.max(limit, 1), 50);
        int safeOffset = Math.max(offset, 0);
        Double safeRadius = radiusKm == null ? null : Math.min(Math.max(radiusKm, 0.5), 100);
        Set<String> parsedFilters = filters == null || filters.isBlank()
                ? Set.of()
                : Arrays.stream(filters.split(","))
                        .map(String::trim)
                        .filter(value -> !value.isEmpty())
                        .collect(Collectors.toSet());
        var items = posts.list(
                user == null ? null : user.id(),
                safeLimit,
                safeOffset,
                new FeedQuery(
                        feed,
                        latitude,
                        longitude,
                        safeRadius,
                        q,
                        tag,
                        authorId,
                        parsedFilters
                )
        );
        return new PostList(items, safeLimit, safeOffset, items.size() == safeLimit);
    }

    @GetMapping("/{id}")
    PostDtos.PostResponse get(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @PathVariable UUID id
    ) {
        var user = users.optional(authorization);
        return posts.get(id, user == null ? null : user.id());
    }

    @PostMapping
    ResponseEntity<PostDtos.PostResponse> create(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @RequestBody CreatePostRequest request
    ) {
        var user = users.require(authorization);
        return ResponseEntity.status(201).body(posts.create(request, user));
    }

    @PutMapping("/{id}")
    PostDtos.PostResponse update(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @PathVariable UUID id,
            @RequestBody CreatePostRequest request
    ) {
        return posts.update(id, request, users.require(authorization));
    }

    @DeleteMapping("/{id}")
    ResponseEntity<Void> delete(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @PathVariable UUID id
    ) {
        posts.delete(id, users.require(authorization));
        return ResponseEntity.noContent().build();
    }

    @PutMapping("/{id}/like")
    PostDtos.LikeResponse toggleLike(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @PathVariable UUID id
    ) {
        return posts.toggleLike(id, users.require(authorization));
    }

    @GetMapping("/{id}/comments")
    CommentList comments(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @PathVariable UUID id
    ) {
        return new CommentList(posts.comments(id));
    }

    @PostMapping("/{id}/comments")
    ResponseEntity<PostDtos.CommentResponse> addComment(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @PathVariable UUID id,
            @RequestBody CreateComment request
    ) {
        var user = users.require(authorization);
        return ResponseEntity.status(201).body(
                posts.addComment(id, request == null ? null : request.content(), user)
        );
    }

    @PutMapping("/{id}/plan")
    PostDtos.PlanResponse togglePlan(
            @RequestHeader(value = "Authorization", required = false) String authorization,
            @PathVariable UUID id
    ) {
        return posts.togglePlan(id, users.require(authorization));
    }
}
