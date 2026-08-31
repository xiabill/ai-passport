#pragma once

#include "esp_err.h"
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

esp_err_t vibe_audio_start(void);
void vibe_audio_set_recording(bool on);
bool vibe_audio_recording(void);

#ifdef __cplusplus
}
#endif
