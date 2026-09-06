#pragma once

#include "vibe_protocol.h"

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Pure session state machine. No ESP-IDF / LVGL. Host tests drive it.

typedef enum {
    VIBE_PHASE_DOWN = 0,     // no BLE link
    VIBE_PHASE_WAIT,         // linked, audio CCCD not subscribed
    VIBE_PHASE_IDLE,         // ready to talk
    VIBE_PHASE_RECORDING,    // mic streaming
    VIBE_PHASE_PROCESSING,   // waiting for Typeless after stop
} vibe_phase_t;

// Gesture index: button * 3 + gesture, i.e. 0..8. VIBE_GESTURE_COUNT lives in
// vibe_protocol.h, next to the wire format that carries these actions.
#define VIBE_GESTURE_NONE  0xFFU

typedef enum {
    VIBE_IN_LINK_UP = 0,
    VIBE_IN_LINK_DOWN,
    VIBE_IN_AUDIO_SUB,
    VIBE_IN_AUDIO_UNSUB,
    VIBE_IN_GESTURE,         // arg = gesture index 0..8
    VIBE_IN_ACTIONS,         // arg = gesture index | (action << 8)
    VIBE_IN_TYPELESS,        // arg = typeless state byte
    VIBE_IN_SILENCE,         // 30 s below peak threshold while recording
    VIBE_IN_PROC_TIMEOUT,    // processing wait expired
} vibe_in_t;

typedef struct {
    vibe_phase_t phase;
    bool linked;
    bool audio_sub;
    uint8_t typeless;
    // Action bound to each gesture, supplied by the bridge. Used only to decide
    // whether to arm the microphone and to label the on-screen key hints.
    uint8_t actions[VIBE_GESTURE_COUNT];
    uint8_t active_gesture;  // VIBE_GESTURE_NONE when idle
} vibe_state_t;

typedef struct {
    uint8_t ble_events[2];
    uint8_t n_events;
    bool start_capture;
    bool stop_capture;
    bool edit_action;
} vibe_out_t;

void vibe_state_init(vibe_state_t *s);
vibe_out_t vibe_state_apply(vibe_state_t *s, vibe_in_t in, uint32_t arg);

#ifdef __cplusplus
}
#endif
