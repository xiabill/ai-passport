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
| Settings | Power mode, device prefix, output device, hotkeys, closed-loop retap, Typeless poll, login item |
| Logs | Filter, search, copy, open file, clear |
| Debug | Key taps, simulated device events, 440 Hz tone, mic capture test, reconnect, UUID copy, self-check |

## Build

```bash
cd tools/mac-bridge
./build.sh
open /Applications/FoloVibeBridge.app
```

`./build.sh` runs `swift run FoloVibeCoreTests`, packages the app, and installs it to `/Applications/FoloVibeBridge.app` by default. Full Xcode is not required; a Swift 5.9+ toolchain and Apple Command Line Tools are enough. The status and settings pages include a guided setup flow with permission/setup checks and a “Check again” action after returning from System Settings. Grant Bluetooth and Accessibility/Input Monitoring. Set Typeless to the Typeless key (default Fn), Doubao to the Doubao key (default Right Option in toggle mode), and both microphones to `BlackHole 2ch`.

The status page includes audio-effect tests for the configured output, a Passport microphone record/playback round, and BLE packet/loss checks. Every mapping in Settings supports both a picker and direct key capture. If BlackHole is missing, the setup guide can open its official installation page and macOS Sound settings.

Logs: `~/Library/Logs/folovibe-bridge.log`

Power modes: Standard keeps the device easy to reconnect and enters deep sleep after 15 minutes idle. Eco dims the display to 8% after 10 seconds, turns the backlight off after 1 minute, pauses BLE advertising after 60 seconds while disconnected, and enters deep sleep after 5 minutes. Any ordinary function key resumes advertising and wakes the device in Eco mode.

## Protocol

- Center single/double/long presses start Typeless Dictate/Translation/Ask anything; UP controls Doubao and DOWN sends Return.
- Device name: `FoloVibe-XXXX`
- Service `F0100001-0000-4A6B-9E10-464F4C4F5631`
- Audio notify `...0002`: 166-byte ADPCM frames or a 6-byte end-of-stream marker
- Event notify `...0003`: `1` Typeless Dictate start, `2` Typeless stop, `3` Return, `4` legacy cancel, `5` Doubao start, `6` Doubao stop, `7` Doubao stop and Return, `8` Typeless Translation start, `9` Typeless Ask anything start
- Control write `...0004`: Typeless state `0` idle, `1` recording, `2` processing, `3` not running
