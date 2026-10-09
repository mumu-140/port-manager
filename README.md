# Port Manager

<p align="center">
  <img src=".github/assets/icon.svg" alt="Port Manager 图标" width="128" height="128">
</p>

<p align="center">
  <a href="https://github.com/mumu-140/port-manager/actions/workflows/ci.yml"><img src="https://github.com/mumu-140/port-manager/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-15%2B-brightgreen" alt="macOS 15+"></a>
  <a href="https://www.microsoft.com/windows"><img src="https://img.shields.io/badge/Windows-10%2B-0078D6" alt="Windows 10+"></a>
</p>

<p align="center">
  <a href="README_EN.md">English</a> | <b>简体中文</b>
</p>

Port Manager 是一个跨平台的端口管理工具，帮你看清本机哪些端口被占用、被谁占用，并提供终止进程、端口转发、隧道管理等能力。macOS、Windows、Linux 三端均为原生应用。

> 本仓库由 [productdevbook/port-killer](https://github.com/productdevbook/port-killer) fork 而来，现独立维护，MIT 协议，详见 [FORK_NOTICE.md](FORK_NOTICE.md)。为兼容起见，桌面端可执行文件仍保留 **PortKiller** 名称。

## 功能

### 端口与进程管理

- 自动发现本机监听中的 TCP 端口及其归属进程
- 优雅终止、强制结束、深度清理三种结束方式
- 按端口号 / 进程名搜索与过滤
- 收藏端口、关注端口（状态变化时通知）
- 端口备注与标签
- 进程类型归类
- 自动刷新与自动结束规则

### Kubernetes 端口转发

- 创建、管理 `kubectl port-forward` 连接
- 浏览 context、namespace、service 与端口
- 自动重连、连接日志、状态监控

### Cloudflare Tunnel

- 查看 quick tunnel 与 named tunnel
- 查看 ingress 配置与运行状态
- 在应用内启停本地隧道
- 一键打开或复制公网 URL

### 服务预设（一键起服务）

内置 5 种常用服务预设，填几个参数就能起一个服务，不用手写命令：

- **静态文件分享** —— `python3 -m http.server`，只读，绑定回环地址
- **SSH 本地转发 / SOCKS5 代理** —— 复用本机 SSH agent 与配置，自动保活
- **Dufs 文件分享** —— 只读 / 上传 / 读写三种模式（需本机已安装 dufs）
- **Jupyter Lab** —— 绑定回环地址，端口被占时直接报错而不是静默换端口

安全设计：所有预设默认只绑 `127.0.0.1`；不收集任何密码、token；依赖检测只读 PATH，从不自动安装东西。

### 中文界面

- macOS 端：English / 简体中文 / 跟随系统
- Windows 端：English / 简体中文 / 跟随系统，浅色 / 深色主题可切

## 截图

### macOS

<p align="center">
  <img src=".github/assets/macos.png" alt="Port Manager on macOS" width="800">
</p>

### Windows

<p align="center">
  <img src=".github/assets/windows.jpeg" alt="Port Manager on Windows" width="800">
</p>

## 安装

### macOS

不使用上游的 Homebrew tap。去 [Actions](https://github.com/mumu-140/port-manager/actions/workflows/ci.yml) 下载最新 CI 构建，或从源码编译：

```bash
git clone https://github.com/mumu-140/port-manager.git
cd port-manager/platforms/macos
./scripts/build-app.sh
open .build/apple/Products/Release/PortKiller.app
```

> CI 构建未经 Apple 公证，首次启动请在 Finder 里右键 → 打开。

### Windows

从源码运行：

```powershell
git clone https://github.com/mumu-140/port-manager.git
cd port-manager\platforms\windows\PortKiller
dotnet run
```

打 tag 的 release 会附带 x64 / ARM64 的 ZIP 包。

### Linux

直接运行：

```bash
git clone https://github.com/mumu-140/port-manager.git
cd port-manager
./platforms/linux/port-killer.py
```

或使用自带安装脚本：

```bash
./platforms/linux/install.sh
```

## 仓库结构

```text
platforms/
├── macos/                  Swift / SwiftUI 原生应用
├── windows/                .NET 9 / WPF 原生应用
└── linux/                  Python / GTK 托盘应用

portkiller-core/            Rust 核心（Linux 侧使用）
.github/workflows/          CI、PR 构建、独立发布流程
appcast.xml                 本仓库预留的 Sparkle 更新源
sponsors.json               本仓库的赞助者数据
```

## 发布与更新

- 推送 `v*` tag 会在本仓库创建 GitHub Release 并附上各平台构建产物
- 自动更新目前处于禁用状态，直到本仓库配好自己的签名与更新源（避免静默切回上游渠道）

详见 [RELEASES.md](RELEASES.md)。

## 参与贡献

欢迎提 issue、修 bug、补翻译、测各平台构建。提 PR 前请先看 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

MIT，详见 [LICENSE](LICENSE)。
