#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VIBE_PWR_DIM_MS 18000U
#define VIBE_PWR_OFF_MS 60000U
#define VIBE_PWR_DEEP_SLEEP_MS (15U * 60U * 1000U)

typedef enum {
    VIBE_SCREEN_BRIGHT = 0,
    VIBE_SCREEN_DIM,
    VIBE_SCREEN_OFF,
} vibe_screen_t;

// Pure policy: busy (recording) stays bright; 18 s dim; 60 s backlight off.
vibe_screen_t vibe_power_next(vibe_screen_t cur, uint32_t idle_ms, bool busy);
// After 15 minutes idle, enter ESP32 deep sleep and wake on the function key.
bool vibe_power_should_deep_sleep(uint32_t idle_ms, bool busy);

void vibe_power_init(void);
void vibe_power_note_activity(void);
void vibe_power_set_busy(bool busy);
// Returns false if the press only woke a dark screen and must not run the app.
bool vibe_power_on_input(void);
void vibe_power_tick(void);
bool vibe_power_screen_on(void);

#ifdef __cplusplus
}
#endif
