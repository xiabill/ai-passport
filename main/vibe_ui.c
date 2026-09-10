#include "vibe_ui.h"
#include "bsp_battery.h"
#include "ui_font.h"
#include "vibe_ble.h"
#include "vibe_power.h"
#include "vibe_protocol.h"
#include "esp_app_desc.h"
#include "esp_timer.h"
#include "lvgl.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

#include <stdio.h>
#include <string.h>

// A calm dark dashboard. The screen answers two questions — is it recording,
// and what will each key do — so everything else is either secondary or gone.
#define VU_BG      0x0E0E10
#define VU_CARD    0x1B1B1F
#define VU_LINE    0x303036
#define VU_TEXT    0xFFFFFF
#define VU_DIM     0x8A8A90
#define VU_GREEN   0x32D74B
#define VU_RED     0xFF453A
#define VU_ORANGE  0xFF9F0A
#define VU_BLUE    0x0A84FF
#define VU_PURPLE  0xBF5AF2
#define VU_CYAN    0x64D2FF
#define VU_HOT     0xFF6B8A

#define VU_KEY_W   70
#define VU_KEY_H   96
#define VU_KEY_Y   190

static SemaphoreHandle_t s_mu;
static lv_obj_t *s_scr;
static lv_obj_t *s_led;
static lv_obj_t *s_phase;
static lv_obj_t *s_batt;
static lv_obj_t *s_meter_hint;
static lv_obj_t *s_foot;
static vibe_charge_t s_charge;
static lv_obj_t *s_key_box[3];
static lv_obj_t *s_key_name[3];
static lv_obj_t *s_key_act[3];
static lv_obj_t *s_bars[VIBE_UI_BARS];
static lv_timer_t *s_timer;
static vibe_ui_model_t s_live;
static vibe_phase_t s_shown = (vibe_phase_t)255;
static uint8_t s_shown_gesture = 0xFEU;
static bool s_led_on;

static lv_obj_t *card(lv_obj_t *parent, int x, int y, int w, int h, uint32_t fill)
{
    lv_obj_t *obj = lv_obj_create(parent);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_pos(obj, x, y);
    lv_obj_set_size(obj, w, h);
    lv_obj_set_style_radius(obj, 10, 0);
    lv_obj_set_style_pad_all(obj, 0, 0);
    lv_obj_set_style_border_width(obj, 1, 0);
    lv_obj_set_style_border_color(obj, lv_color_hex(VU_LINE), 0);
    lv_obj_set_style_bg_color(obj, lv_color_hex(fill), 0);
    // A top-lit gradient and a soft drop shadow lift the card off the
    // background; flat fills on this LCD look like printed paper.
    lv_obj_set_style_bg_grad_color(obj, lv_color_hex(VU_BG), 0);
    lv_obj_set_style_bg_grad_dir(obj, LV_GRAD_DIR_VER, 0);
    lv_obj_set_style_bg_main_stop(obj, 0, 0);
    lv_obj_set_style_bg_grad_stop(obj, 255, 0);
    lv_obj_set_style_shadow_width(obj, 8, 0);
    lv_obj_set_style_shadow_offset_y(obj, 2, 0);
    lv_obj_set_style_shadow_color(obj, lv_color_hex(0x000000), 0);
    lv_obj_set_style_shadow_opa(obj, LV_OPA_40, 0);
    return obj;
}

static lv_obj_t *text(lv_obj_t *parent, const char *s, const lv_font_t *font, uint32_t color)
{
    lv_obj_t *lab = lv_label_create(parent);
    lv_label_set_text(lab, s);
    lv_obj_set_style_text_font(lab, font, 0);
    lv_obj_set_style_text_color(lab, lv_color_hex(color), 0);
    return lab;
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
    case VIBE_ACT_NEWLINE: return "换行";
    case VIBE_ACT_CUSTOM: return "自定";
    default: return "--";
    }
}

// The full version string is far too long for a 224px line, and the suffix is
// the same on every build anyway. A dirty build gets a star so a hand-flashed
// device is never mistaken for a release.
static const char *short_version(void)
{
    static char buf[12];
    if (buf[0]) return buf;
    const esp_app_desc_t *d = esp_app_get_description();
    const char *v = d->version;
    if (*v == 'v') v++;
    size_t n = 0;
    while (v[n] && v[n] != '-' && n + 2 < sizeof(buf)) n++;
    memcpy(buf, v, n);
    buf[n] = strstr(d->version, "dirty") ? '*' : '\0';
    buf[n + 1] = '\0';
    return buf;
}

