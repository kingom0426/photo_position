package com.lumen.api.admin;

import jakarta.servlet.http.HttpServletRequest;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/admin")
public class AdminController {
    private final AdminAuth auth;
    private final AdminService admin;
    public AdminController(AdminAuth auth,AdminService admin) { this.auth=auth; this.admin=admin; }
    @PostMapping("/login")
    ResponseEntity<?> login(@RequestBody Credentials credentials,HttpServletRequest request) {
        if (credentials == null) throw new com.lumen.api.common.ApiException(org.springframework.http.HttpStatus.BAD_REQUEST,"请输入邮箱和密码");
        var result = auth.login(credentials.email(),credentials.password(),request);
        return ResponseEntity.ok().header("Set-Cookie",auth.cookie(result.token()))
                .body(Map.of("name",result.user().nickname(),"email",result.user().email()));
    }
    @PostMapping("/logout")
    ResponseEntity<Void> logout(HttpServletRequest request) {
        auth.logout(request);
        return ResponseEntity.noContent().header("Set-Cookie",auth.cookie("")).build();
    }
    @GetMapping("/me")
    Map<String,String> me(HttpServletRequest request) {
        var user=auth.require(request); return Map.of("name",user.nickname(),"email",user.email());
    }
    @GetMapping("/stats")
    Map<String,Long> stats(HttpServletRequest request) { auth.require(request); return admin.stats(); }
    @GetMapping("/posts")
    AdminService.Page<AdminService.PostRow> posts(HttpServletRequest request,@RequestParam(defaultValue="ORIGINAL") String kind,
            @RequestParam(defaultValue="ACTIVE") String status,@RequestParam(defaultValue="") String q,
            @RequestParam(defaultValue="20") int limit,@RequestParam(defaultValue="0") int offset) {
        auth.require(request); return admin.posts(kind,status,q,Math.min(50,Math.max(1,limit)),Math.max(0,offset));
    }
    @GetMapping("/posts/{id}")
    AdminService.Detail detail(HttpServletRequest request,@PathVariable UUID id) { auth.require(request); return admin.detail(id); }
    @GetMapping("/comments")
    AdminService.Page<AdminService.CommentRow> comments(HttpServletRequest request,@RequestParam(defaultValue="ACTIVE") String status,
            @RequestParam(defaultValue="") String q,@RequestParam(required=false) UUID postId,
            @RequestParam(defaultValue="20") int limit,@RequestParam(defaultValue="0") int offset) {
        auth.require(request); return admin.comments(status,q,postId,Math.min(50,Math.max(1,limit)),Math.max(0,offset));
    }
    @DeleteMapping("/posts/{id}")
    ResponseEntity<Void> deletePost(HttpServletRequest request,@PathVariable UUID id) {
        auth.checkMutation(request); var user=auth.require(request); admin.deletePost(id,user.id()); return ResponseEntity.noContent().build();
    }
    @DeleteMapping("/comments/{id}")
    ResponseEntity<Void> deleteComment(HttpServletRequest request,@PathVariable UUID id) {
        auth.checkMutation(request); var user=auth.require(request); admin.deleteComment(id,user.id()); return ResponseEntity.noContent().build();
    }
    public record Credentials(String email,String password) {}
}
