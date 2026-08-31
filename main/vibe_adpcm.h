#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// IMA ADPCM (DVI4) 4-bit encoder/decoder. CPU cost is negligible on ESP32-C3.
typedef struct {
    int16_t predictor;
    int8_t step_index;
} vibe_adpcm_state_t;

// Encodes `count` samples (`count` must be even) into count/2 bytes.
// Snapshot `state` *before* the call; that snapshot is the BLE packet header.
void vibe_adpcm_encode(vibe_adpcm_state_t *state, const int16_t *pcm, int count,
                       uint8_t *out);

// Decodes `nbytes` ADPCM bytes into nbytes*2 PCM samples. Used by host tests
// and kept next to the encoder so both sides share one step table.
void vibe_adpcm_decode(vibe_adpcm_state_t *state, const uint8_t *in, int nbytes,
                       int16_t *pcm);

#ifdef __cplusplus
}
#endif
