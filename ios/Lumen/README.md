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
- 原图、展示图、缩略图三档上传，列表默认只加载缩略图
- 原作与复刻作业对比
- 邮箱注册、登录与会话恢复
- 游客可浏览，发布、点赞、评论和加入计划需登录
- 底部发布入口使用橙底白色加号；作品发布缺少照片或标题时显示弹窗和行内提醒，支持定位到缺失项

## 发布必填校验检查

在仓库根目录运行以下命令，直接检查生产代码中的校验规则，无需登录或创建线上作品：

```bash
{ printf 'import Foundation\n'; sed -n '/^enum PublishValidation {/,/^}/p' ios/Lumen/Lumen/Views/PublishView.swift; cat ios/Lumen/Tests/PublishValidationChecks.swift; } | swift -module-cache-path /private/tmp/lumen-publish-validation-module-cache -
```

覆盖未选照片、空标题、纯空白标题、正常作品、作业自动标题及编辑已有作品，共 8 组场景和 2 条提示文案。

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

## 数据与登录

iOS 客户端默认连接 `https://chenxi-edu.com/api`。作品和用户数据均来自后端数据库，
不再内置或恢复演示数据。发布照片需要后端已配置阿里云 OSS。
