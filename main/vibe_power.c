#include "vibe_power.h"

#ifndef VIBE_POWER_HOST_TEST
#include "bsp_display.h"
#include "esp_log.h"
#include "esp_timer.h"
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

#ifndef VIBE_POWER_HOST_TEST

static const char *TAG = "vibe_pwr";
static vibe_screen_t s_screen = VIBE_SCREEN_BRIGHT;
static bool s_busy;
static uint32_t s_last_ms;

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
}

bool vibe_power_screen_on(void)
{
    return s_screen != VIBE_SCREEN_OFF;
}

#endif
