#pragma once

#include "vibe_state.h"
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VIBE_UI_BARS 16

typedef struct {
    vibe_phase_t phase;
    int battery;          // 0..100, or -1 if missing
    uint8_t typeless;
    uint8_t bars[VIBE_UI_BARS];
    uint32_t sent;
    uint32_t dropped;
} vibe_ui_model_t;

void vibe_ui_start(void);
void vibe_ui_set(const vibe_ui_model_t *model);

#ifdef __cplusplus
}
#endif
