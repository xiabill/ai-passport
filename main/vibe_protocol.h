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

// Control characteristic values >= 0x80 are Bridge commands.
// Sent on the event channel to the Mac that is losing the device, right
// before its link is cut, so it can say what happened instead of reporting a
// bare disconnect. Outside the gesture range (0x20..0x2B) and the legacy
// events (1..11).
#define VIBE_EV_HANDED_OVER 0x7EU
// Battery report on the event channel: 0x7D, percent (0..100 or 0xFF unknown),
// flags (bit 0 charging). Sent when either changes, and once per new link, so
// the Mac can show every device's battery without polling.
#define VIBE_EV_BATTERY     0x7DU
#define VIBE_EV_BATTERY_CHARGING 0x01U

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
// Play a cue: 0x97 then the cue. For the sounds only the Mac can decide on —
// the device does not know which key a gesture sends, so it cannot tell a
// Return from any other key.
#define VIBE_CTRL_CUE         0x97U
#define VIBE_CUE_SEND         1U
#define VIBE_CUE_EDIT         2U
// Cue volume: 0x98, level (0 silent .. 4 loudest), flags. With bit 0 of the
// flags set the device plays a sample at the new level, which is what the Mac
// asks for when the user changes it — but not when it merely syncs on connect.
#define VIBE_CTRL_VOLUME      0x98U
#define VIBE_VOLUME_LEVELS    5U
#define VIBE_VOLUME_PREVIEW   0x01U
// Twenty seconds, not three: a Mac needs four to six just to discover the
// service and its characteristics before it can ask for anything, so a short
// window dropped every newcomer before it could speak.
#define VIBE_CLAIM_WINDOW_MS  20000U
#define VIBE_LABEL_MAIN_W 64U
#define VIBE_LABEL_MAIN_H 20U
#define VIBE_LABEL_ALT_W  44U
#define VIBE_LABEL_ALT_H  16U
// One extra label slot past the nine gestures: the name of the Mac the device
// belongs to, drawn there for the same reason — Mac names are not limited to
// the device font's few hundred characters.
#define VIBE_LABEL_HOST_SLOT 9U
#define VIBE_LABEL_HOST_W 108U  // stops short of the volume icon
#define VIBE_LABEL_HOST_H 16U
#define VIBE_LABEL_SLOTS  10U

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
// Only the gesture that started a take may end it: pressing a different one
// is ignored, so a mistaken press cannot cut a recording short. There is one
// recording action now, so this is just equality.
#define VIBE_ACT_SAME_INPUT(a, b) ((a) == (b))

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
