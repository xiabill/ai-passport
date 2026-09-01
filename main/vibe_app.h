#pragma once

#include "bsp_button.h"
#include "esp_err.h"
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

esp_err_t vibe_app_start(void);

// Button callback context: button task. Must not block, must not touch LVGL.
void vibe_app_on_button(bsp_btn_t btn, bsp_btn_ev_t ev);

// BLE / audio callbacks: NimBLE or audio task. Must not touch LVGL.
void vibe_app_on_ble_link(bool up);
void vibe_app_on_audio_sub(bool sub);
void vibe_app_on_typeless(uint8_t state);
void vibe_app_on_power_mode(uint8_t mode);
void vibe_app_on_silence(void);
void vibe_app_note_peak(uint8_t level);

#ifdef __cplusplus
}
#endif
