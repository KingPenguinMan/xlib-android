# xlib Android

当前版本为 **0.2.2**。

一个面向 Android 手机和平板的非官方书籍客户端，使用 Flutter 开发。支持线路检测、登录、搜索、查看书籍详情、管理下载任务和查看账户历史记录。

> 本项目由社区独立维护，与 Z-Library 官方及 `heartleo/zlib` 项目均无隶属关系。线路和服务接口由相关服务提供，可能随时变化；请遵守所在地法律法规和内容版权要求。

## 学习交流与版权声明

**本项目仅供学习、技术研究与交流使用。**

- xlib 是独立开发的非官方客户端，不属于 Z-Library 官方产品，也未获得其官方背书或授权。
- Z-Library 板块中的书籍信息、封面及下载资源均来自 Z-Library 相关服务；本项目仅提供客户端交互功能，不运营书籍资源服务器，不在本仓库托管或分发书籍文件。微信读书功能所展示的内容来自微信读书服务。
- 书籍、封面、商标及其他第三方内容的版权归各自权利人所有。本项目的开源许可证仅适用于相应源代码，不授予任何第三方书籍或资源的使用、复制、传播或商业利用权利。
- 请仅访问、下载和使用你依法有权使用的内容，遵守所在地法律法规及相关服务条款，尊重作者与出版机构，支持正版。请勿将本项目用于侵权传播或其他违法用途。
- 如认为本仓库中的代码、图片或其他材料侵犯了你的权利，请通过 [GitHub Issues](https://github.com/KingPenguinMan/xlib-android/issues) 提供具体文件位置、权利说明及必要证据，维护者将核查处理。第三方服务上的书籍内容请向对应服务提供者或权利人反馈；请勿在公开 Issue 中提交身份证件、账户密码等敏感信息。

学习交流用途声明不替代实际所需的版权许可，也不构成对第三方资源合法性、可用性或安全性的保证。

## 功能

- 自动检测可用线路，也可手动选择线路。
- 登录或注册账户，搜索书籍并查看详情。
- 首页瀑布流推荐，滚动到底部自动加载后续内容。
- 查看账户下载历史，支持封面、下载时间和分页加载。
- 管理下载任务，暂停、继续、取消、打开或分享已下载文件。
- 默认将文件保存到公共目录 `Download/Books`，也可以选择其他目录。
- 支持浅色、深色和跟随系统外观。

## 下载

在 [Releases](https://github.com/KingPenguinMan/xlib-android/releases) 下载适合设备的 APK。32 位 ARM 设备选 `armeabi-v7a`，64 位 ARM 手机选 `arm64-v8a`，x86_64 模拟器选 `x86_64`。

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

[0.2.1 原版更新说明](releases/v0.2.1-stable/更新说明.md) · [签名和发布流程](ci/发布流程.md)

## 下载位置

Android 10 及以上版本通过系统媒体存储写入 `Download/Books`。Android 9 及更早版本首次下载时需要授予存储权限。用户选择自定义目录后，应用会使用该目录；可在应用的「我的 → 下载目录」中恢复默认位置。

## 项目结构

- `lib/`：Flutter 页面、状态管理、接口请求和数据模型。
- `android/`：Android 原生下载、文件打开与分享实现。
- `assets/`：阅读邀请插画等资源。

## 许可证与致谢

本仓库采用 MIT License。项目实现参考了 [heartleo/zlib](https://github.com/heartleo/zlib) 的接口交互方式；保留原项目许可证及版权声明。Flutter 依赖及其许可证信息可通过 `flutter pub deps` 查看。
## 历史版本记录（0.1.2）

从 Gitee 发行页下载对应架构的安装包。此版暂停启动更新检查。图书详情中的在线阅读支持 PDF 和文字 EPUB，将文件载入应用缓存后阅读，单个文件上限为 128 MB。我的收藏保存在设备本地。

## 源码同步说明

本次基于 Gitee 正式发布标签 v0.2.1（95aa2fe）同步，统一应用品牌为 xlib。Android 包名保留，沿用维护者本机正式签名流程，服务域名、上游版权和已有网盘密码保留原值。从 0.2.2 起，应用内更新使用本 GitHub 仓库的正式 Release。旧版仍查询 Gitee 的用户需手动安装一次 GitHub 新版。Gitee 0.2.1 附件与本次签名不同，若无法覆盖安装，请先备份数据；详见 [0.2.2 安装说明](releases/v0.2.2-stable/更新说明.md)。
