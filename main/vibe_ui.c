#include "vibe_ui.h"
#include "bsp_battery.h"
#include "ui_font.h"
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
static lv_obj_t *s_meter_hint;
static lv_obj_t *s_key_up;
static lv_obj_t *s_key_mid;
static lv_obj_t *s_key_dn;
static lv_obj_t *s_bars[VIBE_UI_BARS];
static lv_obj_t *s_mascot;
static lv_timer_t *s_timer;
static vibe_ui_model_t s_live;
static vibe_phase_t s_shown = (vibe_phase_t)255;
static uint8_t s_shown_gesture = 0xFEU;
static uint32_t s_rec_t0;
static bool s_led_on;

static lv_obj_t *ink_box(lv_obj_t *parent, int x, int y, int w, int h, uint32_t fill)
{
    lv_obj_t *obj = lv_obj_create(parent);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_pos(obj, x, y);
    lv_obj_set_size(obj, w, h);
    lv_obj_set_style_radius(obj, 5, 0);
    lv_obj_set_style_pad_all(obj, 0, 0);
    lv_obj_set_style_border_width(obj, 3, 0);
    lv_obj_set_style_border_color(obj, lv_color_hex(UI_INK), 0);
    lv_obj_set_style_bg_color(obj, lv_color_hex(fill), 0);
    return obj;
}

