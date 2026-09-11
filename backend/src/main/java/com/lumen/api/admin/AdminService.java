package com.lumen.api.admin;

import com.lumen.api.common.ApiException;
import com.lumen.api.oss.OssService;
import com.lumen.api.post.PostDtos.PostResponse;
import com.lumen.api.post.PostRepository;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AdminService {
    private final JdbcTemplate jdbc;
    private final OssService oss;
    private final PostRepository posts;
    public AdminService(JdbcTemplate jdbc, OssService oss, PostRepository posts) {
        this.jdbc = jdbc; this.oss = oss; this.posts = posts;
    }

    public Map<String, Long> stats() {
        return Map.of("originals", count("SELECT COUNT(*) FROM posts WHERE kind='ORIGINAL' AND deleted_at IS NULL"),
                "assignments", count("SELECT COUNT(*) FROM posts WHERE kind='ASSIGNMENT' AND deleted_at IS NULL"),
                "comments", count("SELECT COUNT(*) FROM comments c JOIN posts p ON p.id=c.post_id WHERE c.status='VISIBLE' AND p.deleted_at IS NULL"),
                "deleted", count("SELECT COUNT(*) FROM posts WHERE deleted_at IS NOT NULL") + count("SELECT COUNT(*) FROM comments WHERE status='DELETED'"));
    }

    public Page<PostRow> posts(String kind, String status, String query, int limit, int offset) {
        if (!List.of("ORIGINAL", "ASSIGNMENT").contains(kind)) throw bad("内容类型无效");
        checkStatus(status);
        var args = new ArrayList<Object>(); args.add(kind);
        String where = " WHERE p.kind=?" + (status.equals("ACTIVE") ? " AND p.deleted_at IS NULL" : status.equals("DELETED") ? " AND p.deleted_at IS NOT NULL" : "");
        String search = search(query);
        if (!search.isEmpty()) {
            where += " AND (LOCATE(?,p.title)>0 OR LOCATE(?,u.nickname)>0 OR p.id=?)";
            args.add(search); args.add(search); args.add(search);
        }
        String from = " FROM posts p JOIN users u ON u.id=p.author_id";
        long total = jdbc.queryForObject("SELECT COUNT(*)" + from + where, Long.class, args.toArray());
        args.add(limit); args.add(offset);
        var items = jdbc.query("SELECT p.id,p.kind,p.title,p.description,p.original_post_id,u.nickname,p.author_id,"
                + "p.thumbnail_object_key,p.display_image_object_key,p.image_object_key,p.thumbnail_url,p.display_image_url,p.image_url,"
                + "p.like_count,p.comment_count,UNIX_TIMESTAMP(p.created_at) AS created_at,UNIX_TIMESTAMP(p.deleted_at) AS deleted_at" + from + where + " ORDER BY p.created_at DESC,p.id DESC LIMIT ? OFFSET ?",
                (rs,n) -> new PostRow(rs.getString("id"),rs.getString("kind"),rs.getString("title"),rs.getString("description"),
                        rs.getString("author_id"),rs.getString("nickname"),rs.getString("original_post_id"),thumbnail(rs),
                        rs.getInt("like_count"),rs.getInt("comment_count"),time(rs,"created_at"),time(rs,"deleted_at")), args.toArray());
        return new Page<>(items,total,limit,offset);
    }

    public Detail detail(UUID id) {
        PostResponse content = posts.findForAdmin(id).orElseThrow(() -> notFound("内容不存在"));
        var dates = jdbc.queryForObject("SELECT UNIX_TIMESTAMP(created_at) AS created_at,UNIX_TIMESTAMP(deleted_at) AS deleted_at FROM posts WHERE id=?",
                (rs,n) -> new String[]{time(rs,"created_at"),time(rs,"deleted_at")}, id.toString());
        return new Detail(content, dates[0], dates[1]);
    }

    public Page<CommentRow> comments(String status, String query, UUID postId, int limit, int offset) {
        checkStatus(status);
        var args = new ArrayList<Object>();
        String where = " WHERE 1=1" + (status.equals("ACTIVE") ? " AND c.status<>'DELETED'" : status.equals("DELETED") ? " AND c.status='DELETED'" : "");
        if (postId != null) { where += " AND c.post_id=?"; args.add(postId.toString()); }
        String search = search(query);
        if (!search.isEmpty()) {
            where += " AND (LOCATE(?,c.content)>0 OR LOCATE(?,u.nickname)>0 OR LOCATE(?,p.title)>0 OR c.id=?)";
            for (int i=0;i<4;i++) args.add(search);
        }
        String from = " FROM comments c JOIN users u ON u.id=c.author_id JOIN posts p ON p.id=c.post_id";
        long total = jdbc.queryForObject("SELECT COUNT(*)"+from+where, Long.class,args.toArray());
        args.add(limit); args.add(offset);
        var items = jdbc.query("SELECT c.id,c.post_id,c.content,c.status,UNIX_TIMESTAMP(c.created_at) AS created_at,c.author_id,u.nickname,p.title,p.deleted_at"+from+where
                + " ORDER BY c.created_at DESC,c.id DESC LIMIT ? OFFSET ?", (rs,n) -> new CommentRow(rs.getString("id"),rs.getString("post_id"),
                rs.getString("title"),rs.getString("author_id"),rs.getString("nickname"),rs.getString("content"),rs.getString("status"),
                time(rs,"created_at"),rs.getTimestamp("deleted_at") != null),args.toArray());
        return new Page<>(items,total,limit,offset);
    }

    @Transactional
    public void deletePost(UUID id, String actor) {
        var rows = jdbc.query("SELECT title,deleted_at FROM posts WHERE id=? FOR UPDATE",
                (rs,n) -> new String[]{rs.getString("title"),rs.getString("deleted_at")},id.toString());
        if (rows.isEmpty()) throw notFound("内容不存在");
        if (rows.get(0)[1] != null) return;
        jdbc.update("UPDATE posts SET deleted_at=CURRENT_TIMESTAMP(3) WHERE id=?",id.toString());
        audit(actor,"POST",id,rows.get(0)[0]);
    }

    @Transactional
    public void deleteComment(UUID id, String actor) {
        var postIds = jdbc.query("SELECT post_id FROM comments WHERE id=?", (rs,n) -> rs.getString(1),id.toString());
        if (postIds.isEmpty()) throw notFound("评论不存在");
        // Use the same parent-first lock order as app comment creation.
        jdbc.queryForObject("SELECT id FROM posts WHERE id=? FOR UPDATE",String.class,postIds.get(0));
        var row = jdbc.queryForMap("SELECT content,status FROM comments WHERE id=? FOR UPDATE",id.toString());
        if ("DELETED".equals(row.get("status"))) return;
        jdbc.update("UPDATE comments SET status='DELETED' WHERE id=?",id.toString());
        if ("VISIBLE".equals(row.get("status"))) {
            jdbc.update("UPDATE posts SET comment_count=GREATEST(comment_count-1,0) WHERE id=?",postIds.get(0));
        }
        audit(actor,"COMMENT",id,row.get("content").toString());
    }

    private void audit(String actor, String type, UUID id, String label) {
        jdbc.update("INSERT INTO admin_audit_logs(id,actor_id,target_type,target_id,action,target_label) VALUES(?,?,?,?,?,?)",
                UUID.randomUUID().toString(),actor,type,id.toString(),"DELETE",label.substring(0,Math.min(label.length(),200)));
    }
    private long count(String sql) { return jdbc.queryForObject(sql,Long.class); }
    private String thumbnail(ResultSet rs) throws SQLException {
        for (String column : List.of("thumbnail_object_key","display_image_object_key","image_object_key")) {
            String url = oss.createDownloadUrl(rs.getString(column)); if (url != null && !url.isBlank()) return url;
        }
        for (String column : List.of("thumbnail_url","display_image_url","image_url")) {
            String url = rs.getString(column); if (url != null && !url.isBlank()) return url;
        }
        return null;
    }
    private static String time(ResultSet rs,String column) throws SQLException {
        // Read absolute epoch seconds from MySQL, not timestamps interpreted using
        // JDBC's configured time zone (which may differ from the RDS session zone).
        var value = rs.getBigDecimal(column);
        return value == null ? null : java.time.Instant.ofEpochMilli(value.movePointRight(3).longValue()).toString();
    }
    private static String search(String value) {
        String query = value == null ? "" : value.trim();
        if (query.length()>100) throw bad("搜索内容不能超过 100 个字符");
        return query;
    }
    private static void checkStatus(String status) { if (!List.of("ACTIVE","DELETED","ALL").contains(status)) throw bad("状态无效"); }
    private static ApiException bad(String text) { return new ApiException(HttpStatus.BAD_REQUEST,text); }
    private static ApiException notFound(String text) { return new ApiException(HttpStatus.NOT_FOUND,text); }
    public record Page<T>(List<T> items,long total,int limit,int offset) {}
    public record PostRow(String id,String kind,String title,String description,String authorId,String authorName,String originalId,
                          String imageUrl,int likeCount,int commentCount,String createdAt,String deletedAt) {}
    public record CommentRow(String id,String postId,String postTitle,String authorId,String authorName,String content,String status,String createdAt,boolean postDeleted) {}
    public record Detail(PostResponse content,String createdAt,String deletedAt) {}
}
