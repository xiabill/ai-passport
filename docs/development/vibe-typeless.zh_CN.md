<p align="right">
  <strong>简体中文</strong> · <a href="vibe-typeless.md">English</a>
</p>

# Vibe Typeless 伴侣

这个分支把 FoloToy AI Passport 做成 Typeless 的无线一键说话麦克风。公开实现由两部分组成：

- ESP32-C3 固件（`main/`）：采集设备麦克风，把 16 kHz PCM 编成 IMA-ADPCM，通过 BLE 发送音频，绘制 VIBE 屏幕并上报按键事件。
- macOS 伴侣（`tools/mac-bridge/`）：连接设备、解码音频、把 PCM 写入 `BlackHole 2ch`，监控 Typeless，并发送配置好的 Typeless / 豆包 / 回车按键。

仓库是公开的，当前实现位于 [`feature/vibe-typeless`](https://github.com/xiabill/ai-passport/tree/feature/vibe-typeless)。上游 `main` 保持干净的硬件基线。

## 工作链路

```text
Passport 麦克风
        │  16 kHz PCM → IMA-ADPCM
        ▼
ESP32-C3 BLE notify ───────────────┐
        │ 设备事件                  │
        ▼                           ▼
  VIBE 屏幕                    FoloVibe Bridge
                                      │ 解码 PCM
                                      ▼
                               BlackHole 2ch
                                      │
                                      ▼
                          ┌───────────────┐
                          │ Typeless      │
                          │ 豆包输入法     │
                          └───────────────┘

Passport 确定/下/上 ──BLE event──> Bridge ──CGEvent──> Typeless
Typeless 状态 ───────BLE write───> Passport
```

## 准备工作

### 硬件

- FoloToy AI Passport：ESP32-C3、240×320 竖屏、麦克风、扬声器、三键 ADC 电阻梯。
- 能枚举 ESP32-C3 USB Serial/JTAG 的 USB 连接。
- 进行无线测试时请保证电池有电。

### macOS

- macOS 13 或更新版本，用于 Swift Package。
- Swift 5.9+ 工具链和 Apple Command Line Tools。构建 macOS 伴侣只需要 `swift build`，不要求安装完整 Xcode。
- 打开蓝牙。
- 安装 Typeless 和豆包输入法。Typeless 使用自己的说话键；豆包建议打开“免按模式”，并把快捷键设为右⌥。
- 安装 BlackHole 2ch，并把它作为 Typeless 的麦克风输入。

### 固件工具链

- ESP-IDF 5.5.3 和 ESP32-C3 工具链。
- ESP-IDF 安装的 Python 依赖。

固件命令前先激活准确版本：

```bash
source <ESP-IDF-v5.5.3-路径>/export.sh
idf.py --version
```

## 构建 macOS Bridge

在仓库根目录运行：

```bash
cd tools/mac-bridge
./build.sh
open FoloVibeBridge.app
```

`build.sh` 会先运行核心测试，再构建 release 可执行文件并打包本地 `FoloVibeBridge.app`。应用不把机器相关的二进制提交到仓库，其他人下载源码后可以自行构建。

首次打开后：

1. macOS 询问时允许蓝牙权限。
2. 打开“系统设置 → 隐私与安全性 → 辅助功能”，启用 `FoloVibe Bridge`。
3. 在 Bridge 的“设置”页选择设备名前缀 `FoloVibe` 和输出设备 `BlackHole 2ch`。
4. 在 Bridge 设置中分别选择 Typeless 和豆包的按键。Typeless 默认 `Fn`；豆包默认 `Right Option`（右⌥）。如果你在对应输入法中改过快捷键，两边选择相同按键。
5. 回车键默认 `Return`，它对应设备的下键；旧的 `Escape` 取消键仍保留在配置里用于兼容，但不再占用设备上键。
6. 在 Typeless 和豆包输入法中选择 `BlackHole 2ch` 作为麦克风输入（按当前输入法的设置要求启用）。

Bridge 会把设置保存到 macOS 用户默认值。日志位置：

```text
~/Library/Logs/folovibe-bridge.log
```

“设置”页还可以打开开机启动、自动重连、闭环补按和 Typeless 状态轮询。“调试”页提供按键发送、模拟设备事件、测试音、重连、复制 UUID 和麦克风测试。

## 构建并刷写固件

先运行仓库检查：

```bash
./tools/validate.sh --static
./tools/validate.sh --firmware
```

固件门禁会用全新的临时目录编译，验证适合小程序安装的合并镜像，并把通过的文件写到：

```text
build/FoloToy-AI-Passport-full.bin
```

开发迭代也可以使用增量命令：

```bash
idf.py set-target esp32c3
idf.py build
idf.py merge-bin -o build/FoloToy-AI-Passport-full.bin
```

刷机前先找当前 USB 端口。设备重启后，macOS 可能会改变端口末尾编号：

```bash
ls /dev/cu.usbmodem* 2>/dev/null
```

已有身份的设备只能使用通过 `--firmware` 校验的镜像，并从 `0x0` 写入：

```bash
python -m esptool --chip esp32c3 \
  -p /dev/cu.usbmodemXXXX -b 460800 \
  write_flash 0x0 build/FoloToy-AI-Passport-full.bin
```

不要对已有设备执行 `erase-flash`。镜像必须在受保护的 `cardid` 分区 `0x356000` 之前结束；永久 Recovery 分区位于 `0x700000`。仓库校验器会检查这些边界、3 MB 应用上限、分区表 MD5，以及按住上键 5 秒进入 Recovery 的 bootloader hook。

## 设备行为

| 按键 | 空闲 | 对应输入法录音中 | 其他输入法录音中 |
| --- | --- | --- | --- |
| 确定 OK | 启动 Typeless | 停止 Typeless | 忽略，避免抢占豆包 |
| 下 DOWN | 发送 Return | 停止当前输入，完成后发送 Return | 停止当前输入，完成后发送 Return |
| 上 UP | 启动豆包 | 停止豆包 | 忽略，避免抢占 Typeless |

峰值低于阈值约 30 秒也会自动停止。短提示音由音频 worker 生成，因此按键回调本身不会执行阻塞的播放工作。

两个输入法共享同一个设备麦克风和 BLE 音频流，但不会并行录音。豆包停止后 Bridge 会短暂等待再发送 Return，给识别结果落到当前输入框留出时间；Typeless 则继续读取本地状态，在转写完成后再发送。

VIBE 页面显示 BLE/Typeless 状态、电量、音频状态、绿/黄/红声波和三个按键提示。声波是活动历史，不是经过校准的声压计。

省电行为：

- 使用中背光 100%，空闲 18 秒降到 20%，60 秒后熄屏。
- 屏幕熄灭后的第一次按键只负责唤醒。
- BLE 空闲使用 30–50 ms 连接间隔和 slave latency，说话时切到 7.5–15 ms、latency 0。

## BLE 协议契约

设备广播名为 `FoloVibe-XXXX`，提供以下 128 位服务：

```text
Service:       F0100001-0000-4A6B-9E10-464F4C4F5631
Audio notify:  F0100002-0000-4A6B-9E10-464F4C4F5631
Event notify:  F0100003-0000-4A6B-9E10-464F4C4F5631
Control write: F0100004-0000-4A6B-9E10-464F4C4F5631
```

| 特征 | 方向 | 数据 |
| --- | --- | --- |
| Audio | 设备 → Mac | 166 字节 IMA-ADPCM 帧，或 6 字节 EOS 结束标记 |
| Event | 设备 → Mac | `1` Typeless 开始，`2` Typeless 停止，`3` Return，`4` 旧取消/Escape，`5` 豆包开始，`6` 豆包停止，`7` 豆包停止并发送 Return |
| Control | Mac → 设备 | Typeless 状态：`0` 空闲，`1` 录音，`2` 转写，`3` 未运行 |

音频帧包含序号、预测值、step index 和 ADPCM 数据。Bridge 会对小范围丢帧插入静音，并在状态页显示丢包统计。

## 验证矩阵

自动化结果和实体设备结果必须分开记录：

```text
Build:        idf.py build / validate.sh --firmware
Host tests:   validate.sh --static 和 FoloVibeCoreTests
Device tests: 实体板、BLE、屏幕、按键、扬声器、麦克风、Typeless
```

推荐真机清单：

- [ ] 设备广播 `FoloVibe-*`，Bridge 能连接。
- [ ] Bridge 显示已订阅音频，Typeless 选择 `BlackHole 2ch`。
- [ ] 按确定开始/停止 Typeless 听写，文字进入当前焦点输入框。
- [ ] 按上键开始/停止豆包输入法，文字进入当前焦点输入框。
- [ ] 两个输入法录音互斥，录音中按另一个输入法键不会抢占音频。
- [ ] 说话时按下键：停止当前输入法并发送 Return。
- [ ] 按键提示音可听见，且不影响麦克风采集。
- [ ] 声波低音量显示绿色，中等显示黄色，高峰显示红色，停止后渐隐。
- [ ] USB Serial/JTAG 重启后可以重新枚举，设备身份仍然保留。

## 故障排查

### Bridge 找不到设备

确认蓝牙已打开、设备正在广播 `FoloVibe-*`，并且设置里的前缀是 `FoloVibe`。如果固件没有运行，按一下复位或重新插拔 USB。优先查看“日志”和“调试”页，不要一开始就删除设置。

### Typeless 没有收到声音

确认 Typeless 的麦克风是 `BlackHole 2ch`，macOS 已授予音频权限，Bridge 状态页显示已订阅音频；同时 Bridge 必须拥有辅助功能权限才能发送按键。

### Fn 或 F19 没有触发 Typeless

Bridge 默认是 macOS 的 Fn/Globe 修饰键，不是 F19。请让 Typeless 和 Bridge 都选 `Fn`，或者两边都选 `F19`。Bridge 支持 F13 到 F20，并会保存选择。

### 豆包无法启动或停止

在豆包输入法设置中打开“免按模式”，并把快捷键设置为和 Bridge 的“豆包”选项一致。默认是 `Right Option`（右⌥）；如果你的版本使用 Fn，就两边都选择 `Fn`。如果 macOS 拦截修饰键事件，请给 Bridge 打开辅助功能和输入监控权限。

### USB 端口消失

拔掉并重新插入设备，再次查看 `/dev/cu.usbmodem*`。不要假设重启前的编号仍然有效。如果设备进入 Recovery，松开上键后再重新连接 USB 端口。

### 固件校验器拒绝镜像

不要绕过校验器。确认 ESP-IDF 是 5.5.3、构建使用了 `sdkconfig.defaults`、刷的是合并完整镜像，并检查是否意外修改了分区表或受保护区域。

## 贡献代码

从 `main` 创建 feature 分支；硬件常量放在 BSP，UI/协议逻辑放在 `main`；提交前运行 `./tools/validate.sh`；实体验收单独记录。不要提交凭证、设备二维码密钥、私钥、真实日志或个人数据。详见 [CONTRIBUTING](../../.github/CONTRIBUTING.zh_CN.md) 和 [AGENTS.zh_CN.md](../../AGENTS.zh_CN.md)。

## 许可证

本 fork 保留仓库的 MIT License，见 [LICENSE](../../LICENSE)。
