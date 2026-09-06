#include "vibe_state.h"
#include "vibe_protocol.h"

static vibe_out_t out_none(void)
{
    vibe_out_t o = {{0, 0}, 0, false, false, false};
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

static uint8_t gesture_action(const vibe_state_t *s, uint8_t g)
{
    return g < VIBE_GESTURE_COUNT ? s->actions[g] : VIBE_ACT_NONE;
}

static bool gesture_records(const vibe_state_t *s, uint8_t g)
{
    return VIBE_ACT_RECORDS(gesture_action(s, g));
}

static bool gesture_waits_transcript(const vibe_state_t *s, uint8_t g)
{
    return VIBE_ACT_WAITS_TRANSCRIPT(gesture_action(s, g));
}

void vibe_state_init(vibe_state_t *s)
{
    s->phase = VIBE_PHASE_DOWN;
    s->linked = false;
    s->audio_sub = false;
    s->typeless = VIBE_TL_IDLE;
    for (int i = 0; i < VIBE_GESTURE_COUNT; i++) s->actions[i] = VIBE_ACT_NONE;
    s->active_gesture = VIBE_GESTURE_NONE;
}

// Stops capture. Typeless-backed gestures park in PROCESSING until the bridge
// reports the transcript landed; everything else is done immediately.
static void finish_recording(vibe_state_t *s, vibe_out_t *o)
{
    o->stop_capture = true;
    if (gesture_waits_transcript(s, s->active_gesture)) {
        s->phase = VIBE_PHASE_PROCESSING;
    } else {
        s->active_gesture = VIBE_GESTURE_NONE;
        ready_phase(s);
    }
}

vibe_out_t vibe_state_apply(vibe_state_t *s, vibe_in_t in, uint32_t arg)
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
        s->active_gesture = VIBE_GESTURE_NONE;
        s->phase = VIBE_PHASE_DOWN;
        break;

    case VIBE_IN_AUDIO_SUB:
        s->audio_sub = true;
        if (s->phase == VIBE_PHASE_WAIT) s->phase = VIBE_PHASE_IDLE;
        break;

    case VIBE_IN_AUDIO_UNSUB:
        s->audio_sub = false;
        if (s->phase == VIBE_PHASE_RECORDING) o.stop_capture = true;
        s->active_gesture = VIBE_GESTURE_NONE;
        s->phase = s->linked ? VIBE_PHASE_WAIT : VIBE_PHASE_DOWN;
        break;

    case VIBE_IN_ACTIONS: {
        uint8_t g = (uint8_t)(arg & 0xFFU);
        uint8_t action = (uint8_t)((arg >> 8) & 0xFFU);
        if (g < VIBE_GESTURE_COUNT && action < VIBE_ACT_COUNT) s->actions[g] = action;
        break;
    }

    case VIBE_IN_GESTURE: {
        uint8_t g = (uint8_t)arg;
        if (g >= VIBE_GESTURE_COUNT) break;
        // The gesture is always reported: the bridge decides what it means,
        // including gestures that carry no recording at all.
        push_event(&o, VIBE_GESTURE_EVENT(g / 3U, g % 3U));

        if (s->phase == VIBE_PHASE_RECORDING) {
            // Only the input method that is recording may end its own take.
            // A gesture belonging to the other one is ignored rather than
            // cutting the recording short.
            if (gesture_records(s, g) &&
                VIBE_ACT_SAME_INPUT(gesture_action(s, s->active_gesture),
                                    gesture_action(s, g))) {
                finish_recording(s, &o);
            }
        } else if (s->phase == VIBE_PHASE_IDLE && gesture_records(s, g)) {
            s->active_gesture = g;
            s->phase = VIBE_PHASE_RECORDING;
            o.start_capture = true;
        }
        break;
    }

    case VIBE_IN_TYPELESS:
        s->typeless = (uint8_t)arg;
        if (s->phase == VIBE_PHASE_PROCESSING &&
            (s->typeless == VIBE_TL_IDLE || s->typeless == VIBE_TL_DOWN)) {
            s->active_gesture = VIBE_GESTURE_NONE;
            ready_phase(s);
        }
        break;

    case VIBE_IN_SILENCE:
        if (s->phase == VIBE_PHASE_RECORDING) finish_recording(s, &o);
        break;

    case VIBE_IN_PROC_TIMEOUT:
        if (s->phase == VIBE_PHASE_PROCESSING) {
            s->active_gesture = VIBE_GESTURE_NONE;
            ready_phase(s);
        }
        break;
    }

    return o;
}
