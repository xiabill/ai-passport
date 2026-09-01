#include "vibe_power.h"

#ifndef VIBE_POWER_HOST_TEST
#include "bsp_display.h"
#include "esp_log.h"
#include "esp_sleep.h"
#include "esp_timer.h"
#include "driver/gpio.h"
#endif

#define BACKLIGHT_BRIGHT 100
#define BACKLIGHT_DIM 20

vibe_screen_t vibe_power_next_mode(vibe_screen_t cur, uint32_t idle_ms, bool busy,
                                   vibe_power_mode_t mode)
{
    (void)cur;
    if (busy) return VIBE_SCREEN_BRIGHT;
    const uint32_t dim_ms = mode == VIBE_POWER_ECO ? VIBE_PWR_ECO_DIM_MS : VIBE_PWR_DIM_MS;
    const uint32_t standby_ms = mode == VIBE_POWER_ECO ? VIBE_PWR_ECO_STANDBY_MS : VIBE_PWR_STANDBY_MS;
    if (idle_ms >= standby_ms) return VIBE_SCREEN_OFF;
    if (idle_ms >= dim_ms) return VIBE_SCREEN_DIM;
    return VIBE_SCREEN_BRIGHT;
}

vibe_screen_t vibe_power_next(vibe_screen_t cur, uint32_t idle_ms, bool busy)
{
    return vibe_power_next_mode(cur, idle_ms, busy, VIBE_POWER_STANDARD);
}

bool vibe_power_should_deep_sleep_mode(uint32_t idle_ms, bool busy,
                                       vibe_power_mode_t mode)
{
    const uint32_t timeout = mode == VIBE_POWER_ECO
        ? VIBE_PWR_ECO_DEEP_SLEEP_MS : VIBE_PWR_DEEP_SLEEP_MS;
    return !busy && idle_ms >= timeout;
}

bool vibe_power_should_deep_sleep(uint32_t idle_ms, bool busy)
{
    return vibe_power_should_deep_sleep_mode(idle_ms, busy, VIBE_POWER_STANDARD);
}

#ifndef VIBE_POWER_HOST_TEST

static const char *TAG = "vibe_pwr";
static vibe_screen_t s_screen = VIBE_SCREEN_BRIGHT;
static bool s_busy;
static uint32_t s_last_ms;
static bool s_deep_sleep_failed;
static vibe_power_mode_t s_mode = VIBE_POWER_STANDARD;

static uint32_t now_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

static void apply_screen(vibe_screen_t next)
{
    if (next == s_screen) return;
    s_screen = next;
    switch (next) {
    case VIBE_SCREEN_BRIGHT:
        bsp_display_backlight(BACKLIGHT_BRIGHT);
        ESP_LOGI(TAG, "backlight 100");
        break;
    case VIBE_SCREEN_DIM:
        bsp_display_backlight(BACKLIGHT_DIM);
        ESP_LOGI(TAG, "backlight 20");
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

    bsp_display_backlight(0);
    const uint32_t timeout = s_mode == VIBE_POWER_ECO
        ? VIBE_PWR_ECO_DEEP_SLEEP_MS : VIBE_PWR_DEEP_SLEEP_MS;
    ESP_LOGI(TAG, "idle for %u ms; entering deep sleep; wake on GPIO0",
             timeout);
    esp_deep_sleep_start();
}

void vibe_power_init(void)
{
    s_busy = false;
    s_last_ms = now_ms();
    s_screen = VIBE_SCREEN_BRIGHT;
    s_mode = VIBE_POWER_STANDARD;
    bsp_display_backlight(BACKLIGHT_BRIGHT);
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
    if (s_busy) s_last_ms = now;
    uint32_t idle = now - s_last_ms;
    apply_screen(vibe_power_next_mode(s_screen, idle, s_busy, s_mode));
    if (!s_deep_sleep_failed && vibe_power_should_deep_sleep_mode(idle, s_busy, s_mode)) {
        enter_deep_sleep();
    }
}

bool vibe_power_screen_on(void)
{
    return s_screen != VIBE_SCREEN_OFF;
}

#endif
