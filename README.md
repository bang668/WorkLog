# WorkLog

本地、单用户的 Mac 工作日志。在日、周、月视图里记下每天做了什么，需要汇报时导出 Markdown。

需求、原型和 UI 稿不在这个仓库里。

## 环境

- macOS 14 或更高版本
- 从源码编译需要 Xcode 15 或更高版本

## 编译

```bash
open WorkLog.xcodeproj
```

选择 **WorkLog** 这个 scheme，然后运行（⌘R）。也可以在终端执行：

```bash
xcodebuild -project WorkLog.xcodeproj -scheme WorkLog -configuration Debug -destination 'platform=macOS' build
xcodebuild -project WorkLog.xcodeproj -scheme WorkLog -destination 'platform=macOS' test
```

Debug 编译完成后，用 Xcode 直接运行，或到 DerivedData 里找到生成的应用。
