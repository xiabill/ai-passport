#include "vibe_power.h"

#ifndef VIBE_POWER_HOST_TEST
#include "bsp_battery.h"
#include "bsp_display.h"
#include "bsp_audio.h"
#include "esp_log.h"
#include "esp_lcd_panel_ops.h"
#include "esp_sleep.h"
#include "esp_timer.h"
#include "driver/gpio.h"
#include "driver/usb_serial_jtag.h"
#include "vibe_ble.h"
#endif

#define BACKLIGHT_STANDARD 50
#define BACKLIGHT_BRIGHT 100
#define BACKLIGHT_DIM 15
#define BACKLIGHT_ECO_DIM 8

static uint32_t dim_ms_for(vibe_power_mode_t mode)
{
    switch (mode) {
    case VIBE_POWER_ULTRA: return VIBE_PWR_ULTRA_DIM_MS;
    case VIBE_POWER_ECO: return VIBE_PWR_ECO_DIM_MS;
    default: return VIBE_PWR_DIM_MS;
    }
}

static uint32_t standby_ms_for(vibe_power_mode_t mode)
{
    switch (mode) {
    case VIBE_POWER_ULTRA: return VIBE_PWR_ULTRA_STANDBY_MS;
    case VIBE_POWER_ECO: return VIBE_PWR_ECO_STANDBY_MS;
    default: return VIBE_PWR_STANDBY_MS;
    }
}

vibe_screen_t vibe_power_next_mode(vibe_screen_t cur, uint32_t idle_ms, bool busy,
                                   vibe_power_mode_t mode)
{
    (void)cur;
    if (busy) return VIBE_SCREEN_BRIGHT;
    const uint32_t dim_ms = dim_ms_for(mode);
    const uint32_t standby_ms = standby_ms_for(mode);
    if (idle_ms >= standby_ms) return VIBE_SCREEN_OFF;
    if (idle_ms >= dim_ms) return VIBE_SCREEN_DIM;
    return VIBE_SCREEN_BRIGHT;
}

vibe_screen_t vibe_power_next(vibe_screen_t cur, uint32_t idle_ms, bool busy)
{
    return vibe_power_next_mode(cur, idle_ms, busy, VIBE_POWER_STANDARD);
}

static uint32_t deep_sleep_ms_for(vibe_power_mode_t mode)
{
    switch (mode) {
    case VIBE_POWER_ULTRA: return VIBE_PWR_ULTRA_DEEP_SLEEP_MS;
    case VIBE_POWER_ECO: return VIBE_PWR_ECO_DEEP_SLEEP_MS;
    default: return VIBE_PWR_DEEP_SLEEP_MS;
    }
}

bool vibe_power_should_deep_sleep_mode(uint32_t idle_ms, bool busy,
                                       vibe_power_mode_t mode)
{
    return !busy && idle_ms >= deep_sleep_ms_for(mode);
}

vibe_power_mode_t vibe_power_effective_mode(vibe_power_mode_t mode, int battery)
{
    if (battery < 0 || battery > VIBE_PWR_LOW_BATTERY_PCT) return mode;
    return mode > VIBE_POWER_ECO ? mode : VIBE_POWER_ECO;
}

bool vibe_power_should_deep_sleep_full(uint32_t idle_ms, bool busy,
                                       vibe_power_mode_t mode,
                                       uint32_t unlinked_ms, int battery)
{
    if (busy) return false;
    // A nearly flat cell outranks every other consideration.
    if (battery >= 0 && battery <= VIBE_PWR_CRITICAL_BATTERY_PCT) return true;
    if (unlinked_ms >= VIBE_PWR_UNLINKED_DEEP_SLEEP_MS) return true;
    return idle_ms >= deep_sleep_ms_for(vibe_power_effective_mode(mode, battery));
}

bool vibe_power_should_deep_sleep(uint32_t idle_ms, bool busy)
{
    return vibe_power_should_deep_sleep_mode(idle_ms, busy, VIBE_POWER_STANDARD);
}

