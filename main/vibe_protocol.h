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

// Legacy semantic events 1..11. The firmware no longer emits these; they stay
// documented so a bridge can still understand an older device.
#define VIBE_BLE_START  1U
#define VIBE_BLE_STOP   2U
#define VIBE_BLE_ENTER  3U
// 4 is retired (legacy cancel). Do not reuse: old bridges map it to Escape.
#define VIBE_BLE_DOUBAO_START 5U
#define VIBE_BLE_DOUBAO_STOP  6U
#define VIBE_BLE_DOUBAO_STOP_SEND 7U
#define VIBE_BLE_TYPELESS_TRANSLATE 8U
#define VIBE_BLE_TYPELESS_ASK       9U
#define VIBE_BLE_DOUBAO_SELECT_ALL  10U
#define VIBE_BLE_DOUBAO_CLEAR       11U

#define VIBE_TL_IDLE       0U
#define VIBE_TL_RECORDING  1U
#define VIBE_TL_PROCESSING 2U
#define VIBE_TL_DOWN       3U

// Control characteristic values >= 0x80 are Bridge commands. Values 0..3
// remain reserved for Typeless state feedback.
#define VIBE_CTRL_POWER_MODE_STANDARD 0x80U
#define VIBE_CTRL_POWER_MODE_ECO      0x81U
#define VIBE_CTRL_POWER_MODE_ULTRA    0x82U

// Custom key labels, drawn by the Mac and sent as 8-bit alpha bitmaps so any
// text renders, not just the characters in the device's font subset.
//   0x93 slot off_lo off_hi data...   a chunk of the bitmap for one gesture
//   0x94 slot                          drop it and show the built-in name
// Slot is the gesture index (button * 3 + gesture). The size is fixed by the
// kind of slot, so it never travels on the wire.
#define VIBE_CTRL_LABEL       0x93U
#define VIBE_CTRL_LABEL_CLEAR 0x94U
// Sent by a Bridge right after it connects: "I mean to use this device".
// A second connection only takes the device over once it says so; anything
// that connects without asking (an old Bridge, a phone, the OS reconnecting
// on its own) is dropped instead of silently stealing the device.
#define VIBE_CTRL_CLAIM       0x95U
#define VIBE_CLAIM_WINDOW_MS  3000U
#define VIBE_LABEL_MAIN_W 64U
#define VIBE_LABEL_MAIN_H 20U
#define VIBE_LABEL_ALT_W  44U
#define VIBE_LABEL_ALT_H  16U

// Raw gesture events. The device no longer decides what a button means; it
// reports which button was pressed and how, and the bridge maps that to an
// action. Encoding: 0x20 | (button << 2) | gesture, i.e. 0x20..0x2A.
#define VIBE_GESTURE_COUNT 9
#define VIBE_BLE_GESTURE_BASE 0x20U
#define VIBE_BTN_UP    0U
#define VIBE_BTN_MID   1U
#define VIBE_BTN_DOWN  2U
#define VIBE_GES_CLICK  0U
#define VIBE_GES_DOUBLE 1U
#define VIBE_GES_LONG   2U
#define VIBE_GESTURE_EVENT(btn, ges) \
    ((uint8_t)(VIBE_BLE_GESTURE_BASE | ((btn) << 2) | (ges)))
#define VIBE_GESTURE_BIT(btn, ges) ((uint16_t)1U << ((btn) * 3U + (ges)))

// Control command: 0x91 followed by 9 action codes, one per gesture index
// (button * 3 + gesture). The device uses them for two things only: deciding
// whether a gesture arms the microphone, and labelling the on-screen key
// hints. Rebinding an action is a 10-byte write, never a reflash.
#define VIBE_CTRL_ACTIONS 0x91U
#define VIBE_CTRL_ACTIONS_LEN (1U + VIBE_GESTURE_COUNT)

#define VIBE_ACT_NONE       0U
#define VIBE_ACT_DICTATE    1U
#define VIBE_ACT_TRANSLATE  2U
#define VIBE_ACT_ASK        3U
#define VIBE_ACT_DOUBAO     4U
#define VIBE_ACT_ENTER      5U
#define VIBE_ACT_SELECT_ALL 6U
#define VIBE_ACT_CLEAR      7U
#define VIBE_ACT_NEWLINE    8U
#define VIBE_ACT_CUSTOM     9U
#define VIBE_ACT_HANDOFF    10U
#define VIBE_ACT_COUNT      11U

// Actions that must arm the microphone on the device itself.
#define VIBE_ACT_RECORDS(a) \
    ((a) == VIBE_ACT_DICTATE || (a) == VIBE_ACT_TRANSLATE || \
     (a) == VIBE_ACT_ASK || (a) == VIBE_ACT_DOUBAO)
// Of those, the ones backed by Typeless, whose transcript we must wait for.
#define VIBE_ACT_WAITS_TRANSCRIPT(a) \
    ((a) == VIBE_ACT_DICTATE || (a) == VIBE_ACT_TRANSLATE || (a) == VIBE_ACT_ASK)

// Two recording actions drive the same input method when they are the same
// action, or when both are Typeless modes. Only a gesture from the same input
// method may end a take; pressing the other one is ignored so a mistaken press
// cannot cut a recording short.
#define VIBE_ACT_SAME_INPUT(a, b) \
    ((a) == (b) || (VIBE_ACT_WAITS_TRANSCRIPT(a) && VIBE_ACT_WAITS_TRANSCRIPT(b)))

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
