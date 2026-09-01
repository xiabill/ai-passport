#pragma once

#include "lvgl.h"

#ifdef __cplusplus
extern "C" {
#endif

// Keep the UI's font names stable while using LVGL's antialiased Source Han
// Sans SC subsets. This gives CJK glyphs the same baseline and visual weight
// instead of mixing a hand-rasterized 1bpp font with Montserrat.
#define ui_font_cjk_14 lv_font_source_han_sans_sc_14_cjk
#define ui_font_cjk_16 lv_font_source_han_sans_sc_16_cjk

#ifdef __cplusplus
}
#endif
