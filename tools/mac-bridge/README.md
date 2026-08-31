<p align="right">
  <a href="README.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# FoloVibe Bridge

macOS menu-bar companion for the AI Passport vibe-typeless firmware. It receives IMA-ADPCM microphone frames over BLE, plays them into `BlackHole 2ch`, and taps `F19` / Return / Escape so Typeless can dictate into the focused app.

## Build and run

```bash
cd tools/mac-bridge
./build.sh
open FoloVibeBridge.app
```

Grant Bluetooth and Accessibility to `FoloVibe Bridge`. Set Typeless dictation to `F19` and the Typeless microphone to `BlackHole 2ch`.

Logs: `~/Library/Logs/folovibe-bridge.log`

## Protocol

- Device name: `FoloVibe-XXXX`
- Service `F0100001-0000-4A6B-9E10-464F4C4F5631`
- Audio notify `...0002`: 166-byte ADPCM frames or a 6-byte end-of-stream marker
- Event notify `...0003`: `1` start, `2` stop, `3` enter, `4` cancel
- Control write `...0004`: Typeless state `0` idle, `1` recording, `2` processing, `3` not running
