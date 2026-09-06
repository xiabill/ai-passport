#pragma once

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

// Serves the FAP_SCREENSHOT_V1 serial protocol used by the community
// publisher: it answers a request on the console with the live display
// contents. Observational only — it never reboots, flashes, or alters state.
esp_err_t vibe_shot_start(void);

#ifdef __cplusplus
}
#endif
