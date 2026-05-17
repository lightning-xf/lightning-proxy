# Lightning Proxy

[![License](https://img.shields.io/badge/License-AGPL--3.0-red.svg)](https://www.gnu.org/licenses/agpl-3.0.html)
[![Flutter](https://img.shields.io/badge/Flutter-v3.22+-blue.svg)](https://flutter.dev)
[![Xray](https://img.shields.io/badge/Xray-Core-orange.svg)](https://github.com/XTLS/Xray-core)

Lightning Proxy 是一款基于 Flutter 开发的高性能、现代化 Android VPN 客户端。它集成了强大的 Xray-core，旨在提供极致的连接速度、灵活的分流规则以及优雅的用户体验。

## 🚀 下载安装

您可以从 [GitHub Releases](https://github.com/lightning-xf/lightning-proxy/releases) 页面下载最新的安装包。

### 安装包版本说明：
- **app-arm64-v8a-release.apk**：**推荐版本**。适用于几乎所有现代 Android 手机（如小米、华为、三星、Pixel 等）。
- **app-armeabi-v7a-release.apk**：适用于较旧的 32 位 Android 设备。
- **app-x86_64-release.apk**：适用于在电脑上运行的 Android 模拟器。

---

## ✨ 核心特性

### 1. 强大的协议支持
- **全协议覆盖**：完美支持 VMess, VLESS (Reality/Vision), Trojan, Shadowsocks, Hysteria2, TUIC 等主流代理协议。
- **高性能内核**：直接调用原生 Go 编译的 Xray-core，确保加解密效率和连接稳定性。

### 2. 智能分流 (Rule Mode)
- **绕过中国模式**：自动识别并直连中国大陆流量（基于 `geosite:cn` 和 `geoip:cn`），国外流量走代理。
- **FakeDNS 技术**：内置 FakeDNS 路由，有效解决 DNS 污染问题，并提升 Google 服务及 Chrome 浏览器的访问成功率。
- **灵活切换**：支持“全局代理”、“规则分流”和“完全直连”三种模式。

### 3. 应用分流 (App Splitting)
- 支持按应用选择是否走 VPN 隧道，您可以指定特定的浏览器或游戏走代理，其他应用保持直连。

### 4. 极致 UI/UX
- **流畅动画**：使用 `RepaintBoundary` 优化重绘，确保在连接/断开瞬间界面无卡顿。
- **现代化设计**：遵循 Material Design 3 设计规范，支持深色模式。
- **实时日志**：内置日志查看器，方便排查连接问题。

---

## �️ 构建与开发环境

如果您想自行编译本项目，请确保您的开发环境满足以下要求：

### 1. 环境依赖
- **Flutter SDK**: `v3.22.0` 或更高版本。
- **Dart SDK**: `v3.4.0` 或更高版本。
- **Android SDK**: API Level 34 (Android 14) 及以上。
- **Go 环境**: `v1.22.0` 或以上（用于编译 `go_core`）。
- **Gomobile**: 用于将 Go 代码打包为 Android 库。

### 2. 关键环境变量
在编译 `go_core` 之前，请确保设置以下环境变量：
- `ANDROID_HOME`: Android SDK 路径。
- `ANDROID_NDK_HOME`: Android NDK 路径。

---

## 📦 打包发布命令

### 1. 编译 Go 核心 (Xray JNI)
进入 `go_core` 目录并运行以下命令（或使用根目录的脚本）：
```bash
# 使用 gomobile 编译为 aar
gomobile bind -v -target=android/arm64 -androidapi 21 -o ../android/app/libs/libxray.aar .
```

### 2. 编译 Flutter 安装包
在项目根目录下运行：
```bash
# 清理缓存
flutter clean

# 获取依赖
flutter pub get

# 编译正式版 APK (包含所有架构)
flutter build apk --release

# 或者分别编译特定架构以减小包体积
flutter build apk --release --split-per-abi
```
生成的 APK 路径：`build/app/outputs/flutter-apk/`

---

## � 开源协议

本项目采用 [AGPL-3.0 License](LICENSE) 协议开源。
这意味着如果您在服务器上使用此代码并提供服务，您必须公开您的源代码。

## 🤝 贡献与反馈

- **提交 Bug**: 请通过 GitHub Issues 提交。
- **贡献代码**: 欢迎提交 Pull Request。
- **项目链接**: [https://github.com/lightning-xf/lightning-proxy](https://github.com/lightning-xf/lightning-proxy)

---
*Powered by Lightning Team*
