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

// The board has no charge-detect line, so charging is inferred from the fuel
// gauge: the reading climbs when current is going in and falls when it is not.
// The gauge exposes 1/256 of a percent, which moves every few seconds while
// charging, so the state settles far sooner than whole percents would allow.
#define VIBE_CHARGE_FULL_FINE 25600          // 100% in 1/256 units
#define VIBE_CHARGE_SAMPLE_MS (20U * 1000U)  // one I2C read every 20s is plenty
// Below this the reading is drifting, not charging. A resting cell wanders by a
// few units either way.
#define VIBE_CHARGE_MIN_RATE 8               // 1/256 %/min, ~0.03 %/min
// Past this point the charger tapers off and a linear estimate turns into a
// lie, so the remaining time is withheld rather than guessed.
#define VIBE_CHARGE_TAPER_FINE (92 * 256)

typedef struct {
    int32_t last_fine;   // most recent reading, -1 before the first sample
    uint32_t last_ms;
    int32_t rate;        // 1/256 %% per minute, smoothed; positive when charging
    bool charging;
} vibe_charge_t;

void vibe_charge_reset(vibe_charge_t *c);

// Feeds one gauge reading. Ignores samples that arrive too close together to
// carry a usable slope.
void vibe_charge_sample(vibe_charge_t *c, int soc_fine, uint32_t now_ms);

// Minutes until full, or -1 when that cannot be stated honestly: not charging,
// no rate yet, or already into the taper where a linear estimate misleads.
int vibe_charge_minutes_to_full(const vibe_charge_t *c);

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
