#include "vibe_protocol.h"
#include "vibe_state.h"

#include <assert.h>

#define G_UP_CLICK    (VIBE_BTN_UP * 3 + VIBE_GES_CLICK)
#define G_MID_CLICK   (VIBE_BTN_MID * 3 + VIBE_GES_CLICK)
#define G_MID_DOUBLE  (VIBE_BTN_MID * 3 + VIBE_GES_DOUBLE)
#define G_DOWN_CLICK  (VIBE_BTN_DOWN * 3 + VIBE_GES_CLICK)
#define G_DOWN_LONG   (VIBE_BTN_DOWN * 3 + VIBE_GES_LONG)

static void bind(vibe_state_t *s, uint8_t gesture, uint8_t action)
{
    vibe_state_apply(s, VIBE_IN_ACTIONS, (uint32_t)gesture | ((uint32_t)action << 8));
}

// Default-ish bindings: middle click dictates, middle double translates,
// up click drives Doubao, down click sends Return.
static void linked_idle(vibe_state_t *s)
{
    vibe_state_init(s);
    vibe_state_apply(s, VIBE_IN_LINK_UP, 0);
    vibe_state_apply(s, VIBE_IN_AUDIO_SUB, 0);
    bind(s, G_MID_CLICK, VIBE_ACT_DICTATE);
    bind(s, G_MID_DOUBLE, VIBE_ACT_TRANSLATE);
    bind(s, G_UP_CLICK, VIBE_ACT_DOUBAO);
    bind(s, G_DOWN_CLICK, VIBE_ACT_ENTER);
    assert(s->phase == VIBE_PHASE_IDLE);
}

int main(void)
{
    vibe_state_t s;
    vibe_out_t o;

    // Every gesture is reported, whatever it is bound to.
    linked_idle(&s);
    o = vibe_state_apply(&s, VIBE_IN_GESTURE, G_MID_CLICK);
    assert(o.n_events == 1);
    assert(o.ble_events[0] == VIBE_GESTURE_EVENT(VIBE_BTN_MID, VIBE_GES_CLICK));
    assert(o.start_capture);
    assert(s.phase == VIBE_PHASE_RECORDING);
    assert(s.active_gesture == G_MID_CLICK);

    // The same gesture again stops the take and the device is done: nothing
    // reports when a transcript lands, so it must not sit waiting for one.
    o = vibe_state_apply(&s, VIBE_IN_GESTURE, G_MID_CLICK);
    assert(o.stop_capture);
    assert(s.phase == VIBE_PHASE_IDLE);
    assert(s.active_gesture == VIBE_GESTURE_NONE);

    // A second recording key behaves the same way.
    linked_idle(&s);
    vibe_state_apply(&s, VIBE_IN_GESTURE, G_UP_CLICK);
    assert(s.phase == VIBE_PHASE_RECORDING);
    o = vibe_state_apply(&s, VIBE_IN_GESTURE, G_UP_CLICK);
    assert(o.stop_capture);
    assert(s.phase == VIBE_PHASE_IDLE);

    // The other input method must not cut a recording short: pressing the
    // Doubao gesture while Typeless is recording is reported but ignored.
    linked_idle(&s);
    vibe_state_apply(&s, VIBE_IN_GESTURE, G_MID_CLICK);
    o = vibe_state_apply(&s, VIBE_IN_GESTURE, G_UP_CLICK);
    assert(o.n_events == 1);
    assert(!o.stop_capture);
    assert(!o.start_capture);
    assert(s.phase == VIBE_PHASE_RECORDING);
    assert(s.active_gesture == G_MID_CLICK);

    // A different gesture does not end someone else's take.
    o = vibe_state_apply(&s, VIBE_IN_GESTURE, G_MID_DOUBLE);
    assert(!o.stop_capture);
    assert(s.phase == VIBE_PHASE_RECORDING);
    assert(s.active_gesture == G_MID_CLICK);

    // Non-recording actions only report; they never touch the microphone.
    linked_idle(&s);
    o = vibe_state_apply(&s, VIBE_IN_GESTURE, G_DOWN_CLICK);
    assert(o.n_events == 1);
    assert(o.ble_events[0] == VIBE_GESTURE_EVENT(VIBE_BTN_DOWN, VIBE_GES_CLICK));
    assert(!o.start_capture && !o.stop_capture);
    assert(s.phase == VIBE_PHASE_IDLE);

    // Unbound gestures are still reported, but do nothing locally.
    linked_idle(&s);
    o = vibe_state_apply(&s, VIBE_IN_GESTURE, G_DOWN_LONG);
    assert(o.n_events == 1);
    assert(!o.start_capture);
    assert(s.phase == VIBE_PHASE_IDLE);

    // Rebinding takes effect without any reflash.
    linked_idle(&s);
    bind(&s, G_DOWN_LONG, VIBE_ACT_ASK);
    o = vibe_state_apply(&s, VIBE_IN_GESTURE, G_DOWN_LONG);
    assert(o.start_capture);
    assert(s.phase == VIBE_PHASE_RECORDING);

    // Silence timeout ends the take like a manual stop.
    linked_idle(&s);
    vibe_state_apply(&s, VIBE_IN_GESTURE, G_MID_CLICK);
    o = vibe_state_apply(&s, VIBE_IN_SILENCE, 0);
    assert(o.stop_capture);
    assert(s.phase == VIBE_PHASE_IDLE);

    // Losing the link mid-take stops capture and parks the device.
    linked_idle(&s);
    vibe_state_apply(&s, VIBE_IN_GESTURE, G_MID_CLICK);
    o = vibe_state_apply(&s, VIBE_IN_LINK_DOWN, 0);
    assert(o.stop_capture);
    assert(s.phase == VIBE_PHASE_DOWN);
    assert(s.active_gesture == VIBE_GESTURE_NONE);

    // Losing only the audio subscription does the same but keeps the link.
    linked_idle(&s);
    vibe_state_apply(&s, VIBE_IN_GESTURE, G_MID_CLICK);
    o = vibe_state_apply(&s, VIBE_IN_AUDIO_UNSUB, 0);
    assert(o.stop_capture);
    assert(s.phase == VIBE_PHASE_WAIT);

    // Gestures are ignored while the link is not ready.
    vibe_state_init(&s);
    o = vibe_state_apply(&s, VIBE_IN_GESTURE, G_MID_CLICK);
    assert(!o.start_capture);
    assert(s.phase == VIBE_PHASE_DOWN);

    // Out-of-range gesture indexes must not corrupt anything.
    linked_idle(&s);
    o = vibe_state_apply(&s, VIBE_IN_GESTURE, VIBE_GESTURE_COUNT);
    assert(o.n_events == 0);
    assert(s.phase == VIBE_PHASE_IDLE);

    return 0;
}
