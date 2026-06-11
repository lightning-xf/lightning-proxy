# ⚡ Lightning Proxy (Android) v1.0.0

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Android-green.svg?style=for-the-badge&logo=android" alt="Platform">
  <img src="https://img.shields.io/badge/Flutter-v3.11+-blue.svg?style=for-the-badge&logo=flutter" alt="Flutter">
  <img src="https://img.shields.io/badge/Xray-Core-orange.svg?style=for-the-badge&logo=xray" alt="Xray">
  <img src="https://img.shields.io/badge/License-AGPL--3.0-red.svg?style=for-the-badge" alt="License">
</p>

## 📖 项目介绍

**Lightning Proxy** 是一款专为 **Android** 平台量身打造的高性能、现代化 VPN 客户端。它完美结合了 Flutter 极速的 UI 交互体验与 Xray 内核强大的协议处理能力，旨在为用户提供最纯净、最智能、最易用的网络加速体验。

本项目深度集成 Android 系统特性，通过自研的配置生成引擎，将复杂的网络协议封装为简单直观的操作界面，无论是专业玩家还是普通小白都能轻松上手。

---

## 📱 客户端功能详解

### 1. 首页 (Home)
- **核心控制**：一键开启/关闭 VPN 连接，实时显示连接状态。
- **流量监控**：实时上行/下行速率显示。
- **模式切换展示**：直观展示当前处于“单节点模式”还是“代理组模式”。
- **快捷信息**：显示当前连接的节点名称、协议类型及服务器地址。

### 2. 节点管理 (Nodes)
- **多协议支持**：VMess, VLESS, Trojan, Shadowsocks, Hysteria2, TUIC 等。
- **节点操作**：支持手动添加、剪贴板导入、二维码扫描。
- **延迟测试**：一键对所有节点进行 Ping 延迟测试，快速筛选最优节点。
- **分组管理**：清晰展示不同订阅来源的节点。

### 3. 代理组管理 (Proxy Groups)
- **高级策略**：
  - **手动选择 (Select)**：用户自定义固定节点。
  - **延迟自动切换 (URL Test)**：根据实时延迟自动选择最快节点。
  - **故障自动转移 (Fallback)**：主节点不可用时自动切换备用。
  - **负载均衡 (Load Balance)**：多节点并发，分散网络压力。
- **策略嵌套**：支持代理组嵌套，实现更复杂的路由逻辑。

### 4. 路由与规则 (Routing & Rules)
- **规则集订阅 (Rule Set)**：一键订阅远程分流规则（如绕过中国、广告过滤）。
- **自定义规则**：支持基于域名、IP、端口、网络协议的自定义分流规则。
- **路由策略**：支持全局、分流（绕过局域网/大陆）、直连三种全局路由模式。

### 5. 高级设置 (Settings)
- **小白科普**：为每一个配置项（如 Mux, FakeDNS, BBR 等）提供 **[?] 详细说明图标**。
- **系统集成**：支持开机自启、断线重连、局域网共享。
- **备份恢复**：一键导出/导入完整配置。
- **多语言支持**：完美支持简体中文与英文。

---

## 🛠️ 技术环境要求

### 1. 核心构建环境 (Core Build)
用于编译底层的 Go 核心库 (`go_core`)。
- **Go**: v1.20 或更高版本。
- **Gomobile**: 用于将 Go 编译为 Android AAR 库。
- **Android NDK**: 推荐 r25c 或更高。
- **构建脚本**: `.\build_android_core.ps1` (Windows) 或 `./build_android_core.sh` (Linux/macOS)。

### 2. 打包环境 (Build Environment)
用于构建最终的 Android APK。
- **Flutter SDK**: v3.11.4 或更高版本。
- **Java/JDK**: JDK 17。
- **Android SDK**: API Level 33+。
- **构建工具**: Gradle 7.5+。

### 3. 运行环境 (Runtime)
- **系统版本**: Android 7.0 (API 24) 及以上。
- **架构适配**: `arm64-v8a`, `armeabi-v7a`, `x86_64`。

---

## 🚀 构建、编译与打包流程

### 1. 初始化环境
确保已安装上述技术环境要求中的所有工具。
```powershell
# 检查 Flutter 环境
flutter doctor
# 检查 Go 环境
go version
```

### 2. 编译 Go 核心内核 (AAR)
这是最关键的第一步，将 Xray-core 编译为 Android 识别的二进制库。
```powershell
# Windows 下运行 (推荐)
.\build_android_core.ps1
```
*该脚本会自动处理环境变量，并在 `android/app/libs` 目录下生成 `go_core.aar`。*

### 3. 获取 Flutter 依赖
```powershell
flutter pub get
```

### 4. 开发环境运行
```powershell
# 建议使用 --release 模式以获得真实的 Xray 运行性能
flutter run --release
```

### 5. 最终发布打包 (Release APK)
推荐使用分架构打包，以大幅减小单 APK 的体积。
```powershell
# 执行一键打包脚本
.\build_release.bat
```
或者手动执行 Flutter 指令：
```powershell
# 生成分架构的 Release APK
flutter build apk --release --split-per-abi
```
*产物路径：`build/app/outputs/flutter-apk/`*

---

## 📂 项目结构树

```text
D:.
├───android                # Android 原生层 (Kotlin 实现)
│   ├───app
│   │   └───src/main/kotlin/com/lightning/proxy
│   │       ├───channel    # Flutter 与原生通信接口 (VPN 隧道/日志)
│   │       ├───kernel     # 内核管理工具
│   │       └───service    # Android VpnService 系统服务实现
├───go_core                # 基于 Xray-core 的 Go 核心代码
├───lib                    # Flutter 业务逻辑层
│   ├───core               # 核心服务 (状态管理、配置生成、协议解析)
│   ├───pages              # 所有的 UI 界面
│   ├───theme              # 主题与视觉定义
│   ├───widgets            # 通用组件
│   └───main.dart          # App 入口
├───pubspec.yaml           # Flutter 依赖配置
├───build_release.bat      # 一键打包脚本 (Windows)
└───README.md              # 本文档
```

---

## 📄 开源协议

本项目采用 **[AGPL-3.0 License](LICENSE)** 协议开源。

---

## 🤝 贡献与反馈

如果您在使用过程中遇到任何问题，或有更好的改进建议，欢迎提交 **Issue** 或 **Pull Request**。

- **开发者**: Lightning Team
- **项目主页**: [Lightning Proxy GitHub](https://github.com/lightning-xf/lightning-proxy)
