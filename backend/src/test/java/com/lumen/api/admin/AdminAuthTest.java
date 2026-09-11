package com.lumen.api.admin;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;
import com.lumen.api.common.ApiException;
import com.lumen.api.user.AuthRateLimiter;
import com.lumen.api.user.UserService;
import jakarta.servlet.http.Cookie;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.mock.web.MockHttpServletRequest;

class AdminAuthTest {
    JdbcTemplate jdbc; AdminAuth auth; UserService users; UserService.User user;
    @BeforeEach void setup() {
        // Keep the in-memory database alive for separate JDBC connections.
        jdbc=new JdbcTemplate(new DriverManagerDataSource("jdbc:h2:mem:"+UUID.randomUUID()+";MODE=MySQL;DB_CLOSE_DELAY=-1","sa",""));
        jdbc.execute("CREATE TABLE users(id VARCHAR(64),email_verified_at TIMESTAMP,status VARCHAR(16))");
        jdbc.execute("CREATE TABLE admin_members(user_id VARCHAR(64))");
        jdbc.execute("CREATE TABLE user_sessions(token_hash CHAR(64),expires_at TIMESTAMP)");
        jdbc.update("INSERT INTO users VALUES('admin',CURRENT_TIMESTAMP,'ACTIVE')");
        users=mock(UserService.class);user=new UserService.User("admin",null,"admin@example.invalid",null,"管理员",null,"","");
        when(users.require(any())).thenAnswer(call->{if(!"Bearer test-token".equals(call.getArgument(0)))throw new ApiException(HttpStatus.UNAUTHORIZED,"Please sign in");return user;});
        when(users.login(any(),any())).thenReturn(new UserService.AuthResult("test-token","",user,false));
        auth=new AdminAuth(users,jdbc,mock(AuthRateLimiter.class),"https://chenxi-edu.com");
    }
    MockHttpServletRequest request() {var request=new MockHttpServletRequest();request.addHeader("X-Lumen-Admin","1");request.addHeader("Origin","https://chenxi-edu.com");request.setCookies(new Cookie("lumen_admin","test-token"));return request;}
    @Test void ordinaryUserDeniedAndFreshLoginSessionRevoked() {
        assertThatThrownBy(()->auth.require(request())).isInstanceOf(ApiException.class).hasMessageContaining("权限");
        assertThatThrownBy(()->auth.login("admin@example.invalid","test-password",request())).isInstanceOf(ApiException.class).hasMessageContaining("权限");
        verify(users).logout("Bearer test-token");
    }
    @Test void adminMustBeVerifiedActiveAndStillAuthorized() {
        jdbc.update("INSERT INTO admin_members VALUES('admin')");assertThat(auth.require(request())).isEqualTo(user);
        jdbc.update("UPDATE users SET email_verified_at=NULL");assertThatThrownBy(()->auth.require(request())).isInstanceOf(ApiException.class);
        jdbc.update("UPDATE users SET email_verified_at=CURRENT_TIMESTAMP,status='DISABLED'");assertThatThrownBy(()->auth.require(request())).isInstanceOf(ApiException.class);
        jdbc.update("UPDATE users SET status='ACTIVE'");jdbc.update("DELETE FROM admin_members");assertThatThrownBy(()->auth.require(request())).isInstanceOf(ApiException.class);
    }
    @Test void missingCookieAndBearerHeaderCannotEnter() {
        var request=new MockHttpServletRequest();request.addHeader("Authorization","Bearer test-token");
        assertThatThrownBy(()->auth.require(request)).isInstanceOf(ApiException.class);
    }
    @Test void mutationsRequireHeaderAndTrustedOrigin() {
        auth.checkMutation(request());
        var missing=new MockHttpServletRequest();assertThatThrownBy(()->auth.checkMutation(missing)).isInstanceOf(ApiException.class);
        var foreign=request();foreign.removeHeader("Origin");foreign.addHeader("Origin","https://untrusted.example");
        assertThatThrownBy(()->auth.checkMutation(foreign)).isInstanceOf(ApiException.class);
    }
    @Test void cookieIsSecureHttpOnlyAndShortLived() {
        assertThat(auth.cookie("test-token")).contains("HttpOnly","Secure","SameSite=Strict","Path=/api/admin","Max-Age=28800");
        assertThat(auth.cookie("")).contains("Max-Age=0");
    }
}
