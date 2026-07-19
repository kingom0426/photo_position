# Lumen API

Java + Spring Boot 后端，使用阿里云 RDS MySQL 保存业务数据，使用阿里云 OSS 保存照片。

## 环境要求

- JDK 17 或更高版本
- Maven 3.9 或更高版本

## 配置

```bash
cp .env.example .env.local
```

填写 RDS 与 OSS 配置。Spring Boot 启动时会自动读取后端目录下的 `.env.local`。

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
- `GET /api/posts/:id`
- `POST /api/posts`
- `PUT /api/posts/:id/like`
- `GET|POST /api/posts/:id/comments`
- `PUT /api/posts/:id/plan`
- `POST /api/uploads/presign`

除健康检查外，当前 MVP 使用 `x-user-id` 请求头模拟登录。正式上线前必须替换为服务端签发并验证的登录令牌。

图片上传流程：

1. iOS 请求 `/api/uploads/presign`。
2. iOS 使用返回的 10 分钟有效 PUT URL 直传 OSS。
3. 上传成功后，iOS 调用 `/api/posts` 保存对象 Key、URL、EXIF 与地点权限。
4. Bucket 保持私有读；作品接口会为图片生成一小时有效的下载签名 URL。

## iOS 本地联调

iOS 模拟器默认请求 `http://127.0.0.1/api`。真机调试时需将
`Lumen/Services/APIClient.swift` 中的地址改为 Mac 的局域网 IP 或已部署的 HTTPS API 域名。
