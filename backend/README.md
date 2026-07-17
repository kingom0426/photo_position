# Lumen API

Node.js + Express 后端，使用阿里云 RDS MySQL 保存业务数据，使用阿里云 OSS 保存照片。

## 配置

```bash
cp .env.example .env.local
```

填写 RDS 与 OSS 配置。`.env.local` 已被 Git 忽略，禁止提交密钥。

OSS 必填项：

- `OSS_REGION`：例如 `oss-cn-beijing`
- `OSS_BUCKET`
- `OSS_ACCESS_KEY_ID`
- `OSS_ACCESS_KEY_SECRET`
- `OSS_PUBLIC_BASE_URL`：建议填写绑定 HTTPS 的 CDN 或 Bucket 公网域名

AccessKey 应使用只允许目标 Bucket 指定目录上传的 RAM 子账号，不要使用阿里云主账号 AccessKey。

## 初始化和启动

```bash
npm install
npm run db:check
npm run db:migrate
npm start
```

服务默认监听 `http://127.0.0.1:8080`，健康检查为 `GET /api/health`。

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

iOS 模拟器默认请求 `http://127.0.0.1:8080/api`。真机调试时需将
`Lumen/Services/APIClient.swift` 中的地址改为 Mac 的局域网 IP 或已部署的 HTTPS API 域名。
