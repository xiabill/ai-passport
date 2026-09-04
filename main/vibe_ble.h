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
// Eco mode pauses advertising after a grace period while disconnected. A
// function-key activity resumes it so the Mac can reconnect.
void vibe_ble_set_power_mode(bool eco);
void vibe_ble_note_activity(void);
// Stop BLE activity before manual light sleep and resume advertising after a
// GPIO wake. The device intentionally gives up the Mac link while asleep.
void vibe_ble_prepare_light_sleep(void);
void vibe_ble_resume_after_light_sleep(void);

#ifdef __cplusplus
}
#endif
