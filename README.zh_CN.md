<p align="right">
  <strong>简体中文</strong> · <a href="README.md">English</a>
</p>

# AI Passport — Vibe Typeless

这是 [FoloToy/ai-passport](https://github.com/FoloToy/ai-passport) 的公开 fork，把 AI Passport 做成给 vibe coding 使用的 Typeless 一键说话麦克风。当前维护版本位于本仓库的 [`main`](https://github.com/xiabill/ai-passport/tree/main) 分支。

- 固件：ESP32-C3 BLE IMA-ADPCM 麦克风、Typeless 三手势/豆包双输入法按键、回车键、VIBE 状态页、省电和按键提示音
- 蓝牙链路：自定义 GATT 服务，传输音频、设备事件和 Typeless 状态
- Mac 桥：[`tools/mac-bridge/`](tools/mac-bridge/) 接收并解码音频，写入 `BlackHole 2ch`，发送配置好的 Typeless / 豆包快捷键
- 完整安装、构建、刷机、BLE 协议和排错教程：[docs/development/vibe-typeless.zh_CN.md](docs/development/vibe-typeless.zh_CN.md)
- English guide：[docs/development/vibe-typeless.md](docs/development/vibe-typeless.md)
- 可直接下载的程序和固件：[GitHub Releases](https://github.com/xiabill/ai-passport/releases/latest)

## 普通用户快速开始

从[最新 GitHub Release](https://github.com/xiabill/ai-passport/releases/latest) 下载 macOS 版 `FoloVibeBridge`，解压后把 `FoloVibeBridge.app` 拖到 `/Applications`。同一个 Release 里还包含匹配版本的 `FoloToy-AI-Passport-full.bin` 固件。

首次启动时按应用内检查逐项授权：蓝牙、辅助功能/输入监控，安装 BlackHole 2ch，并让 Typeless、豆包和 Bridge 使用一致的快捷键。详细的[用户教程](docs/releases/v0.2.2-vibe-typeless.zh_CN.md)包含安装、授权、按键映射、刷机和排错说明。

## 开发者快速开始

```bash
git clone https://github.com/xiabill/ai-passport.git
cd ai-passport

# macOS 伴侣
cd tools/mac-bridge
./build.sh
# build.sh 默认会安装到 /Applications
open /Applications/FoloVibeBridge.app
```

固件需要 ESP-IDF 5.5.3 和 ESP32-C3 设备。给已有设备刷机前请阅读[完整教程](docs/development/vibe-typeless.zh_CN.md)：合并固件不能覆盖受保护的 `cardid` 分区。

本 fork 的维护版本发布在 `main`；本地开发请从 `main` 创建 feature 分支，完成测试后再合并回 `main`。
