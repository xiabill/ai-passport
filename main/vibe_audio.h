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
    VIBE_BEEP_BOOT = 32,
    VIBE_BEEP_DISCONNECT = 64,
    VIBE_BEEP_SLEEP = 128,
} vibe_beep_t;

// Request a cue; the audio task plays it when the codec is free.
void vibe_audio_beep(vibe_beep_t type);

// Cue loudness, 0 (silent) to VIBE_VOLUME_LEVELS - 1. Kept by the caller in
// NVS; this only applies it.
void vibe_audio_set_volume_level(uint8_t level);
uint8_t vibe_audio_volume_level(void);

// Blocks until queued cues have finished, or the timeout passes. For the one
// cue that has to finish before power goes: going to sleep.
void vibe_audio_drain(uint32_t timeout_ms);

#ifdef __cplusplus
}
#endif
