照片按钮布局验证（2026-09-11）

使用 PublishView 的 PhotosPicker 预览代码及 Components 的 PostPhotoView，在 iOS 26.5 模拟器 Form 中渲染，替代照片为本地合成测试图。截图确认按钮横向、文字完整、位于卡片边界内。正式 App 构建通过并已安装至杜鑫；2026-09-11 09:09 解锁后真机启动成功。

修复：以显式 HStack 替代 Label，固定 36pt 高，图标 16pt，文字单行，外边距 12pt。
