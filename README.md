<p align="center">
  <img src="docs/app-icon.png" width="128" alt="WorkLog">
</p>

# WorkLog

本地、单用户的 Mac 工作日志。在日、周、月视图里记下每天做了什么，需要汇报时导出 Markdown。

## 版本记录

新版本写在上面，以前的版本留在下面。打开 DMG 后把 WorkLog.app 拖进「应用程序」；ZIP 则先解压，再把应用放进去。这些安装包没有经过 Apple 公证，第一次打开时在 Finder 里按住 Control 点按应用，选择「打开」。

### 0.0.2

2026-10-29 · 需要 macOS 14 或更高版本

- 周视图和月视图里，点中某一天后可以粘贴。点到日期以外的地方，选中框还在，颜色变浅，这时粘贴不起作用。日视图不能粘贴。
- 点中一条事项可以复制，再到另一天粘贴成新的事项。
- 设置里的二级类型改成标签。点标签后面的加号添加，双击标签修改，点叉删除，也可以拖动排序。
- 下方查看的描述固定为一定宽度。字太多会换行，再多就在这一列里滚动。备注占用右边剩下的宽度。

- [WorkLog-0.0.2.dmg](https://github.com/bang668/WorkLog/releases/download/v0.0.2/WorkLog-0.0.2.dmg)
- [WorkLog-0.0.2.zip](https://github.com/bang668/WorkLog/releases/download/v0.0.2/WorkLog-0.0.2.zip)

### 0.0.1

2026-10-27 · 需要 macOS 14 或更高版本

首次发布。日志记在这台 Mac 的一个文件夹里。

- 日、周、月三种视图
- 添加和编辑用半抽屉；查看可以放在右侧、下方，或点开后直接编辑
- 事项有描述、备注，以及一级、二级类型
- 导出 Markdown，或复制到剪贴板
- 从文本导入旧记录。日期单独一行，事项缩进写在下面。已有事项只追加，同一天里描述相同的不再写入
- 可以设置登录后自动打开

- [WorkLog-0.0.1.dmg](https://github.com/bang668/WorkLog/releases/download/v0.0.1/WorkLog-0.0.1.dmg)
- [WorkLog-0.0.1.zip](https://github.com/bang668/WorkLog/releases/download/v0.0.1/WorkLog-0.0.1.zip)

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

## 许可证

保留所有权利。发布页上的安装包可以下载使用。源码没有开放许可。
