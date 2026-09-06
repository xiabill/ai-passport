<p align="right">
  <a href="README.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# AI Passport — Vibe Typeless

This public fork of [FoloToy/ai-passport](https://github.com/FoloToy/ai-passport) turns the AI Passport into a Typeless push-to-talk microphone for vibe coding. The maintained implementation is on this repository's [`main`](https://github.com/xiabill/ai-passport/tree/main) branch.

- Firmware: ESP32-C3 BLE IMA-ADPCM microphone, Typeless / Doubao dual-input buttons, Return key, VIBE status page, power saving, and button feedback beep
- Bluetooth link: custom GATT service for audio, device events, and Typeless state
- Mac companion: [`tools/mac-bridge/`](tools/mac-bridge/) receives and decodes audio, writes PCM to `BlackHole 2ch`, and taps the configured Typeless / Doubao shortcuts
- Complete setup, build, flash, BLE protocol, and troubleshooting guide: [docs/development/vibe-typeless.md](docs/development/vibe-typeless.md)
- Chinese guide: [docs/development/vibe-typeless.zh_CN.md](docs/development/vibe-typeless.zh_CN.md)
- Ready-to-use downloads: [GitHub Releases](https://github.com/xiabill/ai-passport/releases/latest)

## Quick start for users

Download the latest [FoloVibe Bridge macOS package](https://github.com/xiabill/ai-passport/releases/latest), unzip it, and move `FoloVibeBridge.app` to `/Applications`. The same release contains the matching `FoloToy-AI-Passport-full.bin` firmware image.

On first launch, follow the in-app setup checks. Grant Bluetooth and Accessibility/Input Monitoring, install BlackHole 2ch, then select matching keys in Typeless, Doubao, and Bridge. The detailed [user guide](docs/releases/v0.3.1-vibe-typeless.md) covers installation, permissions, key mappings, firmware flashing, and troubleshooting.

## Quick start for developers

```bash
git clone https://github.com/xiabill/ai-passport.git
cd ai-passport

# macOS companion
cd tools/mac-bridge
./build.sh
# build.sh installs to /Applications by default
open /Applications/FoloVibeBridge.app
```

The firmware requires ESP-IDF 5.5.3 and an ESP32-C3 board. Follow the [full guide](docs/development/vibe-typeless.md) before flashing an existing device: the merged image must not overwrite the protected `cardid` partition.

This fork publishes the maintained implementation from `main`; use a feature branch for local changes and submit tested changes back to `main`.
