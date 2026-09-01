#pragma once

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

typedef enum {
    VIBE_SOURCE_NONE = 0,
    VIBE_SOURCE_TYPELESS,
    VIBE_SOURCE_TYPELESS_TRANSLATE,
    VIBE_SOURCE_TYPELESS_ASK,
    VIBE_SOURCE_DOUBAO,
} vibe_source_t;

typedef enum {
    VIBE_IN_LINK_UP = 0,
    VIBE_IN_LINK_DOWN,
    VIBE_IN_AUDIO_SUB,
    VIBE_IN_AUDIO_UNSUB,
    VIBE_IN_OK,              // Typeless toggle
    VIBE_IN_OK_DOUBLE,       // Typeless translation shortcut
    VIBE_IN_OK_LONG,         // Typeless Ask anything shortcut
    VIBE_IN_DOWN,            // Return / stop-and-send
    VIBE_IN_UP,              // Doubao toggle
    VIBE_IN_UP_DOUBLE,       // Doubao select all
    VIBE_IN_UP_LONG,         // Doubao clear all
    VIBE_IN_TYPELESS,        // typeless_byte is valid
    VIBE_IN_SILENCE,         // 30 s below peak threshold while recording
    VIBE_IN_PROC_TIMEOUT,    // processing wait expired
} vibe_in_t;

typedef struct {
    vibe_phase_t phase;
    vibe_source_t source;
    bool linked;
    bool audio_sub;
    uint8_t typeless;
    bool queued_enter;
} vibe_state_t;

typedef struct {
    uint8_t ble_events[2];
    uint8_t n_events;
    bool start_capture;
    bool stop_capture;
    bool edit_action;
} vibe_out_t;

void vibe_state_init(vibe_state_t *s);
vibe_out_t vibe_state_apply(vibe_state_t *s, vibe_in_t in, uint8_t typeless_byte);

#ifdef __cplusplus
}
#endif
