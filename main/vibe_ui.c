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

// Layout, top to bottom:
//   status bar   link + device name on the left, battery on the right
//   hero         one large element that says what the device is doing;
//                while talking it gives way to a full-width live waveform
//   keys         what each key does on a click, double click and long press
//   footer       power mode and firmware version, for when they matter
//
// Colour carries meaning and nothing else: green is ready, red is live,
// orange is working, and each action family keeps one hue everywhere.
#define VU_BG_TOP  0x141418
#define VU_BG_BOT  0x060607
#define VU_CARD    0x19191E
#define VU_LINE    0x2C2C33
#define VU_TEXT    0xF5F5F7
#define VU_DIM     0x9A9AA2
#define VU_FAINT   0x5C5C64
#define VU_GREEN   0x32D74B
#define VU_RED     0xFF453A
#define VU_ORANGE  0xFF9F0A
#define VU_BLUE    0x0A84FF
#define VU_PURPLE  0xBF5AF2
#define VU_CYAN    0x64D2FF
#define VU_HOT     0xFF6B8A

// Strings shown in the 24px hero font. The font generator collects only the
// characters inside HERO(), keeping that font to a handful of glyphs.
#define HERO(s) s

#define RING_D     96
#define RING_X     ((240 - RING_D) / 2)
#define RING_Y     44
#define KEY_W      72
#define KEY_H      94
#define KEY_Y      206
#define BAR_PITCH  6
#define BAR_W      4
#define BAR_MID_Y  126
#define BAR_MAX_H  116

static SemaphoreHandle_t s_mu;
static lv_obj_t *s_scr;
static lv_obj_t *s_link_icon, *s_name;
static lv_obj_t *s_batt_icon, *s_batt;
static lv_obj_t *s_idle;           // hero group shown when not recording
static lv_obj_t *s_halo, *s_ring, *s_mic, *s_bt, *s_spin;
static lv_obj_t *s_title, *s_sub;
static lv_obj_t *s_rec;            // hero group shown while recording
static lv_obj_t *s_rec_dot, *s_rec_clock;
static lv_obj_t *s_bars[VIBE_UI_BARS];
static lv_obj_t *s_key[3], *s_key_bar[3], *s_key_name[3], *s_key_act[3];
static lv_obj_t *s_key_tag[3][2], *s_key_alt[3][2];
static lv_obj_t *s_foot;
static vibe_charge_t s_charge;

// Custom labels: one alpha bitmap per gesture, written by the BLE task and
// drawn by LVGL tinted in the key's colour. Sized exactly per slot kind.
static uint8_t s_lab_main[3][VIBE_LABEL_MAIN_W * VIBE_LABEL_MAIN_H];
static uint8_t s_lab_alt[6][VIBE_LABEL_ALT_W * VIBE_LABEL_ALT_H];
static lv_image_dsc_t s_lab_dsc[VIBE_GESTURE_COUNT];
static volatile bool s_lab_ready[VIBE_GESTURE_COUNT];
static volatile uint8_t s_lab_gen[VIBE_GESTURE_COUNT];   // bumped when a bitmap completes
static uint8_t s_lab_shown_gen[VIBE_GESTURE_COUNT];
static lv_obj_t *s_key_img[3], *s_key_alt_img[3][2];
static lv_timer_t *s_timer;
static vibe_ui_model_t s_live;
static int64_t s_rec_since_us;
static int64_t s_batt_at_us;
static bool s_was_recording;

// --- small helpers ---------------------------------------------------------
// LVGL invalidates on every setter call, even when nothing changes. The
// screen is repainted several times a second, so each setter checks first
// and the panel only redraws what actually moved.

static void set_text(lv_obj_t *l, const char *s)
{
    if (strcmp(lv_label_get_text(l), s) != 0) lv_label_set_text(l, s);
}

static void set_fg(lv_obj_t *o, uint32_t hex)
{
    lv_color_t c = lv_color_hex(hex);
    if (!lv_color_eq(lv_obj_get_style_text_color(o, 0), c)) lv_obj_set_style_text_color(o, c, 0);
}

