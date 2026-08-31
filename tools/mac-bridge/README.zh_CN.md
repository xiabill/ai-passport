<p align="right">
  <strong>简体中文</strong> · <a href="README.md">English</a>
</p>

# FoloVibe Bridge

AI Passport vibe-typeless 固件的 macOS 伴侣。这是完整应用：总览、设置、实时日志、调试测试台，外加菜单栏。

通过 BLE 接收 IMA-ADPCM 麦克风帧，播放到 `BlackHole 2ch`，并按设置里的 Typeless / 豆包 / 回车键，让两个输入法把文字打进当前焦点应用。

完整的固件、BLE、Typeless、刷机、权限和故障排查教程见 [Vibe 教程](../../docs/development/vibe-typeless.zh_CN.md)。

## 窗口

| 页 | 内容 |
| --- | --- |
| 状态 | 设备、音频、Typeless、权限、电平条、问题清单 |
| 设置 | 设备名前缀、输出设备、热键、闭环补按、Typeless 轮询、开机启动 |
| 日志 | 分类过滤、搜索、复制、打开文件、清空 |
| 调试 | 点按热键、模拟设备事件、440Hz 测试音、设备麦录音测试、重连、复制 UUID、自检 |

## 构建

```bash
cd tools/mac-bridge
./build.sh
open FoloVibeBridge.app
```

`./build.sh` 会先跑 `swift run FoloVibeCoreTests` 再打包。不需要完整 Xcode，Swift 5.9+ 工具链和 Apple Command Line Tools 即可。给 FoloVibe Bridge 打开蓝牙、辅助功能和输入监控。Typeless 默认 Fn，豆包默认右⌥（免按模式），两边的麦克风都选 `BlackHole 2ch`。

日志：`~/Library/Logs/folovibe-bridge.log`

## 协议

- 设备名：`FoloVibe-XXXX`
- 服务 `F0100001-0000-4A6B-9E10-464F4C4F5631`
- 音频 notify `...0002`：166 字节 ADPCM 帧，或 6 字节结束标记
- 事件 notify `...0003`：`1` Typeless 开始，`2` Typeless 停止，`3` 回车，`4` 旧取消，`5` 豆包开始，`6` 豆包停止，`7` 豆包停止并回车
- 控制 write `...0004`：Typeless 状态 `0` 空闲，`1` 录音，`2` 转写，`3` 未运行
