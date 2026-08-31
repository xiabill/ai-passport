#include "vibe_protocol.h"

#include <assert.h>
#include <string.h>

int main(void)
{
    uint8_t adpcm[VIBE_AUDIO_ADPCM_LEN];
    memset(adpcm, 0xA5, sizeof(adpcm));
    uint8_t pkt[VIBE_AUDIO_PKT_LEN];
    vibe_packet_pack(pkt, 0x1234, -2, 7, adpcm);

    vibe_packet_hdr_t hdr;
    assert(vibe_packet_parse_hdr(pkt, sizeof(pkt), &hdr));
    assert(hdr.seq == 0x1234);
    assert(hdr.predictor == -2);
    assert(hdr.step_index == 7);
    assert(!hdr.eos);
    assert(pkt[6] == 0xA5);
    assert(pkt[VIBE_AUDIO_PKT_LEN - 1] == 0xA5);

    uint8_t eos[VIBE_AUDIO_HDR_LEN];
    vibe_packet_eos(eos, 9);
    assert(vibe_packet_parse_hdr(eos, sizeof(eos), &hdr));
    assert(hdr.seq == 9);
    assert(hdr.eos);

    assert(!vibe_packet_parse_hdr(pkt, 5, &hdr));
    return 0;
}
