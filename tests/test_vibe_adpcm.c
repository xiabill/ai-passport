#include "vibe_adpcm.h"

#include <assert.h>
#include <stdint.h>
#include <string.h>

int main(void)
{
    vibe_adpcm_state_t st = {0, 0};
    int16_t pcm[4];
    uint8_t bytes[2] = {0x04, 0x0C};
    vibe_adpcm_decode(&st, bytes, 2, pcm);
    assert(pcm[0] == 7);
    assert(pcm[1] == 8);
    assert(pcm[2] == -1);

    int16_t src[8] = {0};
    uint8_t enc[4];
    int16_t roundtrip[8];
    vibe_adpcm_state_t enc_st = {0, 0};
    vibe_adpcm_state_t header = enc_st;
    vibe_adpcm_encode(&enc_st, src, 8, enc);
    vibe_adpcm_state_t dec_st = header;
    vibe_adpcm_decode(&dec_st, enc, 4, roundtrip);
    for (int i = 0; i < 8; i++) assert(roundtrip[i] == 0);
    return 0;
}
