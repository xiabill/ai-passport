#include "vibe_app.h"
#include "vibe_audio.h"
#include "vibe_ble.h"
#include "vibe_power.h"
#include "vibe_state.h"
#include "vibe_ui.h"

#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

static const char *TAG = "vibe_app";

#define PROC_TIMEOUT_US (8 * 1000 * 1000)

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

static void apply(vibe_in_t in, uint8_t typeless_byte);

static void publish_locked(void)
{
    vibe_ui_model_t m = {0};
    m.phase = s_st.phase;
    m.source = s_st.source;
    m.linked = s_st.linked;
    m.audio_sub = s_st.audio_sub;
    m.queued_enter = s_st.queued_enter;
    m.typeless = s_st.typeless;
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

static void apply(vibe_in_t in, uint8_t typeless_byte)
{
    xSemaphoreTake(s_mu, portMAX_DELAY);
    vibe_out_t o = vibe_state_apply(&s_st, in, typeless_byte);
    bool processing = s_st.phase == VIBE_PHASE_PROCESSING;
    if (o.n_events) s_last_event = o.ble_events[o.n_events - 1];
    publish_locked();
    xSemaphoreGive(s_mu);

    if (o.start_capture) {
        vibe_audio_set_recording(true);
        vibe_power_set_busy(true);
        vibe_ble_link_fast(true);
    }
    if (o.stop_capture) {
        vibe_audio_set_recording(false);
        vibe_power_set_busy(false);
        vibe_ble_link_fast(false);
        vibe_power_note_activity();
    }
    for (uint8_t i = 0; i < o.n_events; i++) {
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

    vibe_power_init();
    vibe_ui_start();
    err = vibe_audio_start();
    if (err != ESP_OK) return err;
    err = vibe_ble_start();
    if (err != ESP_OK) return err;
    ESP_LOGI(TAG, "vibe app ready");
    return ESP_OK;
}

void vibe_app_on_button(bsp_btn_t btn, bsp_btn_ev_t ev)
{
    if (ev == BSP_BTN_PRESS) {
        vibe_audio_beep();
        vibe_ble_note_activity();
        if (!vibe_power_on_input()) s_swallow_click = true;
        return;
    }
    if (ev == BSP_BTN_LONG) {
        // A long press is reported at the threshold. Prevent a component
        // implementation that also emits CLICK on release from firing twice.
        s_swallow_click = true;
        if (btn == BSP_BTN_OK) apply(VIBE_IN_OK_LONG, 0);
        return;
    }
    if (ev == BSP_BTN_DOUBLE) {
        if (btn == BSP_BTN_OK) apply(VIBE_IN_OK_DOUBLE, 0);
        return;
    }
    if (ev != BSP_BTN_CLICK) return;
    if (s_swallow_click) {
        s_swallow_click = false;
        return;
    }
    vibe_power_on_input();
    vibe_ble_note_activity();
    if (btn == BSP_BTN_OK) apply(VIBE_IN_OK, 0);
    else if (btn == BSP_BTN_DOWN) apply(VIBE_IN_DOWN, 0);
    else if (btn == BSP_BTN_UP) apply(VIBE_IN_UP, 0);
}

void vibe_app_on_ble_link(bool up)
{
    if (up) vibe_power_note_activity();
    apply(up ? VIBE_IN_LINK_UP : VIBE_IN_LINK_DOWN, 0);
}

void vibe_app_on_audio_sub(bool sub)
{
    apply(sub ? VIBE_IN_AUDIO_SUB : VIBE_IN_AUDIO_UNSUB, 0);
}

void vibe_app_on_typeless(uint8_t state)
{
    apply(VIBE_IN_TYPELESS, state);
}

void vibe_app_on_power_mode(uint8_t mode)
{
    const bool eco = mode == VIBE_POWER_ECO;
    vibe_power_set_mode(eco ? VIBE_POWER_ECO : VIBE_POWER_STANDARD);
    vibe_ble_set_power_mode(eco);
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
