<p align="right">
  <a href="vibe-typeless.zh_CN.md">简体中文</a> · <strong>English</strong>
</p>

# Vibe Typeless companion

Firmware on `feature/vibe-typeless` turns AI Passport into a push-to-talk microphone for Typeless. The Mac bridge in `tools/mac-bridge/` writes decoded PCM into `BlackHole 2ch` and taps Typeless `F19`.

This is a dedicated application: boot skips the hardware demo menu and opens the VIBE page. `components/bsp` is unchanged.

## Buttons

| Key | Idle | Recording | After stop |
| --- | --- | --- | --- |
| OK | start talking | stop | ignored |
| DOWN | Enter | stop, then Enter when Typeless goes idle | queue Enter |
| UP | Escape | stop + Escape | Escape, return to idle |

Silence below the peak threshold for 30 s also stops a recording.

## On-device acceptance

Do not treat a host-test pass as hardware validation. Record PASS / FAIL / NOT RUN on a real board:

- [ ] `./tools/validate.sh --static` passes.
- [ ] ESP-IDF 5.5.3 `idf.py build` for ESP32-C3 succeeds.
- [ ] Device advertises `FoloVibe-*` and the Mac bridge connects.
- [ ] OK starts Typeless; speaking into the Passport mic produces text in the focused field.
- [ ] OK again stops Typeless and the screen leaves REC.
- [ ] DOWN while talking stops, waits for Typeless, then sends Return.
- [ ] UP cancels (Escape) and does not send.
- [ ] USB Serial/JTAG still enumerates for flashing.

## Unverified without the board

USB was not enumerated on the development Mac at implementation time, so flashing, microphone quality, BLE throughput, and MTU negotiation are unverified.
