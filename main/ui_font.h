#pragma once

#include "lvgl.h"

#ifdef __cplusplus
extern "C" {
#endif

// Compact CJK subsets used by the hardware UI. ASCII and punctuation fall
// back to LVGL's Montserrat fonts.
extern const lv_font_t ui_font_cjk_14;
extern const lv_font_t ui_font_cjk_20;

#ifdef __cplusplus
}
#endif
