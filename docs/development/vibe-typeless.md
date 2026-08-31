<p align="right">
  <a href="vibe-typeless.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Vibe Typeless companion

This branch turns the FoloToy AI Passport into a wireless push-to-talk microphone for Typeless. The public implementation has two cooperating parts:

- ESP32-C3 firmware in `main/`: captures the board microphone, encodes 16 kHz PCM as IMA-ADPCM, sends audio over BLE, draws the VIBE screen, and reports button events.
- macOS companion in `tools/mac-bridge/`: connects to the board, decodes audio, writes PCM to `BlackHole 2ch`, watches Typeless, and posts the configured Typeless / Doubao / Return keys.

The repository is public and the active branch is [`feature/vibe-typeless`](https://github.com/xiabill/ai-passport/tree/feature/vibe-typeless). The upstream `main` branch remains the clean hardware baseline.

## How the pieces fit together

```text
Passport microphone
        │  16 kHz PCM → IMA-ADPCM
        ▼
ESP32-C3 BLE notify ───────────────┐
        │ device events             │
        ▼                           ▼
  VIBE screen                 FoloVibe Bridge
                                      │ decode PCM
                                      ▼
                               BlackHole 2ch
                                      │
                                      ▼
                          ┌───────────────┐
                          │ Typeless      │
                          │ Doubao IME    │
                          └───────────────┘

Passport OK / DOWN / UP ──BLE event──> Bridge ──CGEvent──> Typeless
Typeless state ───────────BLE write───> Passport
```

## Requirements

### Hardware

- FoloToy AI Passport with ESP32-C3, 240×320 portrait display, microphone, speaker, and the three-button ADC ladder.
- USB connection that exposes the ESP32-C3 USB Serial/JTAG port.
- A charged battery for wireless testing.

### macOS

- macOS 13 or newer for the Swift package.
- A Swift 5.9+ toolchain and Apple Command Line Tools. Full Xcode is not required to build the macOS companion with `swift build`.
- Bluetooth enabled.
- Typeless and Doubao IME installed. Configure each to use the corresponding Bridge key; Doubao should use its toggle mode.
- BlackHole 2ch installed as the virtual microphone input for Typeless.

### Firmware toolchain

- ESP-IDF 5.5.3 with the ESP32-C3 toolchain.
- Python dependencies installed by ESP-IDF.

Activate the exact ESP-IDF version before firmware commands:

```bash
source <ESP-IDF-v5.5.3-path>/export.sh
idf.py --version
```

## Build the macOS Bridge

From the repository root:

```bash
cd tools/mac-bridge
./build.sh
open FoloVibeBridge.app
```

`build.sh` first runs the core tests, then builds the release executable and packages a local `FoloVibeBridge.app`. The app is intentionally built locally rather than committed as a machine-specific binary.

On first launch:

1. Allow Bluetooth access if macOS asks.
2. In System Settings → Privacy & Security → Accessibility, enable `FoloVibe Bridge`.
3. In the Bridge Settings tab, select the device prefix `FoloVibe` and output device `BlackHole 2ch`.
4. Configure the Typeless and Doubao keys separately. Typeless defaults to `Fn`; Doubao defaults to `Right Option`, matching its toggle-mode setup. The Bridge supports Fn, modifier keys, and F13–F20.
5. Use `Return` for the device DOWN button. The old `Escape` cancel setting remains for compatibility but is no longer assigned to the device UP button.
6. Choose `BlackHole 2ch` as the microphone input in Typeless and Doubao as required by each app.

The Bridge stores settings in the macOS user defaults database. Logs are written to:

```text
~/Library/Logs/folovibe-bridge.log
```

The Settings tab can also enable launch at login, auto reconnect, closed-loop retapping, and Typeless state polling. The Debug tab provides key-tap, simulated event, tone, reconnect, UUID, and microphone checks.

## Build and flash the firmware

Run the repository checks first:

```bash
./tools/validate.sh --static
./tools/validate.sh --firmware
```

The firmware gate uses a clean temporary build, verifies the BLE-installable merged image, and writes the accepted artifact to:

```text
build/FoloToy-AI-Passport-full.bin
```

For iterative development, an incremental build is also available:

```bash
idf.py set-target esp32c3
idf.py build
idf.py merge-bin -o build/FoloToy-AI-Passport-full.bin
```

Before flashing, find the current USB port because macOS may change its suffix after a reset:

```bash
ls /dev/cu.usbmodem* 2>/dev/null
```

For an existing device, use only an image that passed `--firmware` and flash from offset `0x0`:

```bash
python -m esptool --chip esp32c3 \
  -p /dev/cu.usbmodemXXXX -b 460800 \
  write_flash 0x0 build/FoloToy-AI-Passport-full.bin
```

Do not run `erase-flash` on a device that already has its identity. The image must end before the protected `cardid` partition at `0x356000`; the permanent Recovery region is at `0x700000`. The repository verifier checks these boundaries and also checks the 3 MB application limit, partition-table MD5, and the five-second UP-key Recovery hook.

## Device behavior

| Key | Idle | Its input method is recording | The other input method is recording |
| --- | --- | --- | --- |
| OK | start Typeless | stop Typeless | ignored to prevent takeover |
| DOWN | send Return | stop current input and send Return | stop current input and send Return |
| UP | start Doubao | stop Doubao | ignored to prevent takeover |

Silence below the peak threshold for about 30 seconds also stops recording. A short button feedback beep is generated by the audio worker so the button callback remains lightweight.

The two input methods share one microphone and BLE audio stream, so they never record concurrently. After Doubao stops, the Bridge waits briefly before posting Return so the recognized text can land in the focused field. Typeless keeps its existing local-state wait before sending.

The VIBE page shows BLE/Typeless state, battery, audio status, a green/yellow/red waveform, and three button hints. The waveform is an activity history rather than a calibrated sound-level meter.

Power behavior:

- Backlight is 100% while in use, drops to 20% after 18 seconds idle, and turns off after 60 seconds.
- The first button press while the screen is dark only wakes the screen.
- BLE uses a slower 30–50 ms connection interval with slave latency while idle, and 7.5–15 ms with zero latency while talking.

## BLE contract

The board advertises as `FoloVibe-XXXX` and exposes this 128-bit service:

```text
Service: F0100001-0000-4A6B-9E10-464F4C4F5631
Audio notify:   F0100002-0000-4A6B-9E10-464F4C4F5631
Event notify:   F0100003-0000-4A6B-9E10-464F4C4F5631
Control write:  F0100004-0000-4A6B-9E10-464F4C4F5631
```

| Characteristic | Direction | Payload |
| --- | --- | --- |
| Audio | device → Mac | 166-byte IMA-ADPCM frame, or a 6-byte EOS marker |
| Event | device → Mac | `1` Typeless start, `2` Typeless stop, `3` Return, `4` legacy cancel/Escape, `5` Doubao start, `6` Doubao stop, `7` Doubao stop and send Return |
| Control | Mac → device | Typeless state: `0` idle, `1` recording, `2` processing, `3` not running |

The audio frame contains a sequence number, predictor, step index, and ADPCM payload. The Bridge inserts silence for small sequence gaps and records packet-loss statistics in the status view.

## Validation matrix

Keep automated and physical results separate:

```text
Build:        idf.py build / validate.sh --firmware
Host tests:   validate.sh --static and FoloVibeCoreTests
Device tests: real board, BLE, display, buttons, speaker, microphone, Typeless
```

Recommended real-device checklist:

- [ ] Device advertises `FoloVibe-*` and the Mac Bridge connects.
- [ ] Bridge reports audio subscribed and `BlackHole 2ch` is selected in Typeless.
- [ ] OK starts/stops a Typeless dictation and the focused field receives text.
- [ ] UP starts/stops Doubao input and the focused field receives text.
- [ ] The two input methods are mutually exclusive; the other provider's key is ignored while recording.
- [ ] DOWN stops the active input and sends Return.
- [ ] Button beep is audible without breaking microphone capture.
- [ ] Waveform shows green low activity, yellow medium activity, and red peaks, then decays after stop.
- [ ] USB Serial/JTAG still enumerates after reset and the protected identity remains intact.

## Troubleshooting

### Bridge cannot find the board

Confirm Bluetooth is on, the device is advertising `FoloVibe-*`, and the Settings prefix is `FoloVibe`. Press reset or reconnect USB if the firmware is not running. Use the Logs and Debug tabs before deleting saved settings.

### Typeless does not receive audio

Confirm Typeless uses `BlackHole 2ch` as its microphone, macOS has granted the required audio permission, and the Bridge Status tab says audio is subscribed. The Bridge must also have Accessibility permission to post keys.

### Fn or F19 does not trigger Typeless

The Bridge default is the macOS Fn/Globe modifier, not F19. Configure both Typeless and the Bridge to `Fn`, or choose `F19` in both places. The Bridge supports F13 through F20 and persists the selection.

### Doubao does not start or stop

In Doubao IME settings, enable its toggle mode and set the shortcut to match the Bridge's `Doubao` setting. The default is `Right Option`. If your version uses Fn instead, select `Fn` in both places. Grant Accessibility/Input Monitoring permissions if macOS blocks synthetic modifier-key events.

### USB port disappeared

Unplug and reconnect the board, then list `/dev/cu.usbmodem*` again. Do not assume the old suffix is still valid. If the board is in Recovery, release the UP key after the bootloader enters it and reconnect the USB port.

### Build is rejected by the firmware verifier

Do not bypass the verifier. Check that ESP-IDF is 5.5.3, `sdkconfig.defaults` is being used, the image is a merged full image, and no partition-table or protected-region files were changed unintentionally.

## Contributing

Create a feature branch from `main`, keep hardware constants in the BSP, keep UI/protocol logic in `main`, run `./tools/validate.sh`, and document physical acceptance separately. Never commit credentials, device QR secrets, private keys, real logs, or personal data. See [CONTRIBUTING](../../.github/CONTRIBUTING.md) and [AGENTS.md](../../AGENTS.md).

## License

This fork keeps the repository's MIT License. See [LICENSE](../../LICENSE).
