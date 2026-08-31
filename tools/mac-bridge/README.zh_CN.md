<p align="right">
  <strong>简体中文</strong> · <a href="README.md">English</a>
</p>

# FoloVibe Bridge

AI Passport vibe-typeless 固件的 macOS 菜单栏伴侣。它通过 BLE 接收 IMA-ADPCM 麦克风帧，播放到 `BlackHole 2ch`，并轻按 `F19` / 回车 / Esc，让 Typeless 把文字打进当前焦点应用。

## 构建与运行

```bash
cd tools/mac-bridge
./build.sh
open FoloVibeBridge.app
```

给 `FoloVibe Bridge` 打开蓝牙和辅助功能权限。Typeless 听写快捷键设为 `F19`，麦克风选 `BlackHole 2ch`。

日志：`~/Library/Logs/folovibe-bridge.log`

## 协议

- 设备名：`FoloVibe-XXXX`
- 服务 `F0100001-0000-4A6B-9E10-464F4C4F5631`
- 音频 notify `...0002`：166 字节 ADPCM 帧，或 6 字节结束标记
- 事件 notify `...0003`：`1` 开始，`2` 停止，`3` 回车，`4` 取消
- 控制 write `...0004`：Typeless 状态 `0` 空闲，`1` 录音，`2` 转写，`3` 未运行
