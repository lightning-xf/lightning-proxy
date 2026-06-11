# ⚡ Lightning Proxy

<p align="center">
  <img src="https://img.shields.io/badge/license-AGPL--3.0-orange.svg" alt="License">
  <img src="https://img.shields.io/badge/Flutter-v3.22+-blue.svg" alt="Flutter">
  <img src="https://img.shields.io/badge/Xray-Core-orange.svg" alt="Xray">
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20Windows-blue.svg" alt="Platform">
</p>

Lightning Proxy 是一款高性能、跨平台的代理客户端，专为 Android 和 Windows 平台打造。基于 Flutter 现代化 UI 与 Xray 内核的强大协议支持，为用户提供快速、稳定且轻量的网络代理体验。

---

## 📱 平台分支

本项目采用多分支架构，源代码位于不同平台分支：

| 分支 | 平台 | 说明 |
|------|------|------|
| **Android** | Android | Android 平台客户端 |
| **Windows** | Windows | Windows 平台客户端 |
| **master** | - | 项目展示分支（当前分支） |

---

## ✨ 核心特性

### 1. 多协议支持
内置 Xray 核心，全面支持主流加密协议：
- **VLESS (Reality)**
- **VMess**
- **Trojan**
- **Shadowsocks**
- **Hysteria2**
- **TUIC**

### 2. 高性能优化
- **Android 平台**：深度功耗优化，后台运行时资源占用极低
- **Windows 平台**：极致深睡眠模式，窗口隐藏时 GPU 占用率 0%

### 3. 智能路由
- 内置绕过中国大陆规则
- 支持域名/IP 分流
- 自定义规则集订阅

---

## 📋 系统要求

### Android
- **系统版本**：Android 7.0 (API 24) 及以上
- **架构**：arm64-v8a, armeabi-v7a, x86_64

### Windows
- **系统版本**：Windows 11 / Windows 10 (1607+)
- **架构**：仅支持 x64
- **权限**：需要管理员权限

---

## 📦 下载与安装

请访问 [Releases](RELEASES.md) 页面下载最新版本。

---

## 📸 截图

查看 [SCREENSHOTS.md](SCREENSHOTS.md) 了解应用界面。

---

## 🛠️ 技术架构

### 核心技术栈
- **UI 框架**：[Flutter](https://flutter.dev)
- **状态管理**：[Riverpod](https://riverpod.dev)
- **底层核心**：[Xray-core](https://github.com/XTLS/Xray-core)

### 项目结构
```
lightning/
├── android/    # Android 平台源代码
├── windows/    # Windows 平台源代码
└── README.md   # 项目说明（本文件）
```

---

## 📄 开源协议

本项目采用 [AGPL-3.0 License](LICENSE) 协议开源。

---

## 🤝 贡献与反馈

欢迎提交 Issue 或 Pull Request。

- **项目维护者**：[lightning-xf](https://github.com/lightning-xf)
- **项目主页**：[Lightning Proxy GitHub](https://github.com/lightning-xf/lightning-proxy)
