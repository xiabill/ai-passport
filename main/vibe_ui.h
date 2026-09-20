#pragma once

#include "vibe_state.h"
#include "vibe_power.h"
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VIBE_UI_BARS 36

typedef struct {
    vibe_phase_t phase;
    bool linked;
    bool audio_sub;
    uint8_t actions[VIBE_GESTURE_COUNT];  // action bound to each gesture
    uint8_t active_gesture;               // VIBE_GESTURE_NONE when idle
    int battery;          // 0..100, or -1
    int battery_mv;       // or -1
    bool charging;        // inferred from the gauge, not a hardware line
    int charge_minutes;   // until full, or -1 when it cannot be stated honestly
    uint8_t typeless;
    vibe_power_mode_t power_mode;
    uint8_t last_event;   // 0 if none
    uint8_t bars[VIBE_UI_BARS];
    uint32_t sent;
    uint32_t dropped;
} vibe_ui_model_t;

void vibe_ui_start(void);
void vibe_ui_set(const vibe_ui_model_t *model);

// Called from the BLE task. A chunk that reaches the end of the slot's bitmap
// makes it visible; a chunk at offset 0 hides it until then.
void vibe_ui_label_chunk(uint8_t slot, uint16_t off, const uint8_t *data, uint16_t len);
void vibe_ui_label_clear(uint8_t slot);
// Labels belong to the Mac that sent them; a new link starts from the defaults.
void vibe_ui_labels_reset(void);

#ifdef __cplusplus
}
#endif
