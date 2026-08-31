#include "vibe_ui.h"
#include "bsp_battery.h"
#include "ui_pixel.h"
#include "vibe_ble.h"
#include "vibe_power.h"
#include "vibe_protocol.h"
#include "lvgl.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

#include <stdio.h>
#include <string.h>

static SemaphoreHandle_t s_mu;
static lv_obj_t *s_scr;
static lv_obj_t *s_led;
static lv_obj_t *s_phase;
static lv_obj_t *s_clock;
static lv_obj_t *s_line_tl;
static lv_obj_t *s_line_name;
static lv_obj_t *s_line_batt;
static lv_obj_t *s_line_tx;
static lv_obj_t *s_line_last;
static lv_obj_t *s_key_ok;
static lv_obj_t *s_key_dn;
static lv_obj_t *s_key_up;
static lv_obj_t *s_bars[VIBE_UI_BARS];
static lv_obj_t *s_mascot;
static lv_timer_t *s_timer;
static vibe_ui_model_t s_live;
static vibe_phase_t s_shown = (vibe_phase_t)255;
static uint32_t s_rec_t0;
static bool s_led_on;

static lv_obj_t *ink_box(lv_obj_t *parent, int x, int y, int w, int h, uint32_t fill)
{
    lv_obj_t *obj = lv_obj_create(parent);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_pos(obj, x, y);
    lv_obj_set_size(obj, w, h);
    lv_obj_set_style_radius(obj, 0, 0);
    lv_obj_set_style_pad_all(obj, 0, 0);
    lv_obj_set_style_border_width(obj, 3, 0);
    lv_obj_set_style_border_color(obj, lv_color_hex(UI_INK), 0);
    lv_obj_set_style_bg_color(obj, lv_color_hex(fill), 0);
    return obj;
}

