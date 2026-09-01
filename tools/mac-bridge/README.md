<p align="right">
  <a href="README.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# FoloVibe Bridge

macOS companion for the AI Passport vibe-typeless firmware. It is a full app: status dashboard, settings, live logs, and a debug/test panel, plus a menu-bar extra.

It receives IMA-ADPCM frames over BLE, plays them into `BlackHole 2ch`, and taps the configured Typeless modes, Doubao, and Return keys so the input methods can dictate into the focused app.

For the end-to-end firmware, BLE, Typeless, flashing, permissions, and troubleshooting tutorial, see [the Vibe guide](../../docs/development/vibe-typeless.md).

## Windows

| Tab | Contents |
| --- | --- |
| Status | Device, audio, Typeless, permissions, level meter, problem list |
| Settings | Device prefix, output device, hotkeys, closed-loop retap, Typeless poll, login item |
| Logs | Filter, search, copy, open file, clear |
| Debug | Key taps, simulated device events, 440 Hz tone, mic capture test, reconnect, UUID copy, self-check |

## Build

```bash
cd tools/mac-bridge
./build.sh
open FoloVibeBridge.app
```

`./build.sh` runs `swift run FoloVibeCoreTests` then packages the app. Full Xcode is not required; a Swift 5.9+ toolchain and Apple Command Line Tools are enough. Grant Bluetooth and Accessibility/Input Monitoring. Set Typeless to the Typeless key (default Fn), Doubao to the Doubao key (default Right Option in toggle mode), and both microphones to `BlackHole 2ch`.

Logs: `~/Library/Logs/folovibe-bridge.log`

## Protocol

- Center single/double/long presses start Typeless Dictate/Translation/Ask anything; UP controls Doubao and DOWN sends Return.
- Device name: `FoloVibe-XXXX`
- Service `F0100001-0000-4A6B-9E10-464F4C4F5631`
- Audio notify `...0002`: 166-byte ADPCM frames or a 6-byte end-of-stream marker
- Event notify `...0003`: `1` Typeless Dictate start, `2` Typeless stop, `3` Return, `4` legacy cancel, `5` Doubao start, `6` Doubao stop, `7` Doubao stop and Return, `8` Typeless Translation start, `9` Typeless Ask anything start
- Control write `...0004`: Typeless state `0` idle, `1` recording, `2` processing, `3` not running
