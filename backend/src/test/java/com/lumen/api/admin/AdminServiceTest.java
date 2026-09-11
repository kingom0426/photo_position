package com.lumen.api.admin;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import com.lumen.api.common.ApiException;
import com.lumen.api.notification.NotificationService;
import com.lumen.api.oss.OssService;
import com.lumen.api.post.PostRepository;
import com.lumen.api.post.PostService;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.transaction.annotation.AnnotationTransactionAttributeSource;
import org.springframework.transaction.interceptor.TransactionInterceptor;

class AdminServiceTest {
    JdbcTemplate jdbc; AdminService admin; PostService publicPosts;
    UUID post=UUID.randomUUID(), assignment=UUID.randomUUID(), comment=UUID.randomUUID();
    @BeforeEach void setup() {
        var ds=new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa","");
        jdbc=new JdbcTemplate(ds);
        jdbc.execute("CREATE TABLE users(id VARCHAR(64) PRIMARY KEY,nickname VARCHAR(80),avatar_object_key VARCHAR(512),avatar_url VARCHAR(1000))");
        jdbc.execute("CREATE TABLE posts(id CHAR(36) PRIMARY KEY,author_id VARCHAR(64),kind VARCHAR(16),title VARCHAR(120),description TEXT,original_post_id CHAR(36),"
                +"thumbnail_object_key VARCHAR(512),display_image_object_key VARCHAR(512),image_object_key VARCHAR(512),thumbnail_url VARCHAR(1000),display_image_url VARCHAR(1000),image_url VARCHAR(1000),"
                +"like_count INT DEFAULT 0,comment_count INT DEFAULT 0,created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,deleted_at TIMESTAMP NULL)");
        jdbc.execute("CREATE TABLE comments(id CHAR(36) PRIMARY KEY,post_id CHAR(36),author_id VARCHAR(64),parent_id CHAR(36),content VARCHAR(1000),status VARCHAR(16),created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
        jdbc.execute("CREATE TABLE admin_audit_logs(id CHAR(36),actor_id VARCHAR(64),target_type VARCHAR(16),target_id CHAR(36),action VARCHAR(16),target_label VARCHAR(200))");
        jdbc.update("INSERT INTO users(id,nickname) VALUES('author','摄影师')");
        jdbc.update("INSERT INTO posts(id,author_id,kind,title,description,comment_count) VALUES(?,'author','ORIGINAL','午后光影','作品说明',1)",post.toString());
        jdbc.update("INSERT INTO posts(id,author_id,kind,title,description,original_post_id) VALUES(?,'author','ASSIGNMENT','复刻练习','作业说明',?)",assignment.toString(),post.toString());
        jdbc.update("INSERT INTO comments(id,post_id,author_id,content,status) VALUES(?,?,'author','测试评论','VISIBLE')",comment.toString(),post.toString());
        var oss=mock(OssService.class);var repository=mock(PostRepository.class);
        var factory=new ProxyFactory(new AdminService(jdbc,oss,repository));
        factory.addAdvice(new TransactionInterceptor(new DataSourceTransactionManager(ds),new AnnotationTransactionAttributeSource()));
        admin=(AdminService)factory.getProxy();publicPosts=new PostService(jdbc,repository,oss,mock(NotificationService.class));
    }
    @Test void listsTypesSearchAndPagination() {
        assertThat(admin.posts("ORIGINAL","ACTIVE","摄影",20,0).items()).hasSize(1);
        assertThat(admin.posts("ASSIGNMENT","ACTIVE","",20,0).items().get(0).originalId()).isEqualTo(post.toString());
        assertThat(admin.posts("ORIGINAL","ALL","' OR 1=1 --",20,0).total()).isZero();
        assertThat(admin.posts("ORIGINAL","ALL","",1,1).items()).isEmpty();
        assertThat(admin.comments("ACTIVE","测试",post,20,0).total()).isEqualTo(1);
        assertThat(admin.comments("ACTIVE","",assignment,20,0).items()).isEmpty();
        assertThatThrownBy(()->admin.posts("INVALID","ACTIVE","",20,0)).isInstanceOf(ApiException.class);
        assertThatThrownBy(()->admin.comments("INVALID","",null,20,0)).isInstanceOf(ApiException.class);
        assertThatThrownBy(()->admin.posts("ORIGINAL","ALL","x".repeat(101),20,0)).isInstanceOf(ApiException.class);
    }
    @Test void deletesPostWithoutDeletingAssignmentsOrDatabaseRecord() {
        assertThat(publicPosts.comments(post)).hasSize(1);
        admin.deletePost(post,"admin");admin.deletePost(post,"admin");
        assertThat(admin.posts("ORIGINAL","ACTIVE","",20,0).total()).isZero();
        assertThat(admin.posts("ORIGINAL","DELETED","",20,0).total()).isEqualTo(1);
        assertThat(admin.posts("ASSIGNMENT","ACTIVE","",20,0).total()).isEqualTo(1);
        assertThat(publicPosts.comments(post)).isEmpty();
        assertThat(admin.comments("ACTIVE","",post,20,0).items().get(0).postDeleted()).isTrue();
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM admin_audit_logs",Integer.class)).isEqualTo(1);
    }
    @Test void deletesCommentAndUpdatesCounterOnlyOnce() {
        admin.deleteComment(comment,"admin");admin.deleteComment(comment,"admin");
        assertThat(publicPosts.comments(post)).isEmpty();
        assertThat(jdbc.queryForObject("SELECT comment_count FROM posts WHERE id=?",Integer.class,post.toString())).isZero();
        assertThat(admin.comments("DELETED","",post,20,0).total()).isEqualTo(1);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM admin_audit_logs",Integer.class)).isEqualTo(1);
        assertThat(admin.stats().get("deleted")).isEqualTo(1);
    }
    @Test void hiddenCommentDoesNotDecreaseVisibleCounter() {
        jdbc.update("UPDATE comments SET status='HIDDEN' WHERE id=?",comment.toString());
        jdbc.update("UPDATE posts SET comment_count=0 WHERE id=?",post.toString());
        admin.deleteComment(comment,"admin");
        assertThat(jdbc.queryForObject("SELECT comment_count FROM posts WHERE id=?",Integer.class,post.toString())).isZero();
    }
    @Test void failedAuditRollsBackDeletion() {
        jdbc.execute("DROP TABLE admin_audit_logs");
        assertThatThrownBy(()->admin.deleteComment(comment,"admin")).isInstanceOf(org.springframework.dao.DataAccessException.class);
        assertThat(publicPosts.comments(post)).hasSize(1);
        assertThat(jdbc.queryForObject("SELECT comment_count FROM posts WHERE id=?",Integer.class,post.toString())).isEqualTo(1);
        assertThatThrownBy(()->admin.deletePost(post,"admin")).isInstanceOf(org.springframework.dao.DataAccessException.class);
        assertThat(admin.posts("ORIGINAL","ACTIVE","",20,0).total()).isEqualTo(1);
    }
    @Test void missingTargetsCannotCreateAuditEntries() {
        assertThatThrownBy(()->admin.deletePost(UUID.randomUUID(),"admin")).isInstanceOf(ApiException.class);
        assertThatThrownBy(()->admin.deleteComment(UUID.randomUUID(),"admin")).isInstanceOf(ApiException.class);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM admin_audit_logs",Integer.class)).isZero();
    }
}