#ifndef VIBE_POWER_HOST_TEST

static const char *TAG = "vibe_pwr";
static vibe_screen_t s_screen = VIBE_SCREEN_BRIGHT;
static bool s_busy;
static uint32_t s_busy_since_ms;
static uint32_t s_last_ms;
static bool s_deep_sleep_failed;
static vibe_power_mode_t s_mode = VIBE_POWER_STANDARD;
static bool s_usb_host_powered;
static bool s_linked;
static uint32_t s_unlinked_since_ms;

static uint32_t now_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}



static void apply_screen(vibe_screen_t next)
{
    if (next == s_screen) return;
    s_screen = next;
    const uint8_t bright_level = s_mode == VIBE_POWER_ECO ? BACKLIGHT_BRIGHT : BACKLIGHT_STANDARD;
    const uint8_t dim_level = s_mode == VIBE_POWER_ECO ? BACKLIGHT_ECO_DIM : BACKLIGHT_DIM;
    switch (next) {
    case VIBE_SCREEN_BRIGHT:
        bsp_display_backlight(bright_level);
        ESP_LOGI(TAG, "backlight %u", bright_level);
        break;
    case VIBE_SCREEN_DIM:
        bsp_display_backlight(dim_level);
        ESP_LOGI(TAG, "backlight %u", dim_level);
        break;
    case VIBE_SCREEN_OFF:
        bsp_display_backlight(0);
        ESP_LOGI(TAG, "backlight off");
        break;
    }
}

static void enter_deep_sleep(void)
{
    // GPIO0 is the ADC button ladder: the external pull-up makes a pressed
    // button a low level, so any ordinary function key can wake the C3.
    gpio_config_t wake_cfg = {
        .pin_bit_mask = 1ULL << GPIO_NUM_0,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    esp_err_t err = gpio_config(&wake_cfg);
    if (err == ESP_OK) {
        err = esp_deep_sleep_enable_gpio_wakeup(
            1ULL << GPIO_NUM_0, ESP_GPIO_WAKEUP_GPIO_LOW);
    }
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "deep sleep wake setup failed: %s", esp_err_to_name(err));
        s_deep_sleep_failed = true;
        return;
    }

    // Deep sleep is a reboot-level transition, so close peripherals that do
    // not have a wake-time resume path. This also covers the fallback path
    // when light sleep setup was unavailable.
    bsp_audio_suspend();
    vibe_ble_prepare_light_sleep();
    esp_lcd_panel_handle_t panel = bsp_display_panel();
    if (panel) {
        // A dark screen is not a powered-down one. Backlight PWM alone leaves
        // the ST7789 running; DISP OFF stops its scan, and sleep-in puts the
        // controller itself down. The boot path turns both back on.
        esp_lcd_panel_disp_on_off(panel, false);
        esp_lcd_panel_disp_sleep(panel, true);
    }
    bsp_display_backlight(0);
    // Deep sleep only powers down the MCU core; anything on the always-on 3.3V
    // rail keeps drawing unless it is told to stop. The fuel gauge is the last
    // one that can still be reached from software.
    bsp_battery_sleep();
    const uint32_t timeout = s_mode == VIBE_POWER_ECO
        ? VIBE_PWR_ECO_DEEP_SLEEP_MS : VIBE_PWR_DEEP_SLEEP_MS;
    ESP_LOGI(TAG, "idle for %u ms; entering deep sleep; wake on GPIO0",
             timeout);
    esp_deep_sleep_start();
}

// Enter a real idle state after the screen has gone dark. A timer wake keeps
// the existing 15-minute/5-minute deep-sleep policy, while GPIO0 wakes the
// device immediately on a function-key press.
void vibe_power_init(void)
{
    s_busy = false;
    s_busy_since_ms = 0;
    s_last_ms = now_ms();
    s_screen = VIBE_SCREEN_BRIGHT;
    s_mode = VIBE_POWER_STANDARD;
    s_usb_host_powered = false;
    s_linked = false;
    s_unlinked_since_ms = now_ms();
    bsp_display_backlight(BACKLIGHT_BRIGHT);
}

