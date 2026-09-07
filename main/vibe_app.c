#include "vibe_app.h"
#include "vibe_audio.h"
#include "vibe_ble.h"
#include "vibe_power.h"
#include "vibe_protocol.h"
#include "vibe_state.h"
#include "vibe_shot.h"
#include "vibe_ui.h"

#include "esp_log.h"
#include "esp_timer.h"
#include "nvs.h"
#include "nvs_flash.h"

#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

static const char *TAG = "vibe_app";

// Fallback only. The normal exit from PROCESSING is the bridge writing back a
// Typeless idle/down state, which arrives within one poll of the transcript
// landing. This must outlast a long transcription, otherwise a queued Return
// fires while Typeless is still writing into the focused field.
#define PROC_TIMEOUT_US (20 * 1000 * 1000)

static SemaphoreHandle_t s_mu;
static vibe_state_t s_st;
static uint8_t s_bars[VIBE_UI_BARS];
static uint8_t s_bar_i;
static uint8_t s_bar_max;
static uint8_t s_bar_samples;
static uint8_t s_tail_level;
static uint8_t s_last_event;
static bool s_swallow_click;
static esp_timer_handle_t s_proc_timer;

static void apply(vibe_in_t in, uint32_t arg);
static void actions_load(void);

static void publish_locked(void)
{
    vibe_ui_model_t m = {0};
    m.phase = s_st.phase;
    m.active_gesture = s_st.active_gesture;
    for (int i = 0; i < VIBE_GESTURE_COUNT; i++) m.actions[i] = s_st.actions[i];
    m.linked = s_st.linked;
    m.audio_sub = s_st.audio_sub;
    m.typeless = s_st.typeless;
    m.power_mode = vibe_power_mode();
    m.last_event = s_last_event;
    m.battery = -1;
    m.battery_mv = -1;
    for (int i = 0; i < VIBE_UI_BARS; i++) {
        m.bars[i] = s_bars[(s_bar_i + i) % VIBE_UI_BARS];
    }
    vibe_ble_stats(&m.sent, &m.dropped);
    vibe_ui_set(&m);
}

static void proc_timeout(void *arg)
{
    (void)arg;
    apply(VIBE_IN_PROC_TIMEOUT, 0);
}

static void arm_proc_timer(bool on)
{
    if (!s_proc_timer) return;
    esp_timer_stop(s_proc_timer);
    if (on) esp_timer_start_once(s_proc_timer, PROC_TIMEOUT_US);
}

static void apply(vibe_in_t in, uint32_t arg)
{
    xSemaphoreTake(s_mu, portMAX_DELAY);
    vibe_out_t o = vibe_state_apply(&s_st, in, arg);
    bool processing = s_st.phase == VIBE_PHASE_PROCESSING;
    if (o.n_events) s_last_event = o.ble_events[o.n_events - 1];
    publish_locked();
    xSemaphoreGive(s_mu);

    if (o.start_capture) {
        vibe_audio_beep(VIBE_BEEP_START);
        vibe_audio_set_recording(true);
        vibe_power_set_busy(true);
        vibe_ble_link_fast(true);
    }
    if (o.stop_capture) {
        vibe_audio_beep(VIBE_BEEP_END);
        vibe_audio_set_recording(false);
        vibe_power_set_busy(false);
        vibe_ble_link_fast(false);
        vibe_power_note_activity();
    }
    if (o.edit_action) vibe_audio_beep(VIBE_BEEP_EDIT);
    for (uint8_t i = 0; i < o.n_events; i++) {
        // The send cue follows the actual event emission, so a queued Return
        // is acknowledged when it is released after Typeless processing.
        if (o.ble_events[i] == VIBE_BLE_ENTER ||
            o.ble_events[i] == VIBE_BLE_DOUBAO_STOP_SEND) {
            vibe_audio_beep(VIBE_BEEP_SEND);
        }
        vibe_ble_event_send(o.ble_events[i]);
    }
    arm_proc_timer(processing);
}

esp_err_t vibe_app_start(void)
{
    s_mu = xSemaphoreCreateMutex();
    if (!s_mu) return ESP_ERR_NO_MEM;
    vibe_state_init(&s_st);

    const esp_timer_create_args_t args = {
        .callback = proc_timeout,
        .name = "vibe_proc",
    };
    esp_err_t err = esp_timer_create(&args, &s_proc_timer);
    if (err != ESP_OK) return err;

    actions_load();
    vibe_power_init();
    vibe_ui_start();
    err = vibe_audio_start();
    if (err != ESP_OK) return err;
    err = vibe_ble_start();
    if (err != ESP_OK) return err;
    // Serves screen captures for the community publisher; a failure here must
    // not stop the device from working.
    if (vibe_shot_start() != ESP_OK) ESP_LOGW(TAG, "screen capture unavailable");
    ESP_LOGI(TAG, "vibe app ready");
    return ESP_OK;
}

// BSP enumerates buttons as UP/DOWN/OK; the wire protocol orders them by
// physical position (up/middle/down). Translate once, here.
static uint8_t wire_button(bsp_btn_t btn)
{
    switch (btn) {
    case BSP_BTN_UP: return VIBE_BTN_UP;
    case BSP_BTN_OK: return VIBE_BTN_MID;
    default: return VIBE_BTN_DOWN;
    }
}

static void report_gesture(bsp_btn_t btn, uint8_t gesture)
{
    apply(VIBE_IN_GESTURE, (uint32_t)(wire_button(btn) * 3U + gesture));
}

