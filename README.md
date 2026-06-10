# Lightning Proxy (Windows)

[![License](https://img.shields.io/badge/license-AGPL--3.0-orange.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-v3.22+-blue.svg)](https://flutter.dev)
[![Xray](https://img.shields.io/badge/Xray-Core-orange.svg)](https://github.com/XTLS/Xray-core)
[![Platform](https://img.shields.io/badge/Platform-Windows-blue.svg)](https://www.microsoft.com/windows)

Lightning Proxy 是一款专为 Windows 平台打造的、基于 Flutter 与 Xray 内核的高性能代理客户端。它结合了现代化的 UI 设计语言与极致的功耗优化技术，旨在为用户提供快速、稳定且轻量的网络代理体验。

---

## ✨ 核心特性

### 1. 极致功耗管理 (Zero-Footprint Architecture)
针对代理软件长期后台挂机的特性，本项目实施了深度的功耗审计与重构：
- **真·深睡眠模式 (Ultra Deep Sleep)**：当窗口最小化或隐藏至系统托盘时，程序会物理卸载整个 UI 渲染树，并强制挂起 Flutter 引擎。此时 GPU 占用率为 **0%**，CPU 仅保留核心代理逻辑。
- **DWM 渲染路径断开**：在窗口隐藏状态下，通过 `setOpacity(0)` 与 `blur()` 技术彻底切断与 Windows Desktop Window Manager 的合成路径。
- **视觉特效静态化**：移除了所有高频重绘的 UI 组件（如波纹动画、呼吸灯、动态流量图表），改用低开销的静态/半静态视觉反馈。

### 2. 强大的协议支持 (Xray Core)
内置最新越狱版 Xray-core，全面支持主流加密协议：
- **协议全覆盖**：VLESS (Reality), VMess, Trojan, Shadowsocks, Hysteria2, TUIC 等。
- **传输层优化**：支持 TCP, mKCP, WebSocket, HTTP/2, QUIC, gRPC 等传输配置。
- **智能路由系统**：内置成熟的绕过中国大陆 (Bypass China) 规则，支持域名/IP 分流与自动化路由优先级管理。

### 3. Windows 平台深度适配
- **UWP 应用免代理**：内置一键式 UWP 应用 Loopback Exemption 管理工具，解决 UWP 应用无法走代理的痛点。
- **无边框现代 UI**：自定义无边框标题栏，深度对标 Windows 11 Fluent Design 设计语言。
- **托盘静默交互**：完善的系统托盘右键菜单，支持在不唤起主界面的情况下快速切换模式、节点及代理状态。
- **开机自启与单实例运行**：支持开机静默自启，并确保同一时间仅有一个实例运行。

---

## 🛠️ 技术架构

### 核心技术栈
- **UI 框架**：[Flutter](https://flutter.dev) (Windows Desktop)
- **状态管理**：[Riverpod](https://riverpod.dev)
- **底层核心**：[Xray-core](https://github.com/XTLS/Xray-core) (基于 Go 开发)
- **原生桥接**：Windows C++ / Win32 API / PowerShell

### 项目结构说明
```text
lib/
├── core/               # 核心业务逻辑
│   ├── windows_vpn_manager.dart # Windows 原生进程管理与代理控制
│   ├── vpn_provider.dart        # VPN 全局状态机
│   ├── config_generator.dart    # 自动化 Xray JSON 配置引擎
│   └── traffic_monitor.dart     # 轻量化流量统计
├── pages/              # 业务页面 (首页、节点、设置、日志等)
├── widgets/            # 经过性能审计的 UI 组件
└── main.dart           # 程序入口与生命周期管理
go_core/                # Xray 核心相关的 Go 代码与编译脚本
assets/windows/         # 核心二进制资源 (xray-core.exe, wintun.dll)
```

---

## 🚀 开发与编译

### 编译环境要求
- **Flutter SDK**：3.22.0 或更高版本
- **Visual Studio**：2022 (需安装 "使用 C++ 的桌面开发" 工作负载)
- **Go**：1.22+ (若需自行编译 `go_core`)
- **Inno Setup**：(可选，用于生成安装包)

### 快速构建
1. **获取代码**：
   ```powershell
   git clone https://github.com/lightning-xf/lightning-proxy.git
   cd lightning-proxy
   ```
2. **安装依赖**：
   ```powershell
   flutter pub get
   ```
3. **Release 编译**：
   ```powershell
   flutter build windows --release
   ```
   编译产物位于 `build/windows/x64/runner/Release/`。

---

## 📄 开源协议

本项目采用 [AGPL-3.0 License](LICENSE) 协议开源。请在遵守协议的前提下进行二次开发或分发。

## 🤝 贡献与反馈

欢迎提交 Issue 或 Pull Request。在提交代码前，请确保已通过 `dart analyze` 静态检查。

- **项目维护者**: [lightning-xf](https://github.com/lightning-xf)
- **主页**: [Lightning Proxy Github](https://github.com/lightning-xf/lightning-proxy)
