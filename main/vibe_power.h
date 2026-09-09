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
#define VIBE_PWR_ULTRA_DIM_MS (5U * 1000U)
#define VIBE_PWR_ULTRA_STANDBY_MS (30U * 1000U)
#define VIBE_PWR_ULTRA_DEEP_SLEEP_MS (2U * 60U * 1000U)

// Nothing connected means nobody is nearby, so there is no point waiting out
// the full idle timeout before sleeping.
#define VIBE_PWR_UNLINKED_DEEP_SLEEP_MS (5U * 60U * 1000U)

// Draining a lithium cell flat costs it capacity permanently, so the policy
// tightens on its own well before that point.
#define VIBE_PWR_LOW_BATTERY_PCT 10
#define VIBE_PWR_CRITICAL_BATTERY_PCT 3

typedef enum {
    VIBE_POWER_STANDARD = 0,
    VIBE_POWER_ECO = 1,
    VIBE_POWER_ULTRA = 2,
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
// A USB host connection disables automatic dimming, screen-off, and deep sleep
// for as long as the host is present. Charge-only power cannot be detected on
// this board because no VBUS/charger-status signal is connected to the MCU.
bool vibe_power_should_deep_sleep(uint32_t idle_ms, bool busy);
bool vibe_power_should_deep_sleep_mode(uint32_t idle_ms, bool busy,
                                       vibe_power_mode_t mode);

// Full policy. `unlinked_ms` is how long no Mac has been connected, and
// `battery` is 0..100 or -1 when unknown.
bool vibe_power_should_deep_sleep_full(uint32_t idle_ms, bool busy,
                                       vibe_power_mode_t mode,
                                       uint32_t unlinked_ms, int battery);

// A flat battery forces a thriftier policy than the user picked. Never returns
// a laxer mode than the one passed in.
vibe_power_mode_t vibe_power_effective_mode(vibe_power_mode_t mode, int battery);

// Told by the app whenever the BLE link comes up or goes away.
void vibe_power_set_linked(bool linked);

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