static lv_obj_t *key_chip(lv_obj_t *parent, int x, int y)
{
    // The button label uses two 17px CJK lines. Leave a 2px inner border and
    // exactly 34px of content height so neither line is clipped.
    lv_obj_t *box = ink_box(parent, x, y, 64, 38, UI_PAPER);
    lv_obj_set_style_border_width(box, 2, 0);
    lv_obj_t *lab = lv_label_create(box);
    lv_obj_set_width(lab, 60);
    lv_obj_set_height(lab, 34);
    lv_label_set_long_mode(lab, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_font(lab, &ui_font_cjk_14, 0);
    lv_obj_set_style_text_align(lab, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_line_space(lab, 0, 0);
    lv_obj_set_style_text_letter_space(lab, 0, 0);
    lv_obj_set_style_text_color(lab, lv_color_hex(UI_INK), 0);
    lv_obj_center(lab);
    lv_label_set_text(lab, "");
    return lab;
}

// Keep future labels readable on the 240px display. Explicit newlines remain
// supported, while long labels are wrapped after at most five English words.
static void wrap_key_text(const char *text, char *out, size_t cap)
{
    if (!cap) return;
    size_t n = 0;
    unsigned words = 0;
    bool in_word = false;
    for (const char *p = text; *p && n + 1 < cap; p++) {
        char c = *p;
        if (c == '\n') {
            while (n && out[n - 1] == ' ') n--;
            out[n++] = '\n';
            words = 0;
            in_word = false;
            continue;
        }
        if (c == ' ') {
            if (in_word && n + 1 < cap) out[n++] = ' ';
            in_word = false;
            continue;
        }
        if (!in_word) {
            if (words >= 5) {
                if (n && out[n - 1] == ' ') n--;
                if (n + 1 >= cap) break;
                out[n++] = '\n';
                words = 0;
            }
            words++;
            in_word = true;
        }
        out[n++] = c;
    }
    while (n && out[n - 1] == ' ') n--;
    out[n] = '\0';
}

static void set_key(lv_obj_t *lab, const char *text, uint32_t fill)
{
    lv_obj_t *box = lv_obj_get_parent(lab);
    lv_obj_set_style_bg_color(box, lv_color_hex(fill), 0);
    char wrapped[64];
    wrap_key_text(text, wrapped, sizeof(wrapped));
    lv_label_set_text(lab, wrapped);
}

static uint32_t phase_color(vibe_phase_t p)
{
    switch (p) {
    case VIBE_PHASE_WAIT: return UI_YELLOW;
    case VIBE_PHASE_IDLE: return UI_GREEN;
    case VIBE_PHASE_RECORDING: return UI_RED;
    case VIBE_PHASE_PROCESSING: return UI_ORANGE;
    default: return UI_MUTED;
    }
}

static const char *phase_title(vibe_phase_t p)
{
    switch (p) {
    case VIBE_PHASE_WAIT: return "连接中";
    case VIBE_PHASE_IDLE: return "就绪";
    case VIBE_PHASE_RECORDING: return "录音中";
    case VIBE_PHASE_PROCESSING: return "处理中";
    default: return "离线";
    }
}

// Short labels for the on-screen key hints. The bridge owns the real action
// names; the device only needs something that fits under a key.
static const char *action_title(uint8_t action)
{
    switch (action) {
    case VIBE_ACT_DICTATE: return "语音";
    case VIBE_ACT_TRANSLATE: return "翻译";
    case VIBE_ACT_ASK: return "随便问";
    case VIBE_ACT_DOUBAO: return "豆包";
    case VIBE_ACT_ENTER: return "发送";
    case VIBE_ACT_SELECT_ALL: return "全选";
    case VIBE_ACT_CLEAR: return "删除";
    default: return "--";
    }
}

static const char *active_title(const vibe_ui_model_t *m)
{
    if (m->active_gesture >= VIBE_GESTURE_COUNT) return "--";
    return action_title(m->actions[m->active_gesture]);
}

static const char *power_mode_title(vibe_power_mode_t mode)
{
    return mode == VIBE_POWER_ECO ? "省电模式" : "正常模式";
}

static uint32_t bar_color(uint8_t level, bool enabled)
{
    if (!enabled) return UI_MUTED;
    if (level <= 4) return UI_GREEN;
    if (level <= 10) return UI_YELLOW;
    return UI_RED;
}

// Events are raw gestures now, so the screen names the gesture rather than a
// meaning the device no longer owns.
static const char *event_title(uint8_t ev)
{
    static char buf[24];
    if (ev < VIBE_BLE_GESTURE_BASE) return "--";
    uint8_t btn = (uint8_t)((ev - VIBE_BLE_GESTURE_BASE) >> 2);
    uint8_t ges = (uint8_t)(ev & 0x03U);
    if (btn > VIBE_BTN_DOWN || ges > VIBE_GES_LONG) return "--";
    const char *bn = btn == VIBE_BTN_UP ? "上" : (btn == VIBE_BTN_MID ? "中" : "下");
    const char *gn = ges == VIBE_GES_CLICK ? "单击"
                   : (ges == VIBE_GES_DOUBLE ? "双击" : "长按");
    snprintf(buf, sizeof(buf), "%s键%s", bn, gn);
    return buf;
}


// One key hint = physical key name + whatever its single click is bound to.
static void set_gesture_key(lv_obj_t *obj, const char *name,
                            const vibe_ui_model_t *m, uint8_t button)
{
    char buf[32];
    bool active = m->active_gesture < VIBE_GESTURE_COUNT &&
                  (m->active_gesture / 3U) == button;
    if (active) {
        snprintf(buf, sizeof(buf), "%s\n停止", name);
        set_key(obj, buf, UI_RED);
        return;
    }
    uint8_t action = m->actions[button * 3U + VIBE_GES_CLICK];
    snprintf(buf, sizeof(buf), "%s\n%s", name, action_title(action));
    if (action == VIBE_ACT_NONE) {
        set_key(obj, buf, UI_MUTED);
    } else if (m->phase == VIBE_PHASE_RECORDING && VIBE_ACT_RECORDS(action)) {
        // 录音中按另一个录音键会打断当前这段,弱化提示。
        set_key(obj, buf, UI_MUTED);
    } else {
        set_key(obj, buf, UI_PAPER);
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

    char line[64];
    snprintf(line, sizeof(line), "%s  %s",
             active_title(m), m->linked ? "已连接" : "未连接");
    lv_label_set_text(s_line_tl, line);

    snprintf(line, sizeof(line), "%s  %s", vibe_ble_name(),
             power_mode_title(m->power_mode));
    lv_label_set_text(s_line_name, line);

    if (m->battery >= 0 && m->battery_mv >= 0) {
        snprintf(line, sizeof(line), "电量 %d%%  %d.%02dV", m->battery,
                 m->battery_mv / 1000, (m->battery_mv % 1000) / 10);
    } else if (m->battery >= 0) {
        snprintf(line, sizeof(line), "电量 %d%%", m->battery);
    } else {
        snprintf(line, sizeof(line), "电量 --");
    }
    lv_label_set_text(s_line_batt, line);
    uint32_t batt_color = UI_INK;
    if (m->battery >= 0 && m->battery <= 15) batt_color = UI_RED;
    else if (m->battery >= 0 && m->battery <= 30) batt_color = UI_ORANGE;
    lv_obj_set_style_text_color(s_line_batt, lv_color_hex(batt_color), 0);

    if (!m->linked) {
        snprintf(line, sizeof(line), "音频离线");
    } else if (!m->audio_sub) {
        snprintf(line, sizeof(line), "音频等待");
    } else if (m->phase == VIBE_PHASE_RECORDING) {
        snprintf(line, sizeof(line), "音频正常%s", m->dropped ? "  丢包" : "");
    } else if (m->dropped) {
        snprintf(line, sizeof(line), "音频正常  丢包 %lu",
                 (unsigned long)m->dropped);
    } else {
        snprintf(line, sizeof(line), "音频正常");
    }
    lv_label_set_text(s_line_tx, line);

    snprintf(line, sizeof(line), "最近 %s", event_title(m->last_event));
    lv_label_set_text(s_line_last, line);

    const bool recording = m->phase == VIBE_PHASE_RECORDING && m->audio_sub;
    if (recording) {
        lv_obj_add_flag(s_meter_hint, LV_OBJ_FLAG_HIDDEN);
    } else {
        const char *hint = "待机 / 按键说话";
        if (!m->linked) hint = "未连接";
        else if (!m->audio_sub) hint = "等待音频";
        else if (m->phase == VIBE_PHASE_WAIT) hint = "等待连接";
        else if (m->phase == VIBE_PHASE_PROCESSING) hint = "处理中";
        lv_label_set_text(s_meter_hint, hint);
        lv_obj_remove_flag(s_meter_hint, LV_OBJ_FLAG_HIDDEN);
    }
    for (int i = 0; i < VIBE_UI_BARS; i++) {
        // Peak level is 0..16. Keep the waveform compact so one loud sample
        // does not turn the whole meter into a solid wall of red.
        if (!recording) {
            lv_obj_add_flag(s_bars[i], LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        lv_obj_remove_flag(s_bars[i], LV_OBJ_FLAG_HIDDEN);
        int h = 4 + (int)m->bars[i] * 2;
        if (h > 34) h = 34;
        lv_obj_set_height(s_bars[i], h);
        lv_obj_set_y(s_bars[i], 22 - h / 2);
        lv_obj_set_style_bg_color(s_bars[i],
            lv_color_hex(bar_color(m->bars[i], m->audio_sub)), 0);
    }

    // 按键提示直接反映当前绑定:设备上写着什么,按下去就是什么。
    if (m->phase == VIBE_PHASE_IDLE || m->phase == VIBE_PHASE_RECORDING) {
        set_gesture_key(s_key_up, "UP", m, VIBE_BTN_UP);
        set_gesture_key(s_key_mid, "MID", m, VIBE_BTN_MID);
        set_gesture_key(s_key_dn, "DOWN", m, VIBE_BTN_DOWN);
    } else {
        const char *hint = m->phase == VIBE_PHASE_PROCESSING ? "处理" : "等待";
        char buf[24];
        snprintf(buf, sizeof(buf), "UP\n%s", hint);
        set_key(s_key_up, buf, UI_MUTED);
        snprintf(buf, sizeof(buf), "MID\n%s", hint);
        set_key(s_key_mid, buf, UI_MUTED);
        snprintf(buf, sizeof(buf), "DOWN\n%s", hint);
        set_key(s_key_dn, buf, m->phase == VIBE_PHASE_PROCESSING ? UI_ORANGE : UI_MUTED);
    }

    if (m->phase != s_shown || m->active_gesture != s_shown_gesture) {
        s_shown = m->phase;
        s_shown_gesture = m->active_gesture;
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
    s_scr = ui_pixel_screen_create("语音助手");

    lv_obj_t *panel = ui_pixel_panel_create(s_scr, 10, 46, 220, 208, UI_PAPER);
    // This dense HUD needs a little more usable content area than the
    // default shared panel style; keep the other demo panels unchanged.
    lv_obj_set_style_pad_all(panel, 2, 0);

    s_led = ink_box(panel, 4, 4, 16, 16, UI_MUTED);

    s_phase = ui_pixel_label(panel, "离线", &ui_font_cjk_16, UI_INK);
    lv_obj_set_width(s_phase, 128);
    lv_label_set_long_mode(s_phase, LV_LABEL_LONG_DOT);
    lv_obj_set_pos(s_phase, 26, 0);

    s_clock = ui_pixel_label(panel, "00:00", &lv_font_montserrat_20, UI_RED);
    lv_obj_align(s_clock, LV_ALIGN_TOP_RIGHT, -2, 0);
    lv_obj_add_flag(s_clock, LV_OBJ_FLAG_HIDDEN);

    s_line_tl = ui_pixel_label(panel, "语音  未连接", &ui_font_cjk_14, UI_INK);
    lv_obj_set_width(s_line_tl, 196);
    lv_label_set_long_mode(s_line_tl, LV_LABEL_LONG_DOT);
    lv_obj_set_pos(s_line_tl, 4, 24);

    lv_obj_t *meter = lv_obj_create(panel);
    lv_obj_remove_flag(meter, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_size(meter, 196, 42);
    // Align the meter to the panel's content center instead of relying on a
    // hard-coded x offset that leaves it a few pixels left of the buttons.
    lv_obj_align(meter, LV_ALIGN_TOP_MID, 0, 44);
    lv_obj_set_style_bg_color(meter, lv_color_hex(0xE8EEF0), 0);
    lv_obj_set_style_border_width(meter, 2, 0);
    lv_obj_set_style_border_color(meter, lv_color_hex(UI_INK), 0);
    lv_obj_set_style_radius(meter, 6, 0);
    lv_obj_set_style_pad_all(meter, 0, 0);
    s_meter_hint = ui_pixel_label(meter, "待机 / 按键说话", &ui_font_cjk_14, UI_TEXT_MUTED);
    lv_obj_set_width(s_meter_hint, 190);
    lv_obj_set_height(s_meter_hint, 38);
    lv_obj_set_style_text_align(s_meter_hint, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_center(s_meter_hint);
    for (int i = 0; i < VIBE_UI_BARS; i++) {
        s_bars[i] = lv_obj_create(meter);
        lv_obj_remove_flag(s_bars[i], LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_set_size(s_bars[i], 4, 4);
        lv_obj_set_pos(s_bars[i], 15 + i * 6, 19);
        lv_obj_set_style_radius(s_bars[i], 2, 0);
        lv_obj_set_style_border_width(s_bars[i], 0, 0);
        lv_obj_set_style_pad_all(s_bars[i], 0, 0);
        lv_obj_set_style_bg_color(s_bars[i], lv_color_hex(UI_MUTED), 0);
        lv_obj_add_flag(s_bars[i], LV_OBJ_FLAG_HIDDEN);
    }

    s_line_name = ui_pixel_label(panel, "FoloVibe  正常模式", &ui_font_cjk_14, UI_INK);
    lv_obj_set_width(s_line_name, 196);
    lv_label_set_long_mode(s_line_name, LV_LABEL_LONG_DOT);
    lv_obj_set_pos(s_line_name, 4, 90);
    s_line_batt = ui_pixel_label(panel, "电量 --", &ui_font_cjk_14, UI_INK);
    lv_obj_set_pos(s_line_batt, 4, 107);
    s_line_tx = ui_pixel_label(panel, "音频等待", &ui_font_cjk_14, UI_INK);
    lv_obj_set_width(s_line_tx, 196);
    lv_label_set_long_mode(s_line_tx, LV_LABEL_LONG_DOT);
    lv_obj_set_pos(s_line_tx, 4, 124);
    s_line_last = ui_pixel_label(panel, "最近 --", &ui_font_cjk_14, UI_INK);
    lv_obj_set_width(s_line_last, 196);
    lv_label_set_long_mode(s_line_last, LV_LABEL_LONG_DOT);
    lv_obj_set_pos(s_line_last, 4, 141);

    // With the reduced padding and 4px gaps, all three 64px chips fit inside
    // the 208px content width and height.
    // Hints follow the physical key order on the device: up, middle, down.
    s_key_up = key_chip(panel, 4, 158);
    s_key_mid = key_chip(panel, 72, 158);
    s_key_dn = key_chip(panel, 140, 158);

    // The 240x320 screen's grass starts at y=286. Keep the 38x48 mascot
    // centered and place its feet exactly on that boundary.
    s_mascot = ui_pixel_mascot_create(s_scr, 101, 238);
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
