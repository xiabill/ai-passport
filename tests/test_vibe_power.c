#include "vibe_power.h"

#include <assert.h>

int main(void)
{
    assert(vibe_power_next(VIBE_SCREEN_OFF, 0, true) == VIBE_SCREEN_BRIGHT);
    assert(vibe_power_next(VIBE_SCREEN_BRIGHT, 1000, false) == VIBE_SCREEN_BRIGHT);
    assert(vibe_power_next(VIBE_SCREEN_BRIGHT, VIBE_PWR_DIM_MS, false) == VIBE_SCREEN_DIM);
    assert(vibe_power_next(VIBE_SCREEN_DIM, VIBE_PWR_DIM_MS + 1000, false) == VIBE_SCREEN_DIM);
    assert(vibe_power_next(VIBE_SCREEN_DIM, VIBE_PWR_STANDBY_MS - 1, false) == VIBE_SCREEN_DIM);
    assert(vibe_power_next(VIBE_SCREEN_DIM, VIBE_PWR_STANDBY_MS, false) == VIBE_SCREEN_OFF);
    assert(vibe_power_next(VIBE_SCREEN_OFF, VIBE_PWR_STANDBY_MS, true) == VIBE_SCREEN_BRIGHT);
    assert(!vibe_power_should_deep_sleep(VIBE_PWR_DEEP_SLEEP_MS - 1, false));
    assert(vibe_power_should_deep_sleep(VIBE_PWR_DEEP_SLEEP_MS, false));
    assert(!vibe_power_should_deep_sleep(VIBE_PWR_DEEP_SLEEP_MS, true));
    assert(vibe_power_next_mode(VIBE_SCREEN_BRIGHT, VIBE_PWR_ECO_DIM_MS, false,
                                VIBE_POWER_ECO) == VIBE_SCREEN_DIM);
    assert(vibe_power_next_mode(VIBE_SCREEN_DIM, VIBE_PWR_ECO_STANDBY_MS, false,
                                VIBE_POWER_ECO) == VIBE_SCREEN_OFF);
    assert(!vibe_power_should_deep_sleep_mode(VIBE_PWR_ECO_DEEP_SLEEP_MS - 1, false,
                                              VIBE_POWER_ECO));
    assert(vibe_power_should_deep_sleep_mode(VIBE_PWR_ECO_DEEP_SLEEP_MS, false,
                                             VIBE_POWER_ECO));
    assert(!vibe_power_should_deep_sleep_mode(VIBE_PWR_ECO_DEEP_SLEEP_MS, true,
                                              VIBE_POWER_ECO));
    return 0;
}
