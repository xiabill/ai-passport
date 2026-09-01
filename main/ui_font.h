#pragma once

#include "lvgl.h"

#ifdef __cplusplus
extern "C" {
#endif

// Generated from every CJK character used by the firmware UI. The checked-in
// source is antialiased 4bpp data with a Montserrat fallback for Latin text.
extern const lv_font_t ui_font_cjk_14;
extern const lv_font_t ui_font_cjk_16;

#ifdef __cplusplus
}
#endif
