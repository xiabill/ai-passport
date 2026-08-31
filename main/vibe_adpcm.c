#include "vibe_adpcm.h"

static const int16_t k_step_table[89] = {
    7,     8,     9,     10,    11,    12,    13,    14,    16,    17,    19,
    21,    23,    25,    28,    31,    34,    37,    41,    45,    50,    55,
    60,    66,    73,    80,    88,    97,    107,   118,   130,   143,   157,
    173,   190,   209,   230,   253,   279,   307,   337,   371,   408,   449,
    494,   544,   598,   658,   724,   796,   876,   963,   1060,  1166,  1282,
    1411,  1552,  1707,  1878,  2066,  2272,  2499,  2749,  3024,  3327,  3660,
    4026,  4428,  4871,  5358,  5894,  6484,  7132,  7845,  8630,  9493,  10442,
    11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794,
    32767};

static const int8_t k_index_table[16] = {
    -1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8};

static int clamp_pred(int predictor)
{
    if (predictor > 32767) return 32767;
    if (predictor < -32768) return -32768;
    return predictor;
}

static int clamp_index(int index)
{
    if (index < 0) return 0;
    if (index > 88) return 88;
    return index;
}

static uint8_t encode_sample(vibe_adpcm_state_t *st, int16_t sample)
{
    int step = k_step_table[st->step_index];
    int diff = sample - st->predictor;
    uint8_t code = 0;
    if (diff < 0) {
        code = 8;
        diff = -diff;
    }

    int diffq = step >> 3;
    if (diff >= step) {
        code |= 4;
        diff -= step;
        diffq += step;
    }
    step >>= 1;
    if (diff >= step) {
        code |= 2;
        diff -= step;
        diffq += step;
    }
    step >>= 1;
    if (diff >= step) {
        code |= 1;
        diffq += step;
    }

    int predictor = st->predictor + ((code & 8) ? -diffq : diffq);
    st->predictor = (int16_t)clamp_pred(predictor);
    st->step_index = (int8_t)clamp_index(st->step_index + k_index_table[code]);
    return code;
}

static int16_t decode_nibble(vibe_adpcm_state_t *st, uint8_t nibble)
{
    int step = k_step_table[st->step_index];
    int diffq = step >> 3;
    if (nibble & 1) diffq += step >> 2;
    if (nibble & 2) diffq += step >> 1;
    if (nibble & 4) diffq += step;

    int predictor = st->predictor + ((nibble & 8) ? -diffq : diffq);
    st->predictor = (int16_t)clamp_pred(predictor);
    st->step_index = (int8_t)clamp_index(st->step_index + k_index_table[nibble]);
    return st->predictor;
}

void vibe_adpcm_encode(vibe_adpcm_state_t *state, const int16_t *pcm, int count,
                       uint8_t *out)
{
    for (int i = 0; i < count; i += 2) {
        uint8_t lo = encode_sample(state, pcm[i]);
        uint8_t hi = encode_sample(state, pcm[i + 1]);
        out[i / 2] = (uint8_t)(lo | (hi << 4));
    }
}

void vibe_adpcm_decode(vibe_adpcm_state_t *state, const uint8_t *in, int nbytes,
                       int16_t *pcm)
{
    int o = 0;
    for (int i = 0; i < nbytes; i++) {
        pcm[o++] = decode_nibble(state, (uint8_t)(in[i] & 0x0F));
        pcm[o++] = decode_nibble(state, (uint8_t)(in[i] >> 4));
    }
}
