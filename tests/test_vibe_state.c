#include "vibe_protocol.h"
#include "vibe_state.h"

#include <assert.h>

static void linked_idle(vibe_state_t *s)
{
    vibe_state_init(s);
    vibe_state_apply(s, VIBE_IN_LINK_UP, 0);
    vibe_state_apply(s, VIBE_IN_AUDIO_SUB, 0);
    assert(s->phase == VIBE_PHASE_IDLE);
}

int main(void)
{
    vibe_state_t s;
    vibe_out_t o;

    linked_idle(&s);
    o = vibe_state_apply(&s, VIBE_IN_OK, 0);
    assert(s.phase == VIBE_PHASE_RECORDING);
    assert(s.source == VIBE_SOURCE_TYPELESS);
    assert(o.start_capture);
    assert(o.n_events == 1 && o.ble_events[0] == VIBE_BLE_START);

    o = vibe_state_apply(&s, VIBE_IN_OK, 0);
    assert(s.phase == VIBE_PHASE_PROCESSING);
    assert(o.stop_capture);
    assert(o.n_events == 1 && o.ble_events[0] == VIBE_BLE_STOP);

    o = vibe_state_apply(&s, VIBE_IN_TYPELESS, VIBE_TL_IDLE);
    assert(s.phase == VIBE_PHASE_IDLE);
    assert(o.n_events == 0);

    linked_idle(&s);
    o = vibe_state_apply(&s, VIBE_IN_UP, 0);
    assert(s.phase == VIBE_PHASE_RECORDING);
    assert(s.source == VIBE_SOURCE_DOUBAO);
    assert(o.start_capture);
    assert(o.n_events == 1 && o.ble_events[0] == VIBE_BLE_DOUBAO_START);
    o = vibe_state_apply(&s, VIBE_IN_UP, 0);
    assert(s.phase == VIBE_PHASE_IDLE);
    assert(!s.queued_enter);
    assert(o.stop_capture);
    assert(o.n_events == 1 && o.ble_events[0] == VIBE_BLE_DOUBAO_STOP);

    linked_idle(&s);
    vibe_state_apply(&s, VIBE_IN_UP, 0);
    o = vibe_state_apply(&s, VIBE_IN_DOWN, 0);
    assert(s.phase == VIBE_PHASE_IDLE);
    assert(!s.queued_enter);
    assert(o.stop_capture);
    assert(o.n_events == 1 && o.ble_events[0] == VIBE_BLE_DOUBAO_STOP_SEND);

    linked_idle(&s);
    vibe_state_apply(&s, VIBE_IN_OK, 0);
    o = vibe_state_apply(&s, VIBE_IN_UP, 0);
    assert(s.phase == VIBE_PHASE_RECORDING);
    assert(s.source == VIBE_SOURCE_TYPELESS);
    assert(o.n_events == 0);

    linked_idle(&s);
    vibe_state_apply(&s, VIBE_IN_OK, 0);
    o = vibe_state_apply(&s, VIBE_IN_SILENCE, 0);
    assert(s.phase == VIBE_PHASE_PROCESSING);
    assert(o.stop_capture);

    linked_idle(&s);
    vibe_state_apply(&s, VIBE_IN_OK, 0);
    o = vibe_state_apply(&s, VIBE_IN_LINK_DOWN, 0);
    assert(s.phase == VIBE_PHASE_DOWN);
    assert(o.stop_capture);

    vibe_state_init(&s);
    vibe_state_apply(&s, VIBE_IN_LINK_UP, 0);
    assert(s.phase == VIBE_PHASE_WAIT);
    o = vibe_state_apply(&s, VIBE_IN_OK, 0);
    assert(!o.start_capture);
    assert(s.phase == VIBE_PHASE_WAIT);
    return 0;
}
