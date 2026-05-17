# Lightning Proxy (Android)

一款基于 Flutter 和 Xray 内核的高性能、现代化 Android VPN 客户端。

[![License](https://img.shields.io/badge/license-AGPL--3.0-orange.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-v3.11+-blue.svg)](https://flutter.dev)
[![Xray](https://img.shields.io/badge/Xray-Core-orange.svg)](https://github.com/XTLS/Xray-core)

## ✨ 特性

- **现代化 UI**：采用全新的设计语言，支持深色模式，毛玻璃特效，交互流畅。
- **高性能内核**：集成最新版 Xray-core，支持 VMess, VLESS, Trojan, Shadowsocks, Hysteria2, TUIC 等多种主流协议。
- **智能分流**：内置成熟规则方案，支持 FakeDNS、自动化路由优先级管理，确保国内外网页秒开。
- **高级 DNS 设置**：支持自定义远程/国内 DNS、IPv6 优化以及 Hosts 映射。
- **应用分流**：支持按应用过滤，灵活控制哪些应用走代理。
- **多架构支持**：适配 arm64-v8a, armeabi-v7a, x86_64 等主流 Android 设备。

## 🚀 快速开始

### 编译环境
- Flutter SDK (推荐 3.11.4 或更高版本)
- Android SDK & NDK (用于编译 Go 核心)
- Go 环境 (用于通过 gomobile 编译 `go_core`)

### 获取代码
```bash
git clone https://github.com/lightning-xf/lightning-proxy.git
cd lightning-proxy
```

### 编译 Go 核心 (可选)
如果您修改了 `go_core` 目录下的代码，需要重新生成 `.aar` 文件：
```bash
./build_android_core.sh
```

### 运行项目
```bash
flutter pub get
flutter run --release
```

## 🛠️ 技术架构

- **前端**：Flutter + Riverpod (状态管理)
- **后端核心**：Xray-core (通过 Go JNI 桥接)
- **原生层**：Kotlin (Android VpnService 实现)
- **配置生成**：自动化 Xray JSON 配置引擎，支持动态规则热重载

## 📄 开源协议

本项目采用 [AGPL-3.0 License](LICENSE) 协议开源。

## 🤝 贡献与反馈

欢迎提交 Issue 或 Pull Request 来完善本项目！

- **项目主页**: [https://github.com/lightning-xf/lightning-proxy](https://github.com/lightning-xf/lightning-proxy)
