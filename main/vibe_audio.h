#pragma once

#include "esp_err.h"
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

esp_err_t vibe_audio_start(void);
void vibe_audio_set_recording(bool on);
bool vibe_audio_recording(void);
// 请求一个短促的按键提示音；只置位标志，由音频任务异步播放。
void vibe_audio_beep(void);

#ifdef __cplusplus
}
#endif
