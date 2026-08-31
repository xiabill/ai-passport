#include "vibe_ui.h"
#include "bsp_battery.h"
#include "ui_pixel.h"
#include "lvgl.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

#include <stdio.h>
#include <string.h>

static SemaphoreHandle_t s_mu;
static lv_obj_t *s_scr;
static lv_obj_t *s_phase;
static lv_obj_t *s_hint;
static lv_obj_t *s_stats;
static lv_obj_t *s_batt;
static lv_obj_t *s_bars[VIBE_UI_BARS];
static lv_obj_t *s_mascot;
static lv_timer_t *s_timer;
static vibe_ui_model_t s_live;
static vibe_phase_t s_shown = VIBE_PHASE_DOWN;

static const char *phase_title(vibe_phase_t p)
{
    switch (p) {
    case VIBE_PHASE_WAIT: return "WAIT MAC";
    case VIBE_PHASE_IDLE: return "READY";
    case VIBE_PHASE_RECORDING: return "REC";
    case VIBE_PHASE_PROCESSING: return "WAIT TEXT";
    default: return "OFFLINE";
    }
}

static const char *phase_hint(vibe_phase_t p)
{
    switch (p) {
    case VIBE_PHASE_WAIT: return "Open FoloVibe Bridge\non the Mac.";
    case VIBE_PHASE_IDLE: return "OK talk\nDOWN send   UP cancel";
    case VIBE_PHASE_RECORDING: return "Speaking...\nOK stop   DOWN send";
    case VIBE_PHASE_PROCESSING: return "Typeless is writing.";
    default: return "Waiting for BLE.";
    }
}

static void paint(const vibe_ui_model_t *m)
{
    lv_label_set_text(s_phase, phase_title(m->phase));
    lv_label_set_text(s_hint, phase_hint(m->phase));

    char line[48];
    if (m->battery >= 0) snprintf(line, sizeof(line), "%d%%", m->battery);
    else snprintf(line, sizeof(line), "--");
    lv_label_set_text(s_batt, line);

    snprintf(line, sizeof(line), "tx %lu  drop %lu",
             (unsigned long)m->sent, (unsigned long)m->dropped);
    lv_label_set_text(s_stats, line);

    for (int i = 0; i < VIBE_UI_BARS; i++) {
        int h = 4 + (int)m->bars[i] * 2;
        if (h > 36) h = 36;
        lv_obj_set_height(s_bars[i], h);
        lv_obj_set_y(s_bars[i], 36 - h);
        uint32_t color = m->phase == VIBE_PHASE_RECORDING ? UI_RED : UI_MUTED;
        lv_obj_set_style_bg_color(s_bars[i], lv_color_hex(color), 0);
    }

    if (m->phase != s_shown) {
        s_shown = m->phase;
        ui_pixel_mascot_jump(s_mascot);
    }
}

static void on_tick(lv_timer_t *timer)
{
    (void)timer;
    vibe_ui_model_t m;
    xSemaphoreTake(s_mu, portMAX_DELAY);
    m = s_live;
    xSemaphoreGive(s_mu);
    m.battery = bsp_battery_soc();
    xSemaphoreTake(s_mu, portMAX_DELAY);
    s_live.battery = m.battery;
    xSemaphoreGive(s_mu);
    paint(&m);
}

void vibe_ui_start(void)
{
    s_mu = xSemaphoreCreateMutex();
    s_scr = ui_pixel_screen_create("VIBE");
    s_batt = ui_pixel_label(s_scr, "--", &lv_font_montserrat_14, UI_PAPER);
    lv_obj_set_pos(s_batt, 162, 16);

    lv_obj_t *panel = ui_pixel_panel_create(s_scr, 16, 52, 208, 186, UI_PAPER);

    s_phase = ui_pixel_label(panel, "OFFLINE", &lv_font_montserrat_20, UI_INK);
    lv_obj_align(s_phase, LV_ALIGN_TOP_MID, 0, 4);

    s_hint = lv_label_create(panel);
    lv_obj_set_style_text_font(s_hint, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(s_hint, lv_color_hex(UI_INK), 0);
    lv_obj_set_style_text_align(s_hint, LV_TEXT_ALIGN_CENTER, 0);
    lv_label_set_long_mode(s_hint, LV_LABEL_LONG_WRAP);
    lv_obj_set_width(s_hint, 180);
    lv_obj_align(s_hint, LV_ALIGN_TOP_MID, 0, 36);

    lv_obj_t *meter = lv_obj_create(panel);
    lv_obj_remove_flag(meter, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_size(meter, 176, 36);
    lv_obj_align(meter, LV_ALIGN_BOTTOM_MID, 0, -28);
    lv_obj_set_style_bg_opa(meter, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(meter, 0, 0);
    lv_obj_set_style_pad_all(meter, 0, 0);
    for (int i = 0; i < VIBE_UI_BARS; i++) {
        s_bars[i] = lv_obj_create(meter);
        lv_obj_remove_flag(s_bars[i], LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_set_size(s_bars[i], 8, 4);
        lv_obj_set_pos(s_bars[i], i * 11, 32);
        lv_obj_set_style_radius(s_bars[i], 0, 0);
        lv_obj_set_style_border_width(s_bars[i], 0, 0);
        lv_obj_set_style_pad_all(s_bars[i], 0, 0);
        lv_obj_set_style_bg_color(s_bars[i], lv_color_hex(UI_MUTED), 0);
    }

    s_stats = ui_pixel_label(panel, "tx 0  drop 0", &lv_font_montserrat_14, UI_INK);
    lv_obj_align(s_stats, LV_ALIGN_BOTTOM_MID, 0, -4);

    s_mascot = ui_pixel_mascot_create(s_scr, 101, 244);
    memset(&s_live, 0, sizeof(s_live));
    s_live.battery = -1;
    s_timer = lv_timer_create(on_tick, 200, NULL);
    lv_screen_load(s_scr);
    paint(&s_live);
}

void vibe_ui_set(const vibe_ui_model_t *model)
{
    if (!s_mu) return;
    xSemaphoreTake(s_mu, portMAX_DELAY);
    int battery = s_live.battery;
    s_live = *model;
    if (s_live.battery < 0) s_live.battery = battery;
    xSemaphoreGive(s_mu);
}