static void set_fg_c(lv_obj_t *o, lv_color_t c)
{
    if (!lv_color_eq(lv_obj_get_style_text_color(o, 0), c)) lv_obj_set_style_text_color(o, c, 0);
}

static void set_bg_c(lv_obj_t *o, lv_color_t c)
{
    if (!lv_color_eq(lv_obj_get_style_bg_color(o, 0), c)) lv_obj_set_style_bg_color(o, c, 0);
}

static void set_border_c(lv_obj_t *o, lv_color_t c)
{
    if (!lv_color_eq(lv_obj_get_style_border_color(o, 0), c)) lv_obj_set_style_border_color(o, c, 0);
}

static void show(lv_obj_t *o, bool on)
{
    if (on == lv_obj_has_flag(o, LV_OBJ_FLAG_HIDDEN)) {
        if (on) lv_obj_remove_flag(o, LV_OBJ_FLAG_HIDDEN);
        else lv_obj_add_flag(o, LV_OBJ_FLAG_HIDDEN);
    }
}

// Mix toward the card colour: saturated fills glare on this panel.
static lv_color_t tint(uint32_t color, lv_opa_t amount)
{
    return lv_color_mix(lv_color_hex(color), lv_color_hex(VU_CARD), amount);
}

static lv_obj_t *box(lv_obj_t *parent, int x, int y, int w, int h)
{
    lv_obj_t *o = lv_obj_create(parent);
    lv_obj_remove_flag(o, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_remove_flag(o, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_pos(o, x, y);
    lv_obj_set_size(o, w, h);
    lv_obj_set_style_pad_all(o, 0, 0);
    lv_obj_set_style_border_width(o, 0, 0);
    lv_obj_set_style_radius(o, 0, 0);
    lv_obj_set_style_bg_opa(o, LV_OPA_TRANSP, 0);
    return o;
}

static lv_obj_t *fill(lv_obj_t *parent, int x, int y, int w, int h, int r, uint32_t hex)
{
    lv_obj_t *o = box(parent, x, y, w, h);
    lv_obj_set_style_radius(o, r, 0);
    lv_obj_set_style_bg_opa(o, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(o, lv_color_hex(hex), 0);
    return o;
}

static lv_obj_t *text(lv_obj_t *parent, const char *s, const lv_font_t *font, uint32_t color)
{
    lv_obj_t *lab = lv_label_create(parent);
    lv_label_set_text(lab, s);
    lv_obj_set_style_text_font(lab, font, 0);
    lv_obj_set_style_text_color(lab, lv_color_hex(color), 0);
    return lab;
}

static lv_obj_t *centered(lv_obj_t *parent, const char *s, const lv_font_t *font,
                          uint32_t color, int y)
{
    lv_obj_t *lab = text(parent, s, font, color);
    lv_obj_set_width(lab, 240);
    lv_obj_set_style_text_align(lab, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_pos(lab, 0, y);
    return lab;
}

// --- content -----------------------------------------------------------------

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
    case VIBE_ACT_HANDOFF: return "切换";
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
    switch (mode) {
    case VIBE_POWER_ECO: return "省电模式";
    case VIBE_POWER_ULTRA: return "超级省电";
    default: return "正常模式";
    }
}

// Each action family keeps one hue on the key cards, so the keys read apart
// at a glance instead of being three identical grey boxes.
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
    case VIBE_ACT_CUSTOM:
    case VIBE_ACT_HANDOFF: return VU_CYAN;
    default: return VU_FAINT;
    }
}

static const char *battery_symbol(int pct)
{
    if (pct >= 90) return LV_SYMBOL_BATTERY_FULL;
    if (pct >= 65) return LV_SYMBOL_BATTERY_3;
    if (pct >= 40) return LV_SYMBOL_BATTERY_2;
    if (pct >= 15) return LV_SYMBOL_BATTERY_1;
    return LV_SYMBOL_BATTERY_EMPTY;
}

// --- painting ----------------------------------------------------------------

static void paint_status(const vibe_ui_model_t *m)
{
    set_fg(s_link_icon, m->linked ? VU_BLUE : VU_FAINT);
    set_text(s_name, vibe_ble_name());

    char line[24];
    if (m->battery >= 0) snprintf(line, sizeof(line), "%d%%", m->battery);
    else snprintf(line, sizeof(line), "--");
    set_text(s_batt, line);

    uint32_t hue = VU_DIM;
    if (m->charging) hue = VU_GREEN;
    else if (m->battery >= 0 && m->battery <= 15) hue = VU_RED;
    else if (m->battery >= 0 && m->battery <= 30) hue = VU_ORANGE;
    set_text(s_batt_icon, m->charging ? LV_SYMBOL_CHARGE : battery_symbol(m->battery));
    set_fg(s_batt_icon, hue);
    set_fg(s_batt, m->charging ? VU_GREEN : VU_DIM);
}

static void paint_idle_hero(const vibe_ui_model_t *m)
{
    const char *title;
    uint32_t accent;
    bool spinning = false, offline = false;
    if (!m->linked) {
        title = HERO("等待连接");
        accent = VU_FAINT;
        offline = true;
    } else if (m->phase == VIBE_PHASE_PROCESSING) {
        title = HERO("转写中");
        accent = VU_ORANGE;
        spinning = true;
    } else if (m->phase == VIBE_PHASE_IDLE && m->audio_sub) {
        title = HERO("就绪");
        accent = VU_GREEN;
    } else {
        title = HERO("连接中");
        accent = VU_DIM;
    }
    set_text(s_title, title);

    char sub[48];
    if (m->charging && m->charge_minutes > 0) {
        snprintf(sub, sizeof(sub), "充电中  约 %d:%02d 充满",
                 m->charge_minutes / 60, m->charge_minutes % 60);
    } else if (m->charging) {
        snprintf(sub, sizeof(sub), "充电中");
    } else if (offline) {
        snprintf(sub, sizeof(sub), "在 Mac 上打开 FoloVibe");
    } else if (spinning) {
        snprintf(sub, sizeof(sub), "文字马上就到");
    } else if (m->phase == VIBE_PHASE_IDLE && m->audio_sub) {
        snprintf(sub, sizeof(sub), "按下按键开始说话");
    } else {
        snprintf(sub, sizeof(sub), "正在准备音频");
    }
    set_text(s_sub, sub);

    set_border_c(s_ring, lv_color_hex(accent));
    set_bg_c(s_ring, tint(accent, LV_OPA_10));
    set_border_c(s_halo, tint(accent, LV_OPA_30));
    lv_color_t mic = lv_color_mix(lv_color_hex(accent), lv_color_hex(VU_TEXT), LV_OPA_40);
    for (uint32_t i = 0; i < lv_obj_get_child_count(s_mic); i++) {
        lv_obj_t *part = lv_obj_get_child(s_mic, (int32_t)i);
        if (lv_obj_check_type(part, &lv_arc_class)) {
            if (!lv_color_eq(lv_obj_get_style_arc_color(part, LV_PART_INDICATOR), mic))
                lv_obj_set_style_arc_color(part, mic, LV_PART_INDICATOR);
        } else {
            set_bg_c(part, mic);
        }
    }
    show(s_mic, !offline && !spinning);
    show(s_bt, offline);
    show(s_spin, spinning);
}

static void paint_recording(const vibe_ui_model_t *m)
{
    const int64_t now = esp_timer_get_time();
    int secs = (int)((now - s_rec_since_us) / 1000000);
    if (secs > 99 * 60 + 59) secs = 99 * 60 + 59;
    if (secs < 0) secs = 0;
    char clock[16];
    snprintf(clock, sizeof(clock), "%d:%02d", secs / 60, secs % 60);
    set_text(s_rec_clock, clock);
    // The dot breathes once a second; one cheap opacity change, no animation.
    const lv_opa_t opa = (now / 500000) % 2 ? LV_OPA_40 : LV_OPA_COVER;
    if (lv_obj_get_style_bg_opa(s_rec_dot, 0) != opa) lv_obj_set_style_bg_opa(s_rec_dot, opa, 0);

    for (int i = 0; i < VIBE_UI_BARS; i++) {
        // Level 0..16. Quiet stays a short stub so the trace reads as one line
        // rather than a scatter of dots; loud speech fills the whole band.
        const int level = m->bars[i] > 16 ? 16 : m->bars[i];
        int h = 4 + level * (BAR_MAX_H - 4) / 16;
        if (lv_obj_get_height(s_bars[i]) != h) {
            lv_obj_set_height(s_bars[i], h);
            lv_obj_set_y(s_bars[i], BAR_MID_Y - h / 2);
        }
        // Colour slides with loudness rather than switching bands, so a bar
        // hovering at a threshold does not flicker.
        set_bg_c(s_bars[i], lv_color_mix(lv_color_hex(VU_HOT), lv_color_hex(VU_CYAN),
                                         (lv_opa_t)(level * 255 / 16)));
    }
}

static void show_label(lv_obj_t *img, uint8_t slot, bool on, lv_color_t color)
{
    if (on && s_lab_shown_gen[slot] != s_lab_gen[slot]) {
        // Same buffer, new pixels. Image caching is off in this build, so the
        // pixels are read at draw time and a redraw is all it takes.
        s_lab_shown_gen[slot] = s_lab_gen[slot];
        if (lv_image_get_src(img) != &s_lab_dsc[slot]) lv_image_set_src(img, &s_lab_dsc[slot]);
        lv_obj_invalidate(img);
    }
    if (on && !lv_color_eq(lv_obj_get_style_image_recolor(img, 0), color)) {
        lv_obj_set_style_image_recolor(img, color, 0);
    }
    show(img, on);
}

static void paint_keys(const vibe_ui_model_t *m)
{
    static const uint8_t wire[3] = {VIBE_BTN_UP, VIBE_BTN_MID, VIBE_BTN_DOWN};
    static const uint8_t alt[2] = {VIBE_GES_DOUBLE, VIBE_GES_LONG};
    const bool live = m->linked && (m->phase == VIBE_PHASE_IDLE || m->phase == VIBE_PHASE_RECORDING);

    for (int i = 0; i < 3; i++) {
        const uint8_t b = wire[i];
        const bool active = m->active_gesture < VIBE_GESTURE_COUNT && m->active_gesture / 3U == b;
        const uint8_t action = m->actions[b * 3U + VIBE_GES_CLICK];
        uint32_t hue = action_color(action);
        const char *label = action_title(action);

        lv_color_t card = lv_color_hex(VU_CARD), edge = lv_color_hex(VU_LINE);
        lv_color_t fg = lv_color_hex(hue), bar = lv_color_hex(hue);
        bool alts = true;

        if (!live) {
            fg = bar = lv_color_hex(VU_FAINT);
        } else if (active) {
            // The running take is the one thing worth shouting about, so the
            // whole card fills and says how to end it.
            label = "停止";
            card = tint(VU_RED, LV_OPA_70);
            edge = bar = lv_color_hex(VU_RED);
            fg = lv_color_hex(VU_TEXT);
            alts = false;
        } else if (action == VIBE_ACT_NONE) {
            label = "--";
            fg = bar = lv_color_hex(VU_FAINT);
        } else if (m->phase == VIBE_PHASE_RECORDING && VIBE_ACT_RECORDS(action)) {
            // The other input method is ignored while one is recording.
            fg = bar = lv_color_hex(VU_FAINT);
        } else {
            card = tint(hue, LV_OPA_10);
        }

        set_bg_c(s_key[i], card);
        set_border_c(s_key[i], edge);
        set_bg_c(s_key_bar[i], bar);
        set_text(s_key_act[i], label);
        set_fg_c(s_key_act[i], fg);
        // "Stop" during a take is the device's own word; otherwise a label the
        // Mac drew replaces the built-in one.
        const bool custom = !active && s_lab_ready[b * 3U + VIBE_GES_CLICK];
        show_label(s_key_img[i], b * 3U + VIBE_GES_CLICK, custom, fg);
        show(s_key_act[i], !custom);
        set_fg(s_key_name[i], active ? VU_TEXT : VU_DIM);

        for (int k = 0; k < 2; k++) {
            const uint8_t a = m->actions[b * 3U + alt[k]];
            show(s_key_tag[i][k], alts);
            show(s_key_alt[i][k], alts);
            // The secondary rows fit two characters beside their tag; the one
            // three-character title gets its short form here.
            const char *name = a == VIBE_ACT_NONE ? "--"
                             : a == VIBE_ACT_ASK ? "提问" : action_title(a);
            set_text(s_key_alt[i][k], name);
            const uint32_t alt_fg = live && a != VIBE_ACT_NONE ? VU_DIM : VU_FAINT;
            set_fg(s_key_alt[i][k], alt_fg);
            const uint8_t slot = b * 3U + alt[k];
            const bool custom = alts && s_lab_ready[slot];
            show_label(s_key_alt_img[i][k], slot, custom, lv_color_hex(alt_fg));
            show(s_key_alt[i][k], alts && !custom);
        }
    }
}

static void paint(const vibe_ui_model_t *m)
{
    const bool recording = m->linked && m->phase == VIBE_PHASE_RECORDING && m->audio_sub;
    if (recording && !s_was_recording) s_rec_since_us = esp_timer_get_time();
    s_was_recording = recording;

    paint_status(m);
    show(s_idle, !recording);
    show(s_rec, recording);
    if (recording) paint_recording(m);
    else paint_idle_hero(m);
    paint_keys(m);

    char line[48];
    snprintf(line, sizeof(line), "%s  " LV_SYMBOL_BULLET "  %s",
             power_mode_title(m->power_mode), short_version());
    set_text(s_foot, line);
}

static void on_tick(lv_timer_t *timer)
{
    vibe_power_tick();
    if (!vibe_power_screen_on()) return;

    vibe_ui_model_t m;
    xSemaphoreTake(s_mu, portMAX_DELAY);
    m = s_live;
    xSemaphoreGive(s_mu);

    // The gauge is an I2C read; once a second is plenty for a battery and
    // leaves the fast ticks for the waveform.
    const int64_t now = esp_timer_get_time();
    if (now - s_batt_at_us >= 1000000 || m.battery < 0) {
        s_batt_at_us = now;
        const int fine = bsp_battery_soc_fine();
        const int mv = bsp_battery_mv();
        vibe_charge_sample(&s_charge, fine, mv, (uint32_t)(now / 1000));
        xSemaphoreTake(s_mu, portMAX_DELAY);
        s_live.battery = fine >= 0 ? fine >> 8 : -1;
        s_live.battery_mv = mv;
        s_live.charging = s_charge.charging;
        s_live.charge_minutes = vibe_charge_minutes_to_full(&s_charge);
        m.battery = s_live.battery;
        m.battery_mv = s_live.battery_mv;
        m.charging = s_live.charging;
        m.charge_minutes = s_live.charge_minutes;
        xSemaphoreGive(s_mu);
    }
    paint(&m);

    // Smooth waveform while talking, lazy otherwise.
    static uint32_t s_period = 250;
    const uint32_t period = s_was_recording ? 80 : 250;
    if (period != s_period) {
        s_period = period;
        lv_timer_set_period(timer, period);
    }
}

// --- construction --------------------------------------------------------------

static void build_status(void)
{
    s_link_icon = text(s_scr, LV_SYMBOL_BLUETOOTH, &lv_font_montserrat_14, VU_FAINT);
    lv_obj_set_pos(s_link_icon, 14, 12);
    s_name = text(s_scr, "FoloVibe", &ui_font_cjk_14, VU_DIM);
    lv_obj_set_pos(s_name, 32, 12);

    s_batt = text(s_scr, "--", &ui_font_cjk_14, VU_DIM);
    lv_obj_align(s_batt, LV_ALIGN_TOP_RIGHT, -14, 12);
    s_batt_icon = text(s_scr, LV_SYMBOL_BATTERY_FULL, &lv_font_montserrat_14, VU_DIM);
    lv_obj_align_to(s_batt_icon, s_batt, LV_ALIGN_OUT_LEFT_MID, -6, 0);
    // The icon keeps its place even when the percentage changes width.
    lv_obj_set_style_text_align(s_batt, LV_TEXT_ALIGN_RIGHT, 0);
    lv_obj_set_width(s_batt, 34);
    lv_obj_align(s_batt, LV_ALIGN_TOP_RIGHT, -14, 12);
    lv_obj_align(s_batt_icon, LV_ALIGN_TOP_RIGHT, -52, 12);

    fill(s_scr, 14, 36, 212, 1, 0, VU_LINE);
}

static void build_mic(lv_obj_t *parent)
{
    // A microphone from primitives: capsule, cradle, stem and foot. There is no
    // mic glyph in the built-in icon font, and a drawn one scales cleanly.
    s_mic = box(parent, RING_X, RING_Y, RING_D, RING_D);
    const int cx = RING_D / 2;
    fill(s_mic, cx - 9, 22, 18, 32, 9, VU_TEXT);
    lv_obj_t *cradle = lv_arc_create(s_mic);
    lv_obj_remove_flag(cradle, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(cradle, 36, 36);
    lv_obj_set_pos(cradle, cx - 18, 24);
    lv_arc_set_bg_angles(cradle, 0, 0);
    lv_arc_set_angles(cradle, 20, 160);
    lv_obj_set_style_arc_width(cradle, 3, LV_PART_INDICATOR);
    lv_obj_set_style_arc_rounded(cradle, true, LV_PART_INDICATOR);
    lv_obj_set_style_arc_opa(cradle, LV_OPA_TRANSP, LV_PART_MAIN);
    lv_obj_set_style_bg_opa(cradle, LV_OPA_TRANSP, LV_PART_KNOB);
    lv_obj_set_style_pad_all(cradle, 0, LV_PART_KNOB);
    fill(s_mic, cx - 1, 60, 3, 8, 1, VU_TEXT);
    fill(s_mic, cx - 9, 67, 18, 3, 2, VU_TEXT);
}

static void build_idle_hero(void)
{
    s_idle = box(s_scr, 0, 0, 240, KEY_Y - 4);

    s_halo = box(s_idle, RING_X - 10, RING_Y - 10, RING_D + 20, RING_D + 20);
    lv_obj_set_style_radius(s_halo, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_border_width(s_halo, 1, 0);

    s_ring = box(s_idle, RING_X, RING_Y, RING_D, RING_D);
    lv_obj_set_style_radius(s_ring, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_border_width(s_ring, 3, 0);
    lv_obj_set_style_bg_opa(s_ring, LV_OPA_COVER, 0);

    build_mic(s_idle);

    s_bt = text(s_idle, LV_SYMBOL_BLUETOOTH, &lv_font_montserrat_20, VU_FAINT);
    lv_obj_align(s_bt, LV_ALIGN_TOP_MID, 0, RING_Y + RING_D / 2 - 11);

    s_spin = lv_spinner_create(s_idle);
    lv_obj_remove_flag(s_spin, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(s_spin, RING_D, RING_D);
    lv_obj_set_pos(s_spin, RING_X, RING_Y);
    lv_spinner_set_anim_params(s_spin, 1000, 90);
    lv_obj_set_style_arc_width(s_spin, 3, LV_PART_MAIN);
    lv_obj_set_style_arc_width(s_spin, 3, LV_PART_INDICATOR);
    lv_obj_set_style_arc_opa(s_spin, LV_OPA_TRANSP, LV_PART_MAIN);
    lv_obj_set_style_arc_color(s_spin, lv_color_hex(VU_ORANGE), LV_PART_INDICATOR);

    s_title = centered(s_idle, HERO("就绪"), &ui_font_cjk_24, VU_TEXT, RING_Y + RING_D + 14);
    s_sub = centered(s_idle, "", &ui_font_cjk_14, VU_DIM, RING_Y + RING_D + 46);
}

static void build_recording(void)
{
    s_rec = box(s_scr, 0, 0, 240, KEY_Y - 4);

    s_rec_dot = fill(s_rec, 16, 51, 8, 8, 4, VU_RED);
    lv_obj_t *t = text(s_rec, "录音中", &ui_font_cjk_16, VU_RED);
    lv_obj_set_pos(t, 30, 46);
    s_rec_clock = text(s_rec, "0:00", &lv_font_montserrat_20, VU_TEXT);
    lv_obj_align(s_rec_clock, LV_ALIGN_TOP_RIGHT, -16, 44);

    // A faint centre line keeps the trace anchored when the room goes quiet.
    fill(s_rec, 12, BAR_MID_Y, 216, 1, 0, VU_LINE);
    const int x0 = (240 - VIBE_UI_BARS * BAR_PITCH + (BAR_PITCH - BAR_W)) / 2;
    for (int i = 0; i < VIBE_UI_BARS; i++) {
        s_bars[i] = fill(s_rec, x0 + i * BAR_PITCH, BAR_MID_Y - 2, BAR_W, 4, 2, VU_CYAN);
    }
    lv_obj_add_flag(s_rec, LV_OBJ_FLAG_HIDDEN);
}

static lv_obj_t *label_image(lv_obj_t *parent, int x, int y)
{
    lv_obj_t *img = lv_image_create(parent);
    lv_obj_set_pos(img, x, y);
    lv_obj_set_style_image_recolor_opa(img, LV_OPA_COVER, 0);
    lv_obj_add_flag(img, LV_OBJ_FLAG_HIDDEN);
    return img;
}

static void init_label_slots(void)
{
    for (uint8_t slot = 0; slot < VIBE_GESTURE_COUNT; slot++) {
        const bool main = slot % 3U == VIBE_GES_CLICK;
        lv_image_dsc_t *d = &s_lab_dsc[slot];
        memset(d, 0, sizeof(*d));
        d->header.magic = LV_IMAGE_HEADER_MAGIC;
        d->header.cf = LV_COLOR_FORMAT_A8;
        d->header.w = main ? VIBE_LABEL_MAIN_W : VIBE_LABEL_ALT_W;
        d->header.h = main ? VIBE_LABEL_MAIN_H : VIBE_LABEL_ALT_H;
        d->header.stride = d->header.w;
        d->data_size = d->header.w * d->header.h;
        d->data = main ? s_lab_main[slot / 3U] : s_lab_alt[(slot / 3U) * 2U + (slot % 3U) - 1U];
    }
}

static void build_keys(void)
{
    static const char *names[3] = {"上", "中", "下"};
    static const char *tags[2] = {"双", "长"};
    for (int i = 0; i < 3; i++) {
        const int x = 6 + i * (KEY_W + 6);
        lv_obj_t *k = box(s_scr, x, KEY_Y, KEY_W, KEY_H);
        lv_obj_set_style_radius(k, 12, 0);
        lv_obj_set_style_bg_opa(k, LV_OPA_COVER, 0);
        lv_obj_set_style_bg_color(k, lv_color_hex(VU_CARD), 0);
        lv_obj_set_style_border_width(k, 1, 0);
        lv_obj_set_style_border_color(k, lv_color_hex(VU_LINE), 0);
        lv_obj_set_style_clip_corner(k, true, 0);
        s_key[i] = k;

        // A strip of the action's colour along the top: the key's identity.
        s_key_bar[i] = fill(k, 0, 0, KEY_W, 3, 0, VU_FAINT);

        s_key_name[i] = text(k, names[i], &ui_font_cjk_14, VU_DIM);
        lv_obj_set_pos(s_key_name[i], 9, 9);

        s_key_act[i] = text(k, "--", &ui_font_cjk_16, VU_TEXT);
        lv_obj_set_width(s_key_act[i], KEY_W - 8);
        lv_obj_set_style_text_align(s_key_act[i], LV_TEXT_ALIGN_CENTER, 0);
        lv_label_set_long_mode(s_key_act[i], LV_LABEL_LONG_CLIP);
        lv_obj_set_pos(s_key_act[i], 4, 30);

        s_key_img[i] = label_image(k, (KEY_W - VIBE_LABEL_MAIN_W) / 2, 28);

        fill(k, 10, 54, KEY_W - 20, 1, 0, VU_LINE);

        for (int r = 0; r < 2; r++) {
            const int y = 59 + r * 16;
            s_key_tag[i][r] = text(k, tags[r], &ui_font_cjk_14, VU_FAINT);
            lv_obj_set_pos(s_key_tag[i][r], 9, y);
            s_key_alt[i][r] = text(k, "--", &ui_font_cjk_14, VU_DIM);
            lv_obj_set_width(s_key_alt[i][r], KEY_W - 30);
            lv_obj_set_style_text_align(s_key_alt[i][r], LV_TEXT_ALIGN_RIGHT, 0);
            lv_label_set_long_mode(s_key_alt[i][r], LV_LABEL_LONG_CLIP);
            lv_obj_set_pos(s_key_alt[i][r], 22, y);
            s_key_alt_img[i][r] = label_image(k, KEY_W - 7 - VIBE_LABEL_ALT_W, y + 1);
        }
    }
}

void vibe_ui_start(void)
{
    s_mu = xSemaphoreCreateMutex();

    s_scr = lv_obj_create(NULL);
    lv_obj_remove_flag(s_scr, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_pad_all(s_scr, 0, 0);
    lv_obj_set_style_border_width(s_scr, 0, 0);
    // A barely-there vertical falloff: flat black reads as "off" on this LCD.
    lv_obj_set_style_bg_color(s_scr, lv_color_hex(VU_BG_TOP), 0);
    lv_obj_set_style_bg_grad_color(s_scr, lv_color_hex(VU_BG_BOT), 0);
    lv_obj_set_style_bg_grad_dir(s_scr, LV_GRAD_DIR_VER, 0);

    init_label_slots();
    build_status();
    build_idle_hero();
    build_recording();
    build_keys();

    s_foot = centered(s_scr, "", &ui_font_cjk_14, VU_FAINT, KEY_Y + KEY_H + 4);

    memset(&s_live, 0, sizeof(s_live));
    s_live.battery = -1;
    s_live.battery_mv = -1;
    s_live.charge_minutes = -1;
    vibe_charge_reset(&s_charge);
    s_timer = lv_timer_create(on_tick, 250, NULL);
    lv_screen_load(s_scr);
    paint(&s_live);
}

void vibe_ui_set(const vibe_ui_model_t *model)
{
    if (!s_mu) return;
    xSemaphoreTake(s_mu, portMAX_DELAY);
    const int battery = s_live.battery;
    const int mv = s_live.battery_mv;
    const bool charging = s_live.charging;
    const int minutes = s_live.charge_minutes;
    s_live = *model;
    // Battery state is owned by the UI tick; the app's model does not carry it.
    if (s_live.battery < 0) s_live.battery = battery;
    if (s_live.battery_mv < 0) s_live.battery_mv = mv;
    s_live.charging = charging;
    s_live.charge_minutes = minutes;
    xSemaphoreGive(s_mu);
}

void vibe_ui_label_chunk(uint8_t slot, uint16_t off, const uint8_t *data, uint16_t len)
{
    if (slot >= VIBE_GESTURE_COUNT || !s_lab_dsc[slot].data) return;
    const uint32_t size = s_lab_dsc[slot].data_size;
    if (off >= size) return;
    if (len > size - off) len = (uint16_t)(size - off);
    // Hidden while it is being rewritten, so a half-sent label never shows.
    if (off == 0) s_lab_ready[slot] = false;
    memcpy((uint8_t *)s_lab_dsc[slot].data + off, data, len);
    if (off + len == size) {
        s_lab_gen[slot]++;
        s_lab_ready[slot] = true;
    }
}

void vibe_ui_label_clear(uint8_t slot)
{
    if (slot < VIBE_GESTURE_COUNT) s_lab_ready[slot] = false;
}

void vibe_ui_labels_reset(void)
{
    for (uint8_t i = 0; i < VIBE_GESTURE_COUNT; i++) s_lab_ready[i] = false;
}
