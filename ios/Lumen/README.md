# 光迹 LUMEN iOS

SwiftUI 原生 iOS MVP，最低支持 iOS 17。

## 打开工程

使用 Xcode 打开：

```text
ios/Lumen/Lumen.xcodeproj
```

选择 `Lumen` Scheme 和任意 iPhone 模拟器后运行。

## 当前能力

- SwiftUI 原生首页与摄影作品流
- 作品详情、拍摄配方和评论
- MapKit 原生机位地图
- 拍摄计划及关联作业入口
- PhotosPicker 原生照片选择
- 使用 ImageIO 读取相机、镜头、焦段、光圈、快门、ISO、时间和 GPS
- 上传图片缩放与 JPEG 压缩
- RDS 后端作品流、点赞、评论和复刻计划同步
- OSS 短时签名直传与远程图片展示
- 原作与复刻作业对比
- Codable JSON 本地持久化
- 个人主页和演示数据恢复

## 命令行构建

如果 `xcode-select -p` 没有指向完整 Xcode，可以只对当前命令指定：

```bash
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
xcodebuild -project ios/Lumen/Lumen.xcodeproj \
  -scheme Lumen \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

如果 Xcode 不在 `/Applications/Xcode.app`，请替换为实际路径。无需修改系统全局的 `xcode-select`。

## 数据边界

iOS 客户端默认连接 `https://chenxi-edu.com/api`。后端暂时不可用时保留本地演示数据；云端列表非空后会同步展示。发布照片需要后端已配置阿里云 OSS。
