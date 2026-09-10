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
    // Ultra mode is the thriftiest of the three.
    assert(vibe_power_next(VIBE_SCREEN_BRIGHT, VIBE_PWR_ULTRA_DIM_MS, false) == VIBE_SCREEN_BRIGHT);
    assert(vibe_power_next_mode(VIBE_SCREEN_BRIGHT, VIBE_PWR_ULTRA_DIM_MS, false,
                                VIBE_POWER_ULTRA) == VIBE_SCREEN_DIM);
    assert(vibe_power_next_mode(VIBE_SCREEN_DIM, VIBE_PWR_ULTRA_STANDBY_MS, false,
                                VIBE_POWER_ULTRA) == VIBE_SCREEN_OFF);
    assert(vibe_power_should_deep_sleep_mode(VIBE_PWR_ULTRA_DEEP_SLEEP_MS, false,
                                             VIBE_POWER_ULTRA));
    assert(!vibe_power_should_deep_sleep_mode(VIBE_PWR_ULTRA_DEEP_SLEEP_MS, false,
                                              VIBE_POWER_ECO));

    // A flat cell tightens the policy but never loosens it.
    assert(vibe_power_effective_mode(VIBE_POWER_STANDARD, 50) == VIBE_POWER_STANDARD);
    assert(vibe_power_effective_mode(VIBE_POWER_STANDARD, -1) == VIBE_POWER_STANDARD);
    assert(vibe_power_effective_mode(VIBE_POWER_STANDARD, 5) == VIBE_POWER_ECO);
    assert(vibe_power_effective_mode(VIBE_POWER_ULTRA, 5) == VIBE_POWER_ULTRA);

    // Busy always wins, even at 0%.
    assert(!vibe_power_should_deep_sleep_full(0, true, VIBE_POWER_STANDARD, 0, 0));
    // A critical battery sleeps immediately.
    assert(vibe_power_should_deep_sleep_full(0, false, VIBE_POWER_STANDARD, 0,
                                             VIBE_PWR_CRITICAL_BATTERY_PCT));
    assert(!vibe_power_should_deep_sleep_full(0, false, VIBE_POWER_STANDARD, 0,
                                              VIBE_PWR_CRITICAL_BATTERY_PCT + 1));
    // Nothing connected sleeps early, well before the idle timeout.
    assert(vibe_power_should_deep_sleep_full(1000, false, VIBE_POWER_STANDARD,
                                             VIBE_PWR_UNLINKED_DEEP_SLEEP_MS, 80));
    assert(!vibe_power_should_deep_sleep_full(1000, false, VIBE_POWER_STANDARD,
                                              VIBE_PWR_UNLINKED_DEEP_SLEEP_MS - 1, 80));
    // Connected and idle still honours the mode's own timeout.
    assert(!vibe_power_should_deep_sleep_full(VIBE_PWR_DEEP_SLEEP_MS - 1, false,
                                              VIBE_POWER_STANDARD, 0, 80));
    assert(vibe_power_should_deep_sleep_full(VIBE_PWR_DEEP_SLEEP_MS, false,
                                             VIBE_POWER_STANDARD, 0, 80));
    // A low battery makes a standard-mode device sleep on the eco timeout.
    assert(vibe_power_should_deep_sleep_full(VIBE_PWR_ECO_DEEP_SLEEP_MS, false,
                                             VIBE_POWER_STANDARD, 0, 5));
    // Unknown battery must not trigger the protection path.
    assert(!vibe_power_should_deep_sleep_full(0, false, VIBE_POWER_STANDARD, 0, -1));

    // The unlinked window has to outlast a reconnection attempt. At one minute
    // the device slept before the Bridge finished scanning, so waking it by hand
    // never helped: it was asleep again by the time the scan came round.
    assert(VIBE_PWR_UNLINKED_DEEP_SLEEP_MS >= 3U * 60U * 1000U);
    assert(!vibe_power_should_deep_sleep_full(1000, false, VIBE_POWER_STANDARD,
                                              90U * 1000U, 80));


    // --- charging inference -------------------------------------------------
    {
        vibe_charge_t c;
        vibe_charge_reset(&c);
        // A resting cell is not charging, however long it sits there.
        uint32_t now = 0;
        int fine = 50 * 256;
        for (int i = 0; i < 10; i++) {
            now += VIBE_CHARGE_SAMPLE_MS;
            vibe_charge_sample(&c, fine, now);
        }
        assert(!c.charging);
        assert(vibe_charge_minutes_to_full(&c) == -1);

        // Climbing 1%/min reads as charging, and 50% left at 1%/min is ~50 min.
        vibe_charge_reset(&c);
        now = 0;
        fine = 50 * 256;
        vibe_charge_sample(&c, fine, now);
        for (int i = 0; i < 6; i++) {
            now += 60000;
            fine += 256;
            vibe_charge_sample(&c, fine, now);
        }
        assert(c.charging);
        int mins = vibe_charge_minutes_to_full(&c);
        assert(mins > 35 && mins < 60);

        // Past the taper the estimate is withheld rather than guessed.
        vibe_charge_reset(&c);
        now = 0;
        fine = 95 * 256;
        vibe_charge_sample(&c, fine, now);
        for (int i = 0; i < 4; i++) {
            now += 60000;
            fine += 128;
            vibe_charge_sample(&c, fine, now);
        }
        assert(c.charging);
        assert(vibe_charge_minutes_to_full(&c) == -1);

        // Draining clears it again.
        for (int i = 0; i < 6; i++) {
            now += 60000;
            fine -= 256;
            vibe_charge_sample(&c, fine, now);
        }
        assert(!c.charging);

        // Samples that arrive too close together carry no usable slope.
        vibe_charge_reset(&c);
        vibe_charge_sample(&c, 50 * 256, 0);
        vibe_charge_sample(&c, 90 * 256, 100);
        assert(!c.charging);
    }

    return 0;
}
