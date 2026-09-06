<p align="right">
  <a href="ota-plan.md">简体中文</a> · <strong>English</strong>
</p>

# Remote OTA plan

How the device could be upgraded without a USB cable. **Not implemented yet**;
this exists so the groundwork does not have to be redone later.

## What already works

The device ships with a permanent Recovery at `0x700000`, entered by holding the
up key for five seconds. It exposes a BLE service that the FoloToy mini program
uses to install firmware. See
[BLE and Recovery compatibility](ble-recovery-compatibility.en.md).

**Cable-free flashing is therefore possible today**, at the cost of entering
Recovery by hand and depending on the mini program. What follows is about
upgrading with one click inside the Bridge instead.

## Is there room

```
factory   0x010000 ~ 0x310000   3 MB     factory slot, must stay untouched
          0x310000 ~ 0x356000   280 KB   gap
cardid    0x356000 ~ 0x35A000   16 KB    device identity, protected
          0x35A000 ~ 0x700000   3.65 MB  available
recovery  0x700000 ~ 0x800000   1 MB     permanent Recovery, must stay untouched
```

The release gate allows a derivative to add partitions after cardid, provided
factory, cardid, and recovery keep their exact offsets and sizes and the merged
image carries only `0xFF` padding across the protected regions. Adding OTA
partitions is therefore within the rules.

## Partition layout

Appended to `partitions.csv`, leaving the first five rows untouched:

```
otadata,  data, ota,     0x35A000, 0x2000,
ota_0,    app,  ota_0,   0x360000, 0x1A0000,
ota_1,    app,  ota_1,   0x500000, 0x1A0000,
```

This ends at `0x6A0000`, leaving 384 KB before recovery.

Each app partition is therefore capped at 1.66 MB. The current firmware is
1.2 MB, so about 460 KB of headroom remains — worth a size check in CI so a
future change cannot quietly overflow it.

The 3 MB factory partition stays out of the OTA rotation as the final fallback:
even if both OTA slots are corrupted, the device still boots the factory image.
ESP-IDF application images are position independent, so the same `.bin` runs
from any app partition and the release artifact needs no OTA-specific build.

## Transport

Reuse the existing BLE link: add a write-only characteristic that receives
chunks, feed them through `esp_ota_begin` / `esp_ota_write` / `esp_ota_end`,
then `esp_ota_set_boot_partition` and reboot once the image verifies.

At the throughput this link achieves, a 1.2 MB image takes roughly one to two
minutes. Recording should be refused while an upgrade runs, with progress shown
on the device screen.

## Effort and risk

| Item | Estimate |
| --- | --- |
| Firmware: partitions, OTA service, on-screen progress | ~250 lines |
| Bridge: pick firmware, stream chunks, progress and failure handling | ~200 lines |
| Optional: compare against the latest GitHub release | ~150 lines |

**Unavoidable prerequisite**: a partition table cannot replace itself over the
air, so one USB flash is required to install the new layout. Everything after
that is cable-free.

The risk is contained. A failed or unverified write never switches the boot
partition, so the device keeps running the firmware it already has, and factory
plus Recovery remain as two further fallbacks.

## Order of work

1. Append the three partitions and confirm `./tools/validate.sh --firmware` still passes
2. Flash once over USB and confirm the device boots from factory with the new table
3. Implement the firmware OTA service, then push an image identical to the running one to prove the path
4. Push an image with a changed version string and confirm the reboot runs it
5. Interrupt a transfer deliberately and confirm the device falls back and keeps working