static lv_obj_t *key_chip(lv_obj_t *parent, int x, int y)
{
    lv_obj_t *box = ink_box(parent, x, y, 62, 34, UI_PAPER);
    lv_obj_t *lab = lv_label_create(box);
    lv_obj_set_width(lab, 56);
    lv_obj_set_style_text_font(lab, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_align(lab, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_color(lab, lv_color_hex(UI_INK), 0);
    lv_obj_center(lab);
    lv_label_set_text(lab, "");
    return lab;
}

static void set_key(lv_obj_t *lab, const char *text, uint32_t fill)
{
    lv_obj_t *box = lv_obj_get_parent(lab);
    lv_obj_set_style_bg_color(box, lv_color_hex(fill), 0);
    lv_label_set_text(lab, text);
}

static uint32_t phase_color(vibe_phase_t p)
{
    switch (p) {
    case VIBE_PHASE_WAIT: return UI_YELLOW;
    case VIBE_PHASE_IDLE: return 0x7BE07A;
    case VIBE_PHASE_RECORDING: return UI_RED;
    case VIBE_PHASE_PROCESSING: return UI_ORANGE;
    default: return UI_MUTED;
    }
}

static const char *phase_title(vibe_phase_t p)
{
    switch (p) {
    case VIBE_PHASE_WAIT: return "WAIT";
    case VIBE_PHASE_IDLE: return "READY";
    case VIBE_PHASE_RECORDING: return "REC";
    case VIBE_PHASE_PROCESSING: return "TYPING";
    default: return "OFFLINE";
    }
}

static const char *tl_title(uint8_t tl)
{
    switch (tl) {
    case VIBE_TL_RECORDING: return "REC";
    case VIBE_TL_PROCESSING: return "BUSY";
    case VIBE_TL_DOWN: return "OFF";
    default: return "READY";
    }
}

static const char *source_title(vibe_source_t source)
{
    switch (source) {
    case VIBE_SOURCE_TYPELESS: return "TYP";
    case VIBE_SOURCE_DOUBAO: return "DB";
    default: return "--";
    }
}

static const char *event_title(uint8_t ev)
{
    switch (ev) {
    case VIBE_BLE_START: return "START";
    case VIBE_BLE_STOP: return "STOP";
    case VIBE_BLE_ENTER: return "SEND";
    case VIBE_BLE_CANCEL: return "CANCEL";
    case VIBE_BLE_DOUBAO_START: return "DB START";
    case VIBE_BLE_DOUBAO_STOP: return "DB STOP";
    case VIBE_BLE_DOUBAO_STOP_SEND: return "DB SEND";
    default: return "--";
    }
}

static void paint(const vibe_ui_model_t *m)
{
    uint32_t accent = phase_color(m->phase);
    lv_obj_set_style_bg_color(s_led, lv_color_hex(accent), 0);
    lv_label_set_text(s_phase, phase_title(m->phase));
    lv_obj_set_style_text_color(s_phase, lv_color_hex(
        m->phase == VIBE_PHASE_RECORDING ? UI_RED : UI_INK), 0);

    if (m->phase == VIBE_PHASE_RECORDING) {
        if (s_shown != VIBE_PHASE_RECORDING) s_rec_t0 = lv_tick_get();
        uint32_t sec = (lv_tick_get() - s_rec_t0) / 1000;
        char clk[12];
        snprintf(clk, sizeof(clk), "%02u:%02u",
                 (unsigned)(sec / 60 % 100), (unsigned)(sec % 60));
        lv_label_set_text(s_clock, clk);
        lv_obj_remove_flag(s_clock, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(s_clock, LV_OBJ_FLAG_HIDDEN);
    }

    char line[40];
    snprintf(line, sizeof(line), "MODE %s  LINK %s",
             source_title(m->source), m->linked ? "OK" : "--");
    lv_label_set_text(s_line_tl, line);

    snprintf(line, sizeof(line), "%s", vibe_ble_name());
    lv_label_set_text(s_line_name, line);

    if (m->battery >= 0 && m->battery_mv >= 0) {
        snprintf(line, sizeof(line), "BAT %d%%  %d.%02dV", m->battery,
                 m->battery_mv / 1000, (m->battery_mv % 1000) / 10);
    } else if (m->battery >= 0) {
        snprintf(line, sizeof(line), "BAT %d%%", m->battery);
    } else {
        snprintf(line, sizeof(line), "BAT --");
    }
    lv_label_set_text(s_line_batt, line);
    uint32_t batt_color = UI_INK;
    if (m->battery >= 0 && m->battery <= 15) batt_color = UI_RED;
    else if (m->battery >= 0 && m->battery <= 30) batt_color = UI_ORANGE;
    lv_obj_set_style_text_color(s_line_batt, lv_color_hex(batt_color), 0);

    if (!m->linked) {
        snprintf(line, sizeof(line), "AUDIO OFFLINE");
    } else if (!m->audio_sub) {
        snprintf(line, sizeof(line), "AUDIO WAITING");
    } else if (m->phase == VIBE_PHASE_RECORDING) {
        snprintf(line, sizeof(line), "AUDIO LIVE%s",
                 m->dropped ? "  DROP" : "");
    } else if (m->dropped) {
        snprintf(line, sizeof(line), "AUDIO OK  DROP %lu",
                 (unsigned long)m->dropped);
    } else {
        snprintf(line, sizeof(line), "AUDIO READY");
    }
    lv_label_set_text(s_line_tx, line);

    if (m->queued_enter) {
        snprintf(line, sizeof(line), "LAST %s  Q-SEND", event_title(m->last_event));
    } else {
        snprintf(line, sizeof(line), "LAST %s", event_title(m->last_event));
    }
    lv_label_set_text(s_line_last, line);

    for (int i = 0; i < VIBE_UI_BARS; i++) {
        int h = 3 + (int)m->bars[i] * 2;
        if (h > 32) h = 32;
        lv_obj_set_height(s_bars[i], h);
        lv_obj_set_y(s_bars[i], 20 - h / 2);
        uint32_t c = UI_MUTED;
        if (m->audio_sub) {
            if (m->bars[i] > 10) c = UI_RED;
            else if (m->bars[i] > 5) c = UI_YELLOW;
            else c = UI_GREEN;
        }
        lv_obj_set_style_bg_color(s_bars[i], lv_color_hex(c), 0);
    }

    switch (m->phase) {
    case VIBE_PHASE_IDLE:
        set_key(s_key_ok, "OK\nTYP", UI_YELLOW);
        set_key(s_key_dn, "DOWN\nENTER", UI_PAPER);
        set_key(s_key_up, "UP\nDB", UI_PAPER);
        break;
    case VIBE_PHASE_RECORDING:
        if (m->source == VIBE_SOURCE_DOUBAO) {
            set_key(s_key_ok, "OK\nBUSY", UI_MUTED);
            set_key(s_key_dn, "DOWN\nSEND", UI_YELLOW);
            set_key(s_key_up, "UP\nSTOP", UI_RED);
        } else {
            set_key(s_key_ok, "OK\nSTOP", UI_RED);
            set_key(s_key_dn, "DOWN\nSEND", UI_YELLOW);
            set_key(s_key_up, "UP\nBUSY", UI_MUTED);
        }
        break;
    case VIBE_PHASE_PROCESSING:
        set_key(s_key_ok, "OK\n--", UI_MUTED);
        set_key(s_key_dn, m->queued_enter ? "DOWN\nWAIT" : "DOWN\nSEND", UI_ORANGE);
        set_key(s_key_up, "UP\nBUSY", UI_MUTED);
        break;
    case VIBE_PHASE_WAIT:
        set_key(s_key_ok, "OK\n--", UI_MUTED);
        set_key(s_key_dn, "DOWN\n--", UI_MUTED);
        set_key(s_key_up, "UP\n--", UI_MUTED);
        break;
    default:
        set_key(s_key_ok, "OK\n--", UI_MUTED);
        set_key(s_key_dn, "DOWN\n--", UI_MUTED);
        set_key(s_key_up, "UP\n--", UI_MUTED);
        break;
    }

    if (m->phase != s_shown) {
        s_shown = m->phase;
        ui_pixel_mascot_jump(s_mascot);
    }
}

static void on_tick(lv_timer_t *timer)
{
    (void)timer;
    vibe_power_tick();
    if (!vibe_power_screen_on()) return;

    vibe_ui_model_t m;
    xSemaphoreTake(s_mu, portMAX_DELAY);
    m = s_live;
    xSemaphoreGive(s_mu);
    m.battery = bsp_battery_soc();
    m.battery_mv = bsp_battery_mv();
    xSemaphoreTake(s_mu, portMAX_DELAY);
    s_live.battery = m.battery;
    s_live.battery_mv = m.battery_mv;
    xSemaphoreGive(s_mu);
    paint(&m);

    if (m.phase == VIBE_PHASE_RECORDING) {
        s_led_on = !s_led_on;
        lv_obj_set_style_bg_opa(s_led, s_led_on ? LV_OPA_COVER : LV_OPA_40, 0);
    } else {
        lv_obj_set_style_bg_opa(s_led, LV_OPA_COVER, 0);
    }
}

void vibe_ui_start(void)
{
    s_mu = xSemaphoreCreateMutex();
    s_scr = ui_pixel_screen_create("VIBE");

    lv_obj_t *panel = ui_pixel_panel_create(s_scr, 10, 46, 220, 198, UI_PAPER);

    s_led = ink_box(panel, 4, 4, 16, 16, UI_MUTED);

    s_phase = ui_pixel_label(panel, "OFFLINE", &lv_font_montserrat_20, UI_INK);
    lv_obj_set_pos(s_phase, 26, 0);

    s_clock = ui_pixel_label(panel, "00:00", &lv_font_montserrat_20, UI_RED);
    lv_obj_align(s_clock, LV_ALIGN_TOP_RIGHT, -2, 0);
    lv_obj_add_flag(s_clock, LV_OBJ_FLAG_HIDDEN);

    s_line_tl = ui_pixel_label(panel, "TYPE --  LINK --", &lv_font_montserrat_14, UI_INK);
    lv_obj_set_pos(s_line_tl, 4, 24);

    lv_obj_t *meter = lv_obj_create(panel);
    lv_obj_remove_flag(meter, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_size(meter, 196, 40);
    lv_obj_set_pos(meter, 4, 46);
    lv_obj_set_style_bg_color(meter, lv_color_hex(0xE8EEF0), 0);
    lv_obj_set_style_border_width(meter, 3, 0);
    lv_obj_set_style_border_color(meter, lv_color_hex(UI_INK), 0);
    lv_obj_set_style_radius(meter, 0, 0);
    lv_obj_set_style_pad_all(meter, 0, 0);
    for (int i = 0; i < VIBE_UI_BARS; i++) {
        s_bars[i] = lv_obj_create(meter);
        lv_obj_remove_flag(s_bars[i], LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_set_size(s_bars[i], 5, 3);
        lv_obj_set_pos(s_bars[i], 14 + i * 6, 18);
        lv_obj_set_style_radius(s_bars[i], 0, 0);
        lv_obj_set_style_border_width(s_bars[i], 0, 0);
        lv_obj_set_style_pad_all(s_bars[i], 0, 0);
        lv_obj_set_style_bg_color(s_bars[i], lv_color_hex(UI_MUTED), 0);
    }

    s_line_name = ui_pixel_label(panel, "FoloVibe", &lv_font_montserrat_14, UI_INK);
    lv_obj_set_width(s_line_name, 196);
    lv_label_set_long_mode(s_line_name, LV_LABEL_LONG_DOT);
    lv_obj_set_pos(s_line_name, 4, 90);
    s_line_batt = ui_pixel_label(panel, "BAT --", &lv_font_montserrat_14, UI_INK);
    lv_obj_set_pos(s_line_batt, 4, 108);
    s_line_tx = ui_pixel_label(panel, "AUDIO WAITING", &lv_font_montserrat_14, UI_INK);
    lv_obj_set_pos(s_line_tx, 4, 126);
    s_line_last = ui_pixel_label(panel, "LAST --", &lv_font_montserrat_14, UI_INK);
    lv_obj_set_pos(s_line_last, 4, 144);

    s_key_ok = key_chip(panel, 4, 164);
    s_key_dn = key_chip(panel, 72, 164);
    s_key_up = key_chip(panel, 140, 164);

    // 沿用官方 VIBE 基线的固定坐标；该屏幕的草地从 y=286 开始，
    // 38x48 的吉祥物放在 y=248 时正好站在草地上方，且跳跃动画可安全修改 y。
    s_mascot = ui_pixel_mascot_create(s_scr, 101, 248);
    memset(&s_live, 0, sizeof(s_live));
    s_live.battery = -1;
    s_live.battery_mv = -1;
    s_timer = lv_timer_create(on_tick, 200, NULL);
    lv_screen_load(s_scr);
    paint(&s_live);
}

void vibe_ui_set(const vibe_ui_model_t *model)
{
    if (!s_mu) return;
    xSemaphoreTake(s_mu, portMAX_DELAY);
    int battery = s_live.battery;
    int mv = s_live.battery_mv;
    s_live = *model;
    if (s_live.battery < 0) s_live.battery = battery;
    if (s_live.battery_mv < 0) s_live.battery_mv = mv;
    xSemaphoreGive(s_mu);
}
