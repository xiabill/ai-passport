<p align="right">
  <strong>简体中文</strong> · <a href="vibe-typeless.md">English</a>
</p>

# Vibe Typeless 伴侣

`feature/vibe-typeless` 上的固件把 AI Passport 做成 Typeless 的一键说话麦克风。`tools/mac-bridge/` 里的 Mac 桥把解码后的 PCM 写入 `BlackHole 2ch`，并轻按 Typeless 的 `F19`。

这是专用应用：开机不再进入硬件 demo 菜单，直接打开 VIBE 页。`components/bsp` 未改。

## 按键

| 键 | 空闲 | 录音中 | 停止后 |
| --- | --- | --- | --- |
| 确定 | 开始说话 | 停止 | 忽略 |
| 下 | 回车 | 停止，等 Typeless 空闲后再回车 | 排队回车 |
| 上 | Esc | 停止 + Esc | Esc，回到空闲 |

峰值低于阈值持续 30 秒也会自动停录。

## 真机验收

不要把 host tests 通过当成硬件验证。请在真机上逐项记 PASS / FAIL / NOT RUN：

- [ ] `./tools/validate.sh --static` 通过。
- [ ] ESP-IDF 5.5.3 针对 ESP32-C3 的 `idf.py build` 成功。
- [ ] 设备广播 `FoloVibe-*`，Mac 桥能连上。
- [ ] 按确定启动 Typeless；对着 Passport 麦说话，文字出现在当前输入框。
- [ ] 再按确定停止 Typeless，屏幕离开 REC。
- [ ] 说话时按下键：停止、等 Typeless，然后发回车。
- [ ] 上键取消（Esc），不会发送。
- [ ] USB Serial/JTAG 仍能枚举，方便刷机。

## 未插板时未验证

实现时开发用 Mac 没有枚举到 USB，因此刷写、麦克风音质、BLE 吞吐和 MTU 协商都还没在真机上做过。
