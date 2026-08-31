#include "vibe_protocol.h"

#include <string.h>

void vibe_packet_pack(uint8_t *out, uint16_t seq, int16_t predictor,
                      uint8_t step_index, const uint8_t *adpcm)
{
    out[0] = (uint8_t)(seq & 0xFF);
    out[1] = (uint8_t)(seq >> 8);
    out[2] = (uint8_t)(predictor & 0xFF);
    out[3] = (uint8_t)((uint16_t)predictor >> 8);
    out[4] = step_index;
    out[5] = 0;
    memcpy(out + VIBE_AUDIO_HDR_LEN, adpcm, VIBE_AUDIO_ADPCM_LEN);
}

void vibe_packet_eos(uint8_t *out, uint16_t seq)
{
    out[0] = (uint8_t)(seq & 0xFF);
    out[1] = (uint8_t)(seq >> 8);
    out[2] = 0;
    out[3] = 0;
    out[4] = 0;
    out[5] = VIBE_FLAG_EOS;
}

bool vibe_packet_parse_hdr(const uint8_t *pkt, size_t len, vibe_packet_hdr_t *hdr)
{
    if (!pkt || !hdr) return false;
    if (len != VIBE_AUDIO_PKT_LEN && len != VIBE_AUDIO_HDR_LEN) return false;
    hdr->seq = (uint16_t)(pkt[0] | ((uint16_t)pkt[1] << 8));
    hdr->predictor = (int16_t)(pkt[2] | ((uint16_t)pkt[3] << 8));
    hdr->step_index = pkt[4];
    hdr->flags = pkt[5];
    hdr->eos = (len == VIBE_AUDIO_HDR_LEN) || ((hdr->flags & VIBE_FLAG_EOS) != 0);
    return true;
}
