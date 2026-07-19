# 光迹 LUMEN — 摄影复刻社区 MVP

面向摄影爱好者的作品分享、拍摄配方与复刻练习社区。

## iOS 原生版

原生 SwiftUI 工程位于 [ios/Lumen/Lumen.xcodeproj](ios/Lumen/Lumen.xcodeproj)，最低支持 iOS 17。运行和工程说明参见 [iOS README](ios/Lumen/README.md)。

## 后端运行

需要 JDK 21 或更高版本及 Maven 3.9：

```bash
cd backend
mvn spring-boot:run
```

服务默认监听 <http://127.0.0.1>，详细配置参见 [后端 README](backend/README.md)。

## 已实现

- 推荐作品流、搜索、点赞和关注
- 作品详情、拍摄配方、地点及评论
- 地图机位发现
- 加入和移出拍摄计划
- 发布原作和提交关联作业
- JPEG EXIF 自动解析：相机、镜头、焦段、光圈、快门、ISO、拍摄时间和 GPS
- 上传图片压缩与本地持久化
- 原作与作业并排对比
- 个人主页与本地作品
- 桌面和移动端响应式布局
- Java + Spring Boot API、阿里云 RDS MySQL 数据持久化
- 阿里云 OSS 客户端直传签名链路

## 当前数据方案

原生 iOS 版已经连接后端 API：

- 用户、作品、拍摄参数、地点、点赞、评论和复刻计划存入 MySQL。
- 图片由 iOS 使用短时签名 URL 直传 OSS，数据库只保存对象 Key 和访问 URL。
- 地点可选精确、约 100 米模糊或完全隐藏；接口不会返回隐藏的原始坐标。
- iOS 在后端不可用时保留本地演示内容，联网发布必须使用后端和 OSS。

后端配置和启动方式参见 [backend/README.md](backend/README.md)。

## 下一阶段

- 将 MVP 的 `x-user-id` 替换为正式登录鉴权
- 接入正式地图服务和地点搜索
- 服务端图片处理、EXIF 清理及地点隐私隔离
- 内容审核、举报和管理后台
- 将当前本地状态替换为多用户真实数据
