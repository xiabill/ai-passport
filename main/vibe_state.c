#include "vibe_state.h"
#include "vibe_protocol.h"

static vibe_out_t out_none(void)
{
    vibe_out_t o = {{0, 0}, 0, false, false};
    return o;
}

static void push_event(vibe_out_t *o, uint8_t ev)
{
    if (o->n_events < 2) o->ble_events[o->n_events++] = ev;
}

static void ready_phase(vibe_state_t *s)
{
    if (!s->linked) s->phase = VIBE_PHASE_DOWN;
    else if (!s->audio_sub) s->phase = VIBE_PHASE_WAIT;
    else s->phase = VIBE_PHASE_IDLE;
}

void vibe_state_init(vibe_state_t *s)
{
    s->phase = VIBE_PHASE_DOWN;
    s->linked = false;
    s->audio_sub = false;
    s->typeless = VIBE_TL_IDLE;
    s->queued_enter = false;
}

static vibe_out_t stop_recording(vibe_state_t *s, uint8_t extra)
{
    vibe_out_t o = out_none();
    o.stop_capture = true;
    push_event(&o, VIBE_BLE_STOP);
    if (extra) push_event(&o, extra);
    s->phase = VIBE_PHASE_PROCESSING;
    return o;
}

vibe_out_t vibe_state_apply(vibe_state_t *s, vibe_in_t in, uint8_t typeless_byte)
{
    vibe_out_t o = out_none();

    switch (in) {
    case VIBE_IN_LINK_UP:
        s->linked = true;
        if (s->phase == VIBE_PHASE_DOWN) ready_phase(s);
        break;

    case VIBE_IN_LINK_DOWN:
        if (s->phase == VIBE_PHASE_RECORDING) o.stop_capture = true;
        s->linked = false;
        s->audio_sub = false;
        s->queued_enter = false;
        s->phase = VIBE_PHASE_DOWN;
        break;

    case VIBE_IN_AUDIO_SUB:
        s->audio_sub = true;
        if (s->phase == VIBE_PHASE_WAIT) s->phase = VIBE_PHASE_IDLE;
        break;

    case VIBE_IN_AUDIO_UNSUB:
        s->audio_sub = false;
        if (s->phase == VIBE_PHASE_RECORDING) o.stop_capture = true;
        s->queued_enter = false;
        if (s->linked) s->phase = VIBE_PHASE_WAIT;
        else s->phase = VIBE_PHASE_DOWN;
        break;

    case VIBE_IN_OK:
        if (s->phase == VIBE_PHASE_IDLE) {
            s->queued_enter = false;
            s->phase = VIBE_PHASE_RECORDING;
            o.start_capture = true;
            push_event(&o, VIBE_BLE_START);
        } else if (s->phase == VIBE_PHASE_RECORDING) {
            s->queued_enter = false;
            return stop_recording(s, 0);
        }
        break;

    case VIBE_IN_DOWN:
        if (s->phase == VIBE_PHASE_RECORDING) {
            s->queued_enter = true;
            return stop_recording(s, 0);
        }
        if (s->phase == VIBE_PHASE_IDLE) {
            push_event(&o, VIBE_BLE_ENTER);
        } else if (s->phase == VIBE_PHASE_PROCESSING) {
            s->queued_enter = true;
        }
        break;

    case VIBE_IN_UP:
        s->queued_enter = false;
        if (s->phase == VIBE_PHASE_RECORDING) {
            return stop_recording(s, VIBE_BLE_CANCEL);
        }
        if (s->phase == VIBE_PHASE_IDLE || s->phase == VIBE_PHASE_PROCESSING) {
            push_event(&o, VIBE_BLE_CANCEL);
            if (s->phase == VIBE_PHASE_PROCESSING) ready_phase(s);
        }
        break;

    case VIBE_IN_TYPELESS:
        s->typeless = typeless_byte;
        if (s->phase == VIBE_PHASE_PROCESSING &&
            (typeless_byte == VIBE_TL_IDLE || typeless_byte == VIBE_TL_DOWN)) {
            if (s->queued_enter) {
                push_event(&o, VIBE_BLE_ENTER);
                s->queued_enter = false;
            }
            ready_phase(s);
        }
        break;

    case VIBE_IN_SILENCE:
        if (s->phase == VIBE_PHASE_RECORDING) {
            s->queued_enter = false;
            return stop_recording(s, 0);
        }
        break;

    case VIBE_IN_PROC_TIMEOUT:
        if (s->phase == VIBE_PHASE_PROCESSING) {
            if (s->queued_enter) {
                push_event(&o, VIBE_BLE_ENTER);
                s->queued_enter = false;
            }
            ready_phase(s);
        }
        break;
    }

    return o;
}
