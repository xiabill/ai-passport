#pragma once

#include "esp_err.h"
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Receives a firmware image over BLE and installs it into the inactive OTA
// slot. The factory partition is never a target, so a failed upgrade always
// leaves a bootable device behind.
//
// Framing on the OTA characteristic: the first write is a 5-byte header,
// 'F' 'W' followed by the image length as a little-endian uint32. Every
// later write is raw image data until that many bytes have arrived.
#define VIBE_OTA_HEADER_LEN 6U

typedef enum {
    VIBE_OTA_IDLE = 0,
    VIBE_OTA_RECEIVING,
    VIBE_OTA_APPLYING,
    VIBE_OTA_DONE,
    VIBE_OTA_FAILED,
} vibe_ota_state_t;

void vibe_ota_feed(const uint8_t *data, size_t len);
void vibe_ota_abort(void);
vibe_ota_state_t vibe_ota_state(void);
uint8_t vibe_ota_percent(void);

#ifdef __cplusplus
}
#endif
