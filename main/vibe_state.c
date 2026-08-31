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
    s->source = VIBE_SOURCE_NONE;
    s->linked = false;
    s->audio_sub = false;
    s->typeless = VIBE_TL_IDLE;
    s->queued_enter = false;
}

static vibe_out_t start_recording(vibe_state_t *s, vibe_source_t source, uint8_t event)
{
    vibe_out_t o = out_none();
    s->source = source;
    s->queued_enter = false;
    s->phase = VIBE_PHASE_RECORDING;
    o.start_capture = true;
    push_event(&o, event);
    return o;
}

static vibe_out_t stop_typeless(vibe_state_t *s, bool queue_enter)
{
    vibe_out_t o = out_none();
    o.stop_capture = true;
    s->queued_enter = queue_enter;
    push_event(&o, VIBE_BLE_STOP);
    s->phase = VIBE_PHASE_PROCESSING;
    return o;
}

static vibe_out_t stop_doubao(vibe_state_t *s, bool send)
{
    vibe_out_t o = out_none();
    o.stop_capture = true;
    s->queued_enter = false;
    push_event(&o, send ? VIBE_BLE_DOUBAO_STOP_SEND : VIBE_BLE_DOUBAO_STOP);
    s->source = VIBE_SOURCE_NONE;
    ready_phase(s);
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
        s->source = VIBE_SOURCE_NONE;
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
        s->source = VIBE_SOURCE_NONE;
        s->queued_enter = false;
        if (s->linked) s->phase = VIBE_PHASE_WAIT;
        else s->phase = VIBE_PHASE_DOWN;
        break;

    case VIBE_IN_OK:
        if (s->phase == VIBE_PHASE_IDLE) {
            return start_recording(s, VIBE_SOURCE_TYPELESS, VIBE_BLE_START);
        } else if (s->phase == VIBE_PHASE_RECORDING && s->source == VIBE_SOURCE_TYPELESS) {
            return stop_typeless(s, false);
        }
        break;

    case VIBE_IN_DOWN:
        if (s->phase == VIBE_PHASE_RECORDING) {
            if (s->source == VIBE_SOURCE_TYPELESS) return stop_typeless(s, true);
            if (s->source == VIBE_SOURCE_DOUBAO) return stop_doubao(s, true);
        }
        if (s->phase == VIBE_PHASE_IDLE) {
            push_event(&o, VIBE_BLE_ENTER);
        } else if (s->phase == VIBE_PHASE_PROCESSING) {
            s->queued_enter = true;
        }
        break;

    case VIBE_IN_UP:
        if (s->phase == VIBE_PHASE_IDLE) {
            return start_recording(s, VIBE_SOURCE_DOUBAO, VIBE_BLE_DOUBAO_START);
        }
        if (s->phase == VIBE_PHASE_RECORDING && s->source == VIBE_SOURCE_DOUBAO) {
            return stop_doubao(s, false);
        }
        break;

    case VIBE_IN_TYPELESS:
        s->typeless = typeless_byte;
        if (s->phase == VIBE_PHASE_PROCESSING && s->source == VIBE_SOURCE_TYPELESS &&
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
            if (s->source == VIBE_SOURCE_TYPELESS) return stop_typeless(s, false);
            if (s->source == VIBE_SOURCE_DOUBAO) return stop_doubao(s, false);
        }
        break;

    case VIBE_IN_PROC_TIMEOUT:
        if (s->phase == VIBE_PHASE_PROCESSING && s->source == VIBE_SOURCE_TYPELESS) {
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
