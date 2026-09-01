#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// BLE audio block: 20 ms @ 16 kHz mono, IMA ADPCM 4-bit.
// Packet: [seq:u16 LE][predictor:s16 LE][step_index:u8][flags:u8][ADPCM 160B]
// flags bit0 = end-of-stream (payload omitted; packet is 6 bytes).
#define VIBE_AUDIO_HDR_LEN    6U
#define VIBE_AUDIO_ADPCM_LEN  160U
#define VIBE_AUDIO_PKT_LEN    (VIBE_AUDIO_HDR_LEN + VIBE_AUDIO_ADPCM_LEN)
#define VIBE_AUDIO_SAMPS      320
#define VIBE_AUDIO_HZ         16000
#define VIBE_FLAG_EOS         0x01U

#define VIBE_BLE_START  1U
#define VIBE_BLE_STOP   2U
#define VIBE_BLE_ENTER  3U
#define VIBE_BLE_CANCEL 4U
#define VIBE_BLE_DOUBAO_START 5U
#define VIBE_BLE_DOUBAO_STOP  6U
#define VIBE_BLE_DOUBAO_STOP_SEND 7U
#define VIBE_BLE_TYPELESS_TRANSLATE 8U
#define VIBE_BLE_TYPELESS_ASK       9U

#define VIBE_TL_IDLE       0U
#define VIBE_TL_RECORDING  1U
#define VIBE_TL_PROCESSING 2U
#define VIBE_TL_DOWN       3U

// Control characteristic values >= 0x80 are Bridge commands. Values 0..3
// remain reserved for Typeless state feedback.
#define VIBE_CTRL_POWER_MODE_STANDARD 0x80U
#define VIBE_CTRL_POWER_MODE_ECO      0x81U

void vibe_packet_pack(uint8_t *out, uint16_t seq, int16_t predictor,
                      uint8_t step_index, const uint8_t *adpcm);
void vibe_packet_eos(uint8_t *out, uint16_t seq);

typedef struct {
    uint16_t seq;
    int16_t predictor;
    uint8_t step_index;
    uint8_t flags;
    bool eos;
} vibe_packet_hdr_t;

// Returns false if `len` is not a data packet (166) or an EOS marker (6).
bool vibe_packet_parse_hdr(const uint8_t *pkt, size_t len, vibe_packet_hdr_t *hdr);

#ifdef __cplusplus
}
#endif