void vibe_app_on_button(bsp_btn_t btn, bsp_btn_ev_t ev)
{
    if (ev == BSP_BTN_PRESS) {
        vibe_ble_note_activity();
        if (!vibe_power_on_input()) s_swallow_click = true;
        return;
    }
    if (ev == BSP_BTN_LONG) {
        // A long press is reported at the threshold. Prevent a component
        // implementation that also emits CLICK on release from firing twice.
        s_swallow_click = true;
        report_gesture(btn, VIBE_GES_LONG);
        return;
    }
    if (ev == BSP_BTN_DOUBLE) {
        report_gesture(btn, VIBE_GES_DOUBLE);
        return;
    }
    if (ev != BSP_BTN_CLICK) return;
    if (s_swallow_click) {
        s_swallow_click = false;
        return;
    }
    vibe_power_on_input();
    vibe_ble_note_activity();
    report_gesture(btn, VIBE_GES_CLICK);
}

#define VIBE_NVS_NS   "vibe"
#define VIBE_NVS_KEY  "actions"

// Bindings live in NVS so the keys still describe themselves after a power
// cycle, instead of showing "--" until the bridge reconnects.
static void actions_load(void)
{
    nvs_handle_t h;
    if (nvs_open(VIBE_NVS_NS, NVS_READONLY, &h) != ESP_OK) return;
    uint8_t stored[VIBE_GESTURE_COUNT] = {0};
    size_t len = sizeof(stored);
    if (nvs_get_blob(h, VIBE_NVS_KEY, stored, &len) == ESP_OK && len == sizeof(stored)) {
        for (size_t i = 0; i < VIBE_GESTURE_COUNT; i++) {
            apply(VIBE_IN_ACTIONS, (uint32_t)i | ((uint32_t)stored[i] << 8));
        }
    }
    nvs_close(h);
}

static void actions_save(const uint8_t *actions, size_t len)
{
    if (len != VIBE_GESTURE_COUNT) return;
    nvs_handle_t h;
    if (nvs_open(VIBE_NVS_NS, NVS_READWRITE, &h) != ESP_OK) return;
    uint8_t prev[VIBE_GESTURE_COUNT] = {0};
    size_t prev_len = sizeof(prev);
    // Only write on a real change: NVS has a limited erase budget.
    bool same = nvs_get_blob(h, VIBE_NVS_KEY, prev, &prev_len) == ESP_OK &&
                prev_len == len && memcmp(prev, actions, len) == 0;
    if (!same) {
        nvs_set_blob(h, VIBE_NVS_KEY, actions, len);
        nvs_commit(h);
    }
    nvs_close(h);
}

void vibe_app_on_actions(const uint8_t *actions, size_t len)
{
    for (size_t i = 0; i < len && i < VIBE_GESTURE_COUNT; i++) {
        apply(VIBE_IN_ACTIONS, (uint32_t)i | ((uint32_t)actions[i] << 8));
    }
    actions_save(actions, len);
}

void vibe_app_on_ble_link(bool up)
{
    // Lets the power policy sleep early when nothing is connected.
    vibe_power_set_linked(up);
    if (up) vibe_power_note_activity();
    apply(up ? VIBE_IN_LINK_UP : VIBE_IN_LINK_DOWN, 0);
}

void vibe_app_on_audio_sub(bool sub)
{
    apply(sub ? VIBE_IN_AUDIO_SUB : VIBE_IN_AUDIO_UNSUB, 0);
    // A BLE link alone is not enough: the Mac is ready only after it has
    // subscribed to the audio characteristic. This also runs after a
    // light-sleep wake and gives the user a reliable ready indication.
    if (sub) vibe_audio_beep(VIBE_BEEP_READY);
}

void vibe_app_on_typeless(uint8_t state)
{
    apply(VIBE_IN_TYPELESS, state);
}

void vibe_app_on_power_mode(uint8_t mode)
{
    const vibe_power_mode_t m = mode > VIBE_POWER_ULTRA
        ? VIBE_POWER_STANDARD : (vibe_power_mode_t)mode;
    vibe_power_set_mode(m);
    // The radio only distinguishes "keep it easy to reach" from "wind down";
    // ultra shares eco's radio behaviour and differs in the timeouts.
    vibe_ble_set_power_mode(m != VIBE_POWER_STANDARD);
    // Mode changes arrive from the BLE control channel and otherwise would
    // only become visible on the next state transition.
    xSemaphoreTake(s_mu, portMAX_DELAY);
    publish_locked();
    xSemaphoreGive(s_mu);
}

void vibe_app_on_silence(void)
{
    apply(VIBE_IN_SILENCE, 0);
}

void vibe_app_note_peak(uint8_t level)
{
    xSemaphoreTake(s_mu, portMAX_DELAY);
    if (level > s_bar_max) s_bar_max = level;
    if (++s_bar_samples < 4) {
        xSemaphoreGive(s_mu);
        return;
    }

    // 每 4 个 20 ms 音频块合成为一根柱，保留瞬时峰值，波形更细且不抖。
    uint8_t frame = s_bar_max;
    s_bar_max = 0;
    s_bar_samples = 0;
    if (frame > 0) {
        s_tail_level = frame;
    } else if (s_tail_level > 0) {
        // 停止说话后快速渐隐，避免高电平红柱拖满整段历史。
        s_tail_level = s_tail_level > 2 ? s_tail_level - 2 : 0;
        frame = s_tail_level;
    }
    s_bars[s_bar_i] = frame;
    s_bar_i = (uint8_t)((s_bar_i + 1) % VIBE_UI_BARS);
    publish_locked();
    xSemaphoreGive(s_mu);
}