static const char *power_mode_title(vibe_power_mode_t mode)
{
    return mode == VIBE_POWER_ECO ? "省电模式" : "正常模式";
}

// Each action family gets its own hue so the three keys read apart at a
// glance instead of being three identical grey boxes.
static uint32_t action_color(uint8_t action)
{
    switch (action) {
    case VIBE_ACT_DICTATE:
    case VIBE_ACT_TRANSLATE:
    case VIBE_ACT_ASK: return VU_BLUE;
    case VIBE_ACT_DOUBAO: return VU_GREEN;
    case VIBE_ACT_ENTER:
    case VIBE_ACT_NEWLINE: return VU_ORANGE;
    case VIBE_ACT_SELECT_ALL:
    case VIBE_ACT_CLEAR: return VU_PURPLE;
    default: return VU_DIM;
    }
}

// Tint toward the card colour: a saturated fill would glare on this LCD.
static lv_color_t tint(uint32_t color, lv_opa_t amount)
{
    return lv_color_mix(lv_color_hex(color), lv_color_hex(VU_CARD), amount);
}

static uint32_t phase_color(vibe_phase_t p)
{
    switch (p) {
    case VIBE_PHASE_IDLE: return VU_GREEN;
    case VIBE_PHASE_RECORDING: return VU_RED;
    case VIBE_PHASE_PROCESSING: return VU_ORANGE;
    default: return VU_DIM;
    }
}


