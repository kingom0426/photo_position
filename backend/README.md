# Lumen API

Java + Spring Boot 后端，使用阿里云 RDS MySQL 保存业务数据，使用阿里云 OSS
保存照片，并使用已验证的邮箱与密码完成账号注册登录。

## 环境要求

- JDK 17 或更高版本
- Maven 3.9 或更高版本

## 配置

```bash
cp .env.example .env.local
```

填写 RDS 与 OSS 配置。Spring Boot 启动时会自动读取后端目录下的 `.env.local`。

邮件配置单独存放在不纳入 Git 的 `.env.mail.local`（权限 `600`），启动时也会读取：
`MAIL_HOST`、`MAIL_PORT`、`MAIL_USERNAME`、`MAIL_PASSWORD`（SMTP 授权码）、`MAIL_FROM`。
默认使用 163 SMTP SSL 465，校验证书；`PUBLIC_BASE_URL` 必须为正式 HTTPS 站点。
不得将授权码放入客户端、提交 Git 或输出到日志。现有 `.env.local` 是历史跟踪文件，不要往其中添加邮件凭据。

注册：先请求 `/api/auth/email-code`，再携带 `email`、`password`、`verificationCode`、
`nickname`、`consentAccepted`、`consentVersion` 请求 `/api/auth/register`。
验证码 10 分钟有效，验证尝试受独立事务限频保护；注册成功后原子消费。
邮件异步发送，申请接口的统一提示不代表邮件已送达，失败仅记录挑战 ID 和异常类型。

找回：请求 `/api/auth/forgot-password` 后，用户在邮件中的 HTTPS 页面设置新密码。
一次性随机令牌保存在 URL fragment 中（不进入访问日志），数据库仅保存摘要，有效期 30 分钟。
`POST /api/auth/reset-password` 接受 `token`、`password`；成功后撤销该账号全部会话及其他重置凭证。
`PUT /api/auth/me/password` 需登录并提交 `oldPassword`、`newPassword`，成功后同样重新登录。

旧账号不自动改写邮箱、用户名或密码。已有邮箱可凭原密码登录，也可通过该邮箱重置；
没有邮箱的旧账号须管理员核验所有权后单独处理，不允许按昵称自动合并。
旧客户端的用户名登录字段暂时兼容，但新注册必须完成邮箱验证。

OSS 必填项：

- `OSS_REGION`：例如 `oss-cn-beijing`
- `OSS_BUCKET`
- `OSS_ACCESS_KEY_ID`
- `OSS_ACCESS_KEY_SECRET`
- `OSS_PUBLIC_BASE_URL`：建议填写绑定 HTTPS 的 CDN 或 Bucket 公网域名

AccessKey 应使用只允许目标 Bucket 指定目录上传的 RAM 子账号，不要使用阿里云主账号 AccessKey。

## 初始化和启动

```bash
mvn spring-boot:run
```

Flyway 会在服务启动时自动创建或升级数据表。服务默认监听
`http://127.0.0.1:80`，健康检查为 `GET /api/health`。

运行测试和打包：

```bash
mvn test
mvn package
java -jar target/lumen-api-0.1.0.jar
```

## MVP 接口

- `GET /api/posts`
- `GET /api/posts?feed=following`
- `GET /api/posts?feed=nearby&latitude=...&longitude=...&radiusKm=...`
- `GET /api/discovery/search?q=...`
- `GET /api/discovery/tags`
- `GET /api/notifications`
- `PUT /api/notifications/:id/read`
- `PUT /api/notifications/read-all`
- `GET /api/posts/:id`
- `DELETE /api/posts/:id`
- `POST /api/posts`
- `GET /api/auth/consent`
- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/email-code`
- `POST /api/auth/forgot-password`
- `GET|POST /api/auth/reset-password`
- `PUT /api/auth/me/password`
- `GET /api/auth/me`
- `POST /api/auth/logout`
- `PUT /api/posts/:id/like`
- `GET|POST /api/posts/:id/comments`
- `PUT /api/posts/:id/plan`
- `POST /api/uploads/presign`

作品列表、详情和评论列表允许游客访问；发布、上传、点赞、评论和加入计划需要
`Authorization: Bearer <token>`。注册时必须签署当前版本用户知情同意书；密码使用
PBKDF2-HMAC-SHA256、随机盐和 120,000 次迭代生成摘要，不保存明文。登录成功后由
服务端签发会话令牌，服务端仅保存令牌摘要。

图片上传流程：

1. iOS 将照片生成 480px 缩略图、1280px 展示图，并保留原图。
2. iOS 分别请求 `/api/uploads/presign`，使用返回的 10 分钟有效 PUT URL 直传 OSS。
3. 上传成功后，iOS 调用 `/api/posts` 保存三个对象 Key、EXIF 与地点权限。
4. Bucket 保持私有读；列表使用缩略图，只有打开大图时客户端才请求原图签名 URL。

## iOS 本地联调

iOS 模拟器默认请求 `http://127.0.0.1/api`。真机调试时需将
`Lumen/Services/APIClient.swift` 中的地址改为 Mac 的局域网 IP 或已部署的 HTTPS API 域名。