void vibe_power_set_linked(bool linked)
{
    if (linked == s_linked) return;
    s_linked = linked;
    if (!linked) s_unlinked_since_ms = now_ms();
}

void vibe_power_set_mode(vibe_power_mode_t mode)
{
    if (mode != VIBE_POWER_ECO) mode = VIBE_POWER_STANDARD;
    if (s_mode == mode) return;
    s_mode = mode;
    // Changing the profile is itself activity. Give the user a full timeout
    // window after switching, rather than sleeping immediately on an old idle.
    vibe_power_note_activity();
    ESP_LOGI(TAG, "power mode %s", mode == VIBE_POWER_ECO ? "eco" : "standard");
}

vibe_power_mode_t vibe_power_mode(void)
{
    return s_mode;
}

void vibe_power_note_activity(void)
{
    s_last_ms = now_ms();
    s_deep_sleep_failed = false;
    apply_screen(VIBE_SCREEN_BRIGHT);
}

void vibe_power_set_busy(bool busy)
{
    if (busy && !s_busy) s_busy_since_ms = now_ms();
    s_busy = busy;
    if (busy) vibe_power_note_activity();
}

bool vibe_power_on_input(void)
{
    bool was_off = s_screen == VIBE_SCREEN_OFF;
    vibe_power_note_activity();
    return !was_off;
}

void vibe_power_tick(void)
{
    uint32_t now = now_ms();

    // USB Serial/JTAG reports a host only when it sees USB SOF packets. This
    // reliably identifies a computer connection without confusing a
    // charge-only cable or power bank with a data host.
    bool usb_host_powered = usb_serial_jtag_is_connected();
    if (usb_host_powered) {
        if (!s_usb_host_powered) {
            ESP_LOGI(TAG, "USB host connected; automatic power saving disabled");
        }
        s_usb_host_powered = true;
        s_last_ms = now;
        s_deep_sleep_failed = false;
        apply_screen(VIBE_SCREEN_BRIGHT);
        return;
    }
    if (s_usb_host_powered) {
        ESP_LOGI(TAG, "USB host disconnected; automatic power saving resumed");
        s_usb_host_powered = false;
        s_last_ms = now;
    }

    if (s_busy) s_last_ms = now;
    uint32_t idle = now - s_last_ms;
    vibe_screen_t next = vibe_power_next_mode(s_screen, idle, s_busy, s_mode);
    if (s_busy && now - s_busy_since_ms >= VIBE_PWR_BUSY_DIM_MS) {
        // While speaking, the user already knows the device is working. Keep
        // a small visual cue without leaving the display at full brightness.
        next = VIBE_SCREEN_DIM;
    }
    apply_screen(next);

    // Light sleep used to bridge screen-off and deep sleep, but it stopped the
    // radio: the device was unreachable for the whole stretch and still burning
    // current. Deep sleep is equally unreachable and actually saves power, so the
    // middle state earned nothing. Blank the screen, keep the radio up, and wait
    // for the deep-sleep deadline.
    const int battery = bsp_battery_soc();
    const uint32_t unlinked = s_linked ? 0 : (now - s_unlinked_since_ms);
    if (!s_deep_sleep_failed &&
        vibe_power_should_deep_sleep_full(idle, s_busy, s_mode, unlinked, battery)) {
        if (battery >= 0 && battery <= VIBE_PWR_CRITICAL_BATTERY_PCT) {
            ESP_LOGW(TAG, "battery at %d%%; sleeping to protect the cell", battery);
        } else if (unlinked >= VIBE_PWR_UNLINKED_DEEP_SLEEP_MS) {
            ESP_LOGI(TAG, "nothing connected for %u ms; sleeping early", unlinked);
        }
        enter_deep_sleep();
    }
}

bool vibe_power_screen_on(void)
{
    return s_screen != VIBE_SCREEN_OFF;
}

#endif
