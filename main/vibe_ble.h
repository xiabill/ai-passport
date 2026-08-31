#pragma once

#include "esp_err.h"
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

esp_err_t vibe_ble_start(void);

bool vibe_ble_connected(void);
bool vibe_ble_audio_subscribed(void);

// `len` is VIBE_AUDIO_PKT_LEN for data, VIBE_AUDIO_HDR_LEN for EOS.
esp_err_t vibe_ble_audio_send(const uint8_t *pkt, size_t len);
esp_err_t vibe_ble_event_send(uint8_t ev);

void vibe_ble_stats(uint32_t *sent, uint32_t *dropped);
const char *vibe_ble_name(void);
// true = 7.5–15 ms for audio; false = idle gear after 2 s so a second press
// does not thrash the link.
void vibe_ble_link_fast(bool fast);

#ifdef __cplusplus
}
#endif