static void paint(const vibe_ui_model_t *m)
{
    uint32_t accent = phase_color(m->phase);
    lv_obj_set_style_bg_color(s_led, lv_color_hex(accent), 0);
    lv_obj_set_style_shadow_color(s_led, lv_color_hex(accent), 0);
    lv_label_set_text(s_phase, phase_title(m->phase));
    lv_obj_set_style_text_color(s_phase, lv_color_hex(
        m->phase == VIBE_PHASE_RECORDING ? VU_RED : VU_TEXT), 0);

    char line[64];
    if (m->battery >= 0) {
        snprintf(line, sizeof(line), "%s%d%%", m->charging ? "+" : "", m->battery);
    } else {
        snprintf(line, sizeof(line), "--");
    }
    lv_label_set_text(s_batt, line);
    uint32_t batt_color = VU_DIM;
    if (m->charging) batt_color = VU_GREEN;
    else if (m->battery >= 0 && m->battery <= 15) batt_color = VU_RED;
    else if (m->battery >= 0 && m->battery <= 30) batt_color = VU_ORANGE;
    lv_obj_set_style_text_color(s_batt, lv_color_hex(batt_color), 0);

    // Device name and power mode sit at the bottom in the dim colour; the
    // packet counters and last-gesture line were debug output and are gone.
    // Only CJK and ASCII are in the font, so a separator like U+00B7 renders
    // as a box. Two spaces read the same and always exist.
    if (m->charging && m->charge_minutes > 0) {
        snprintf(line, sizeof(line), "%s  充满 %d:%02d  %s", vibe_ble_name(),
                 m->charge_minutes / 60, m->charge_minutes % 60, short_version());
    } else {
        snprintf(line, sizeof(line), "%s  %s  %s", vibe_ble_name(),
                 power_mode_title(m->power_mode), short_version());
    }
    lv_label_set_text(s_foot, line);

    const bool recording = m->phase == VIBE_PHASE_RECORDING && m->audio_sub;
    if (recording) {
        lv_obj_add_flag(s_meter_hint, LV_OBJ_FLAG_HIDDEN);
    } else {
        const char *hint = "按键说话";
        if (!m->linked) hint = "未连接";
        else if (!m->audio_sub) hint = "等待音频";
        else if (m->phase == VIBE_PHASE_PROCESSING) hint = "处理中";
        lv_label_set_text(s_meter_hint, hint);
        lv_obj_remove_flag(s_meter_hint, LV_OBJ_FLAG_HIDDEN);
    }
    for (int i = 0; i < VIBE_UI_BARS; i++) {
        if (!recording) {
            lv_obj_add_flag(s_bars[i], LV_OBJ_FLAG_HIDDEN);
            continue;
        }
        lv_obj_remove_flag(s_bars[i], LV_OBJ_FLAG_HIDDEN);
        // Peak level is 0..16. Quiet samples stay as a thin baseline rather
        // than vanishing, so the trace reads as one continuous waveform.
        // Level is 0..16 over a 3..99 px span: loud speech should visibly
        // fill the card, not nudge a stub.
        uint8_t level = m->bars[i];
        int h = 3 + (int)level * 6;
        if (h > 99) h = 99;
        lv_obj_set_size(s_bars[i], 4, h);
        lv_obj_set_pos(s_bars[i], 6 + i * 6, 56 - h / 2);
        // Peaks tip into a warm colour; quiet stays cyan-blue.
        lv_obj_set_style_bg_color(s_bars[i],
            lv_color_hex(level >= 13 ? VU_HOT : VU_CYAN), 0);
    }

    // The keys carry the current binding, so the device always states what it
    // will do rather than expecting the shortcut to be memorised.
    static const uint8_t wire[3] = {VIBE_BTN_UP, VIBE_BTN_MID, VIBE_BTN_DOWN};
    const bool live = m->phase == VIBE_PHASE_IDLE || m->phase == VIBE_PHASE_RECORDING;
    for (int i = 0; i < 3; i++) {
        uint8_t button = wire[i];
        bool active = m->active_gesture < VIBE_GESTURE_COUNT &&
                      (m->active_gesture / 3U) == button;
        uint8_t action = m->actions[button * 3U + VIBE_GES_CLICK];

        const char *label = action_title(action);
        uint32_t hue = action_color(action);
        lv_color_t fill = lv_color_hex(VU_CARD);
        lv_color_t edge = lv_color_hex(VU_LINE);
        lv_color_t fg = tint(hue, LV_OPA_90);
        lv_color_t name_fg = lv_color_hex(VU_DIM);
        int edge_w = 1;

        if (!live) {
            label = m->phase == VIBE_PHASE_PROCESSING ? "处理中" : "等待";
            fg = lv_color_hex(VU_DIM);
        } else if (active) {
            // The running take is the one thing worth shouting about, so the
            // whole cell fills instead of merely changing its outline.
            label = "停止";
            fill = tint(VU_RED, LV_OPA_80);
            edge = lv_color_hex(VU_RED);
            fg = lv_color_hex(0xFFFFFF);
            name_fg = tint(VU_RED, LV_OPA_40);
            edge_w = 2;
        } else if (action == VIBE_ACT_NONE) {
            label = "--";
            fg = lv_color_hex(VU_DIM);
        } else if (m->phase == VIBE_PHASE_RECORDING && VIBE_ACT_RECORDS(action)) {
            // Pressing the other input method is ignored, so grey it out.
            fg = lv_color_hex(VU_DIM);
        } else {
            fill = tint(hue, LV_OPA_20);
            edge = tint(hue, LV_OPA_60);
        }
        lv_label_set_text(s_key_act[i], label);
        lv_obj_set_style_text_color(s_key_act[i], fg, 0);
        lv_obj_set_style_text_color(s_key_name[i], name_fg, 0);
        lv_obj_set_style_bg_color(s_key_box[i], fill, 0);
        lv_obj_set_style_border_color(s_key_box[i], edge, 0);
        lv_obj_set_style_border_width(s_key_box[i], edge_w, 0);
    }

    s_shown = m->phase;
    s_shown_gesture = m->active_gesture;
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
    const int fine = bsp_battery_soc_fine();
    vibe_charge_sample(&s_charge, fine, (uint32_t)(esp_timer_get_time() / 1000));
    m.battery = fine >= 0 ? fine >> 8 : -1;
    m.battery_mv = bsp_battery_mv();
    m.charging = s_charge.charging;
    m.charge_minutes = vibe_charge_minutes_to_full(&s_charge);
    xSemaphoreTake(s_mu, portMAX_DELAY);
    s_live.battery = m.battery;
    s_live.battery_mv = m.battery_mv;
    s_live.charging = m.charging;
    s_live.charge_minutes = m.charge_minutes;
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

    s_scr = lv_obj_create(NULL);
    lv_obj_remove_flag(s_scr, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_bg_color(s_scr, lv_color_hex(VU_BG), 0);
    lv_obj_set_style_pad_all(s_scr, 0, 0);
    lv_obj_set_style_border_width(s_scr, 0, 0);

    // Status strip: the one line that says whether the device is usable.
    lv_obj_t *top = card(s_scr, 8, 10, 224, 44, VU_CARD);
    s_led = lv_obj_create(top);
    lv_obj_remove_flag(s_led, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_size(s_led, 12, 12);
    lv_obj_set_pos(s_led, 12, 15);
    lv_obj_set_style_radius(s_led, 6, 0);
    lv_obj_set_style_border_width(s_led, 0, 0);
    lv_obj_set_style_pad_all(s_led, 0, 0);
    lv_obj_set_style_bg_color(s_led, lv_color_hex(VU_DIM), 0);
    // The dot glows in its state colour, so status reads from arm's length.
    lv_obj_set_style_shadow_width(s_led, 10, 0);
    lv_obj_set_style_shadow_spread(s_led, 1, 0);
    lv_obj_set_style_shadow_opa(s_led, LV_OPA_60, 0);

    s_phase = text(top, "离线", &ui_font_cjk_16, VU_TEXT);
    lv_obj_set_pos(s_phase, 32, 12);

    s_batt = text(top, "--", &ui_font_cjk_14, VU_DIM);
    lv_obj_align(s_batt, LV_ALIGN_RIGHT_MID, -12, 0);

    // Middle: the waveform while talking, a single hint otherwise.
    lv_obj_t *meter = card(s_scr, 8, 62, 224, VU_KEY_Y - 62 - 8, VU_CARD);
    s_meter_hint = text(meter, "按键说话", &ui_font_cjk_16, VU_DIM);
    lv_obj_center(s_meter_hint);
    for (int i = 0; i < VIBE_UI_BARS; i++) {
        s_bars[i] = lv_obj_create(meter);
        lv_obj_remove_flag(s_bars[i], LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_set_size(s_bars[i], 4, 3);
        lv_obj_set_style_radius(s_bars[i], 2, 0);
        lv_obj_set_style_border_width(s_bars[i], 0, 0);
        lv_obj_set_style_pad_all(s_bars[i], 0, 0);
        // Each bar carries its own vertical gradient, so colour follows height
        // continuously. Switching the whole bar between colour bands made the
        // trace flicker while speaking.
        lv_obj_set_style_bg_color(s_bars[i], lv_color_hex(VU_CYAN), 0);
        lv_obj_set_style_bg_grad_color(s_bars[i], lv_color_hex(VU_BLUE), 0);
        lv_obj_set_style_bg_grad_dir(s_bars[i], LV_GRAD_DIR_VER, 0);
        lv_obj_add_flag(s_bars[i], LV_OBJ_FLAG_HIDDEN);
    }

    // The keys are the point of the product, so they get the most room.
    static const char *names[3] = {"上", "中", "下"};
    for (int i = 0; i < 3; i++) {
        int x = 8 + i * (VU_KEY_W + 7);
        s_key_box[i] = card(s_scr, x, VU_KEY_Y, VU_KEY_W, VU_KEY_H, VU_CARD);
        s_key_name[i] = text(s_key_box[i], names[i], &ui_font_cjk_16, VU_DIM);
        lv_obj_align(s_key_name[i], LV_ALIGN_TOP_MID, 0, 14);
        s_key_act[i] = text(s_key_box[i], "--", &ui_font_cjk_16, VU_TEXT);
        lv_obj_set_width(s_key_act[i], VU_KEY_W - 8);
        lv_obj_set_style_text_align(s_key_act[i], LV_TEXT_ALIGN_CENTER, 0);
        lv_label_set_long_mode(s_key_act[i], LV_LABEL_LONG_WRAP);
        lv_obj_align(s_key_act[i], LV_ALIGN_TOP_MID, 0, 44);
    }

    // Device name and power mode: worth showing, not worth the eye's attention.
    s_foot = text(s_scr, "FoloVibe", &ui_font_cjk_14, VU_DIM);
    lv_obj_set_width(s_foot, 224);
    lv_obj_set_style_text_align(s_foot, LV_TEXT_ALIGN_CENTER, 0);
    lv_label_set_long_mode(s_foot, LV_LABEL_LONG_DOT);
    lv_obj_set_pos(s_foot, 8, VU_KEY_Y + VU_KEY_H + 8);

    memset(&s_live, 0, sizeof(s_live));
    s_live.battery = -1;
    s_live.battery_mv = -1;
    s_live.charging = false;
    s_live.charge_minutes = -1;
    vibe_charge_reset(&s_charge);
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
