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

vibe_screen_t vibe_power_next(vibe_screen_t cur, uint32_t idle_ms, bool busy)
{
    (void)cur;
    if (busy) return VIBE_SCREEN_BRIGHT;
    if (idle_ms >= VIBE_PWR_OFF_MS) return VIBE_SCREEN_OFF;
    if (idle_ms >= VIBE_PWR_DIM_MS) return VIBE_SCREEN_DIM;
    return VIBE_SCREEN_BRIGHT;
}

bool vibe_power_should_deep_sleep(uint32_t idle_ms, bool busy)
{
    return !busy && idle_ms >= VIBE_PWR_DEEP_SLEEP_MS;
}

#ifndef VIBE_POWER_HOST_TEST

static const char *TAG = "vibe_pwr";
static vibe_screen_t s_screen = VIBE_SCREEN_BRIGHT;
static bool s_busy;
static uint32_t s_last_ms;
static bool s_deep_sleep_failed;

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
    // button a low level, so it can wake the C3 from deep sleep.
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
    ESP_LOGI(TAG, "idle for %u ms; entering deep sleep, wake on GPIO0",
             VIBE_PWR_DEEP_SLEEP_MS);
    esp_deep_sleep_start();
}

void vibe_power_init(void)
{
    s_busy = false;
    s_last_ms = now_ms();
    s_screen = VIBE_SCREEN_BRIGHT;
    bsp_display_backlight(BACKLIGHT_BRIGHT);
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
    apply_screen(vibe_power_next(s_screen, idle, s_busy));
    if (!s_deep_sleep_failed && vibe_power_should_deep_sleep(idle, s_busy)) {
        enter_deep_sleep();
    }
}

bool vibe_power_screen_on(void)
{
    return s_screen != VIBE_SCREEN_OFF;
}

#endif
