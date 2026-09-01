<p align="right">
  <strong>简体中文</strong> · <a href="README.md">English</a>
</p>

# AI Passport — Vibe Typeless

这是 [FoloToy/ai-passport](https://github.com/FoloToy/ai-passport) 的公开 fork，把 AI Passport 做成给 vibe coding 使用的 Typeless 一键说话麦克风。当前实现位于 [`feature/vibe-typeless`](https://github.com/xiabill/ai-passport/tree/feature/vibe-typeless)。

- 固件：ESP32-C3 BLE IMA-ADPCM 麦克风、Typeless 三手势/豆包双输入法按键、回车键、VIBE 状态页、省电和按键提示音
- 蓝牙链路：自定义 GATT 服务，传输音频、设备事件和 Typeless 状态
- Mac 桥：[`tools/mac-bridge/`](tools/mac-bridge/) 接收并解码音频，写入 `BlackHole 2ch`，发送配置好的 Typeless / 豆包快捷键
- 完整安装、构建、刷机、BLE 协议和排错教程：[docs/development/vibe-typeless.zh_CN.md](docs/development/vibe-typeless.zh_CN.md)
- English guide：[docs/development/vibe-typeless.md](docs/development/vibe-typeless.md)

## 快速开始

```bash
git clone --branch feature/vibe-typeless https://github.com/xiabill/ai-passport.git
cd ai-passport

# macOS 伴侣
cd tools/mac-bridge
./build.sh
open FoloVibeBridge.app
```

固件需要 ESP-IDF 5.5.3 和 ESP32-C3 设备。给已有设备刷机前请阅读[完整教程](docs/development/vibe-typeless.zh_CN.md)：合并固件不能覆盖受保护的 `cardid` 分区。

上游 `main` 保持干净基线，不要在 `main` 上堆功能。
