#pragma once

#include "esp_err.h"
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

esp_err_t vibe_audio_start(void);
void vibe_audio_set_recording(bool on);
bool vibe_audio_recording(void);

typedef enum {
    VIBE_BEEP_START = 1,
    VIBE_BEEP_END = 2,
    VIBE_BEEP_EDIT = 4,
    VIBE_BEEP_READY = 8,
    VIBE_BEEP_SEND = 16,
} vibe_beep_t;

// Request a cue; the audio task plays it when the codec is free.
void vibe_audio_beep(vibe_beep_t type);

#ifdef __cplusplus
}
#endif
