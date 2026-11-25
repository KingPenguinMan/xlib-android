# z-lib Android

当前开发基线为 **0.1.2 稳定版**。

一个面向 Android 手机和平板的非官方 z-lib 客户端，使用 Flutter 开发。支持线路检测、登录、搜索、查看书籍详情、管理下载任务和查看账户历史记录。

> 本项目由社区独立维护，与 Z-Library 官方及 `heartleo/zlib` 项目均无隶属关系。线路和服务接口由相关服务提供，可能随时变化；请遵守所在地法律法规和内容版权要求。

## 功能

- 自动检测可用线路，也可手动选择线路。
- 登录或注册账户，搜索书籍并查看详情。
- 首页瀑布流推荐，滚动到底部自动加载后续内容。
- 查看账户下载历史，支持封面、下载时间和分页加载。
- 管理下载任务，暂停、继续、取消、打开或分享已下载文件。
- 默认将文件保存到公共目录 `Download/Books`，也可以选择其他目录。
- 支持浅色、深色和跟随系统外观。

## 下载

在 [Releases](https://gitee.com/Gjbone/zlib-android/releases/tag/v0.1.2) 下载适合设备的 APK。32 位 ARM 设备选 `armeabi-v7a`，64 位 ARM 手机选 `arm64-v8a`，x86_64 模拟器选 `x86_64`。

## 从源码构建

在仓库根目录构建。需要安装 Flutter 3.47.9、Android SDK 和 JDK 17。Flutter/Dart 版本需满足 [`pubspec.yaml`](pubspec.yaml) 中的 SDK 约束。

```powershell
flutter pub get
flutter analyze
flutter build apk --release --target-platform android-arm64
```

APK 输出位置：

```text
build/app/outputs/flutter-apk/app-release.apk
```

如需生成其他架构，可将 `--target-platform` 改为 Flutter 支持的平台组合，例如 `android-arm,android-arm64,android-x64`。

[更新说明](releases/v0.1.2-stable/更新说明.md) · [SHA-256 校验值](releases/v0.1.2-stable/SHA256SUMS.txt) · [签名和发布流程](ci/发布流程.md)

## 下载位置

Android 10 及以上版本通过系统媒体存储写入 `Download/Books`。Android 9 及更早版本首次下载时需要授予存储权限。用户选择自定义目录后，应用会使用该目录；可在应用的「我的 → 下载目录」中恢复默认位置。

## 项目结构

- `lib/`：Flutter 页面、状态管理、接口请求和数据模型。
- `android/`：Android 原生下载、文件打开与分享实现。
- `assets/`：应用图标资源。

## 许可证与致谢

本仓库采用 MIT License。项目实现参考了 [heartleo/zlib](https://github.com/heartleo/zlib) 的接口交互方式；保留原项目许可证及版权声明。Flutter 依赖及其许可证信息可通过 `flutter pub deps` 查看。
## 0.1.2 稳定版安装与预览

从 Gitee 发行页下载对应架构的安装包。此版暂停启动更新检查。图书详情中的在线阅读支持 PDF 和文字 EPUB，将文件载入应用缓存后阅读，单个文件上限为 128 MB。我的收藏保存在设备本地。
