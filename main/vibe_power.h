#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VIBE_PWR_DIM_MS 18000U
#define VIBE_PWR_STANDBY_MS (5U * 60U * 1000U)
#define VIBE_PWR_OFF_MS VIBE_PWR_STANDBY_MS
#define VIBE_PWR_DEEP_SLEEP_MS (15U * 60U * 1000U)
#define VIBE_PWR_BUSY_DIM_MS (3U * 1000U)
#define VIBE_PWR_ECO_DIM_MS (10U * 1000U)
#define VIBE_PWR_ECO_STANDBY_MS (1U * 60U * 1000U)
#define VIBE_PWR_ECO_DEEP_SLEEP_MS (5U * 60U * 1000U)

typedef enum {
    VIBE_POWER_STANDARD = 0,
    VIBE_POWER_ECO = 1,
} vibe_power_mode_t;

typedef enum {
    VIBE_SCREEN_BRIGHT = 0,
    VIBE_SCREEN_DIM,
    VIBE_SCREEN_OFF,
} vibe_screen_t;

// Standard policy: busy stays bright; 18 s dim; 5 min standby.
vibe_screen_t vibe_power_next(vibe_screen_t cur, uint32_t idle_ms, bool busy);
vibe_screen_t vibe_power_next_mode(vibe_screen_t cur, uint32_t idle_ms, bool busy,
                                   vibe_power_mode_t mode);
// Standard policy enters deep sleep after 15 minutes; Eco uses its shorter
// timeout. Both modes wake on the GPIO0 function key.
bool vibe_power_should_deep_sleep(uint32_t idle_ms, bool busy);
bool vibe_power_should_deep_sleep_mode(uint32_t idle_ms, bool busy,
                                       vibe_power_mode_t mode);

void vibe_power_init(void);
void vibe_power_set_mode(vibe_power_mode_t mode);
vibe_power_mode_t vibe_power_mode(void);
void vibe_power_note_activity(void);
void vibe_power_set_busy(bool busy);
// Returns false if the press only woke a dark screen and must not run the app.
bool vibe_power_on_input(void);
void vibe_power_tick(void);
bool vibe_power_screen_on(void);

#ifdef __cplusplus
}
#endif
