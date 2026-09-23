#include "vibe_audio.h"
#include "vibe_adpcm.h"
#include "vibe_app.h"
#include "vibe_ble.h"
#include "vibe_protocol.h"
#include "bsp_audio.h"

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>

static const char *TAG = "vibe_audio";

#define SILENCE_PEAK 500
#define SILENCE_BLOCKS (30 * 50)  // 30 s of 20 ms blocks
#define BEEP_SAMPLE_RATE 16000U
// The ES8311's DAC feeds a fixed-gain speaker amplifier. Loudness is set by
// the codec's volume, so the signal itself runs near full scale for the best
// signal-to-noise, with a few dB kept back so the amplifier never clips.
//
// The cues used to be about 50 dB below full at the default level: a 2600
// peak (-22 dBFS), a codec volume of 52 that the library's default curve maps
// linearly onto -50..0 dB (so -24 dB), and the library's own -3.6 dB for a
// 5 V amplifier fed from a 3.3 V DAC. That is roughly 1/300 of full scale.
#define BEEP_AMPLITUDE 12000
#define BEEP_VOLUME 52U
// Codec volume per level: -22.5, -15, -7.5 and 0 dB on the default curve.
// Even 7.5 dB steps, which the ear hears as roughly equal.
static const uint8_t s_level_volume[VIBE_VOLUME_LEVELS] = {0, 55, 70, 85, 100};
static volatile uint8_t s_level = 2;
static volatile bool s_playing;
#define BEEP_PI 3.14159265358979323846f

static TaskHandle_t s_task;
static volatile bool s_recording;
static vibe_adpcm_state_t s_adpcm;
static uint16_t s_seq;
static int s_quiet;
// Bit mask rather than a single slot: a stop cue must not be overwritten by
// a following start request when the user taps again quickly.
static volatile uint8_t s_beep_pending;
static portMUX_TYPE s_beep_mu = portMUX_INITIALIZER_UNLOCKED;

static int raw_peak(const int16_t *pcm, int n)
{
    int peak = 0;
    for (int i = 0; i < n; i++) {
        int v = pcm[i];
        if (v < 0) v = -v;
        if (v > peak) peak = v;
    }
    return peak;
}

// Hearing is closer to logarithmic than linear. The previous peak/2048 left a
// normal speaking voice in the bottom three steps of a sixteen-step meter, so
// the waveform barely moved no matter how loud the room was. These thresholds
// put conversation in the middle of the range and keep headroom for shouting.
static uint8_t peak_level(int peak)
{
    static const uint16_t steps[16] = {
        150, 260, 420, 650, 950, 1350, 1900, 2600,
        3600, 5000, 6800, 9200, 12500, 16800, 22000, 28000,
    };
    for (uint8_t i = 0; i < 16; i++) {
        if (peak < steps[i]) return i;
    }
    return 16;
}

static void send_eos(void)
{
    uint8_t hdr[VIBE_AUDIO_HDR_LEN];
    vibe_packet_eos(hdr, s_seq++);
    vibe_ble_audio_send(hdr, VIBE_AUDIO_HDR_LEN);
}

static bool take_pending_beep(vibe_beep_t *type)
{
    portENTER_CRITICAL(&s_beep_mu);
    const uint8_t pending = s_beep_pending;
    if (!pending) {
        portEXIT_CRITICAL(&s_beep_mu);
        return false;
    }

    // End is always the final state the user needs to hear. Keep connection
    // ready and send cues ahead of edit/start cues when several transitions
    // arrive in the same scheduling window.
    if (pending & VIBE_BEEP_SLEEP) *type = VIBE_BEEP_SLEEP;
    else if (pending & VIBE_BEEP_END) *type = VIBE_BEEP_END;
    else if (pending & VIBE_BEEP_DISCONNECT) *type = VIBE_BEEP_DISCONNECT;
    else if (pending & VIBE_BEEP_BOOT) *type = VIBE_BEEP_BOOT;
    else if (pending & VIBE_BEEP_READY) *type = VIBE_BEEP_READY;
    else if (pending & VIBE_BEEP_SEND) *type = VIBE_BEEP_SEND;
    else if (pending & VIBE_BEEP_EDIT) *type = VIBE_BEEP_EDIT;
    else *type = VIBE_BEEP_START;
    s_beep_pending = (uint8_t)(pending & (uint8_t)~*type);
    portEXIT_CRITICAL(&s_beep_mu);
    return true;
}

static void play_button_beep(vibe_beep_t type)
{
    typedef struct {
        unsigned hz;
        unsigned samples;
    } beep_segment_t;
    // One palette in C major so the cues sound like a family, each a short
    // figure whose direction carries the meaning: rising means something is
    // opening or has succeeded, falling means it has closed. Gaps are silent.
    // (Durations at 16 kHz: 16 samples per millisecond.)
    //
    // An octave higher than first written: a speaker this size loses a lot
    // below 1 kHz, and hearing is most sensitive from 2 to 4 kHz, so the same
    // signal around 1-2.4 kHz sounds several times louder than around 500 Hz.
    static const beep_segment_t boot[] = {       // awake: an arpeggio
        {1046U, 1440U}, {0U, 160U},               // C6
        {1318U, 1440U}, {0U, 160U},               // E6
        {1568U, 2880U},                           // G6, left to ring
    };
    static const beep_segment_t ready[] = {      // connected: ready to talk
        {1568U, 1600U}, {0U, 160U},               // G6
        {2094U, 4000U},                          // C7, rings on
    };
    static const beep_segment_t start[] = {      // recording starts
        {1318U, 960U}, {0U, 80U},                 // E6
        {1760U, 1600U},                           // A6
    };
    static const beep_segment_t end[] = {        // recording stops: mirrored
        {1760U, 960U}, {0U, 80U},                 // A6
        {1318U, 2080U},                           // E6
    };
    static const beep_segment_t send[] = {       // sent: quick, bright, upward
        {1568U, 800U}, {0U, 80U},                 // G6
        {1976U, 800U}, {0U, 80U},                 // B6
        {2350U, 2400U},                          // D7
    };
    static const beep_segment_t disconnect[] = { // link lost: "connected" reversed
        {2094U, 1600U}, {0U, 160U},              // C7
        {1568U, 3200U},                           // G6
    };
    static const beep_segment_t sleep[] = {      // going to sleep: "boot" reversed
        {1568U, 1440U}, {0U, 160U},               // G6
        {1318U, 1440U}, {0U, 160U},               // E6
        {1046U, 3600U},                           // C6, left to fade out
    };
    static const beep_segment_t edit[] = {       // erased: soft and low
        {1318U, 720U}, {0U, 160U},                // E6
        {1046U, 1280U},                           // C6
    };

    const beep_segment_t *segments;
    unsigned segment_count;
    const char *label;
    if (s_level == 0) return;  // silent: nothing to play
    if (type == VIBE_BEEP_SLEEP) {
        segments = sleep;
        segment_count = sizeof(sleep) / sizeof(sleep[0]);
        label = "sleep";
    } else if (type == VIBE_BEEP_DISCONNECT) {
        segments = disconnect;
        segment_count = sizeof(disconnect) / sizeof(disconnect[0]);
        label = "disconnect";
    } else if (type == VIBE_BEEP_BOOT) {
        segments = boot;
        segment_count = sizeof(boot) / sizeof(boot[0]);
        label = "boot";
    } else if (type == VIBE_BEEP_START) {
        segments = start;
        segment_count = sizeof(start) / sizeof(start[0]);
        label = "start";
    } else if (type == VIBE_BEEP_END) {
        segments = end;
        segment_count = sizeof(end) / sizeof(end[0]);
        label = "end";
    } else if (type == VIBE_BEEP_EDIT) {
        segments = edit;
        segment_count = sizeof(edit) / sizeof(edit[0]);
        label = "edit";
    } else if (type == VIBE_BEEP_READY) {
        segments = ready;
        segment_count = sizeof(ready) / sizeof(ready[0]);
        label = "ready";
    } else {
        segments = send;
        segment_count = sizeof(send) / sizeof(send[0]);
        label = "send";
    }

    unsigned total_samples = 0;
    for (unsigned i = 0; i < segment_count; i++) total_samples += segments[i].samples;
    const unsigned duration_ms = (total_samples * 1000U) / BEEP_SAMPLE_RATE;
    ESP_LOGI(TAG, "button chime %s (%ums, sine, level %u)", label, duration_ms, s_level);
    if (bsp_audio_set_format(BEEP_SAMPLE_RATE, 16, 1) != ESP_OK) {
        ESP_LOGW(TAG, "button %s beep format failed", label);
        return;
    }

    // Keep headroom at both stages. Check the codec volume call explicitly so
    // a muted/reopened codec cannot make the cue disappear silently.
    if (bsp_audio_set_volume(s_level_volume[s_level]) != ESP_OK) {
        ESP_LOGW(TAG, "button %s beep volume failed", label);
    }
    int16_t pcm[64];
    for (unsigned base = 0; base < total_samples; base += 64U) {
        unsigned segment = 0;
        unsigned offset = base;
        while (segment + 1U < segment_count && offset >= segments[segment].samples) {
            offset -= segments[segment].samples;
            segment++;
        }
        for (unsigned i = 0; i < 64; i++) {
            unsigned n = base + i;
            if (n >= total_samples) {
                pcm[i] = 0;
                continue;
            }

            unsigned local = offset + i;
            unsigned current = segment;
            while (current + 1U < segment_count && local >= segments[current].samples) {
                local -= segments[current].samples;
                current++;
            }
            const unsigned hz = segments[current].hz;
            if (hz == 0U) {
                pcm[i] = 0;
                continue;
            }

            // A bell rather than a beep: a 4 ms attack, then an exponential
            // decay across the note, then a short fade so the tail never
            // clicks. Flat-topped notes of the same length read as a buzz
            // and were easy to miss. Still a pure sine: extra harmonics push
            // the small amplifier into audible distortion.
            const unsigned note_samples = segments[current].samples;
            const unsigned attack = 64U;
            const unsigned fade = 48U;
            float gain;
            if (local < attack) {
                gain = (float)local / (float)attack;
            } else {
                gain = expf(-2.4f * (float)(local - attack) / (float)note_samples);
            }
            if (local + fade > note_samples) {
                gain *= (float)(note_samples - local) / (float)fade;
            }
            const float phase = 2.0f * BEEP_PI * (float)hz * (float)local /
                                (float)BEEP_SAMPLE_RATE;
            pcm[i] = (int16_t)(sinf(phase) * (float)BEEP_AMPLITUDE * gain);
        }
        esp_err_t write_err = bsp_audio_write(pcm, sizeof(pcm));
        if (write_err != ESP_OK) {
            ESP_LOGW(TAG, "hardware speaker %s write failed: %s", label,
                     esp_err_to_name(write_err));
            break;
        }
    }
    // The codec write fills the DMA queue asynchronously. Let the whole cue
    // drain before closing the codec, otherwise suspend can truncate it.
    vTaskDelay(pdMS_TO_TICKS(duration_ms + 120U));
    bsp_audio_suspend();
    ESP_LOGI(TAG, "button beep %s done", label);
}

static void audio_task(void *arg)
{
    (void)arg;
    int16_t *pcm = malloc(VIBE_AUDIO_SAMPS * sizeof(int16_t));
    uint8_t *adpcm = malloc(VIBE_AUDIO_ADPCM_LEN);
    uint8_t *pkt = malloc(VIBE_AUDIO_PKT_LEN);
    if (!pcm || !adpcm || !pkt) {
        ESP_LOGE(TAG, "audio buffers alloc failed");
        vTaskDelete(NULL);
        return;
    }

    bool capture_started = false;
    for (;;) {
        vibe_beep_t beep;
        // Play start before the first capture loop, or any cue while idle.
        if ((!capture_started || !s_recording) && take_pending_beep(&beep)) {
            s_playing = true;
            play_button_beep(beep);
            s_playing = false;
        }

        if (!s_recording) {
            vibe_app_note_peak(0);
            capture_started = false;
            vTaskDelay(pdMS_TO_TICKS(20));
            continue;
        }

        capture_started = true;

        if (bsp_audio_set_format(VIBE_AUDIO_HZ, 16, 1) != ESP_OK) {
            ESP_LOGE(TAG, "audio format failed");
            s_recording = false;
            continue;
        }

        memset(&s_adpcm, 0, sizeof(s_adpcm));
        s_seq = 0;
        s_quiet = 0;
        ESP_LOGI(TAG, "capture start");

        while (s_recording) {
            if (bsp_audio_read(pcm, VIBE_AUDIO_SAMPS * sizeof(int16_t)) != ESP_OK) {
                ESP_LOGW(TAG, "audio read failed");
                break;
            }

            int peak = raw_peak(pcm, VIBE_AUDIO_SAMPS);
            vibe_app_note_peak(peak_level(peak));
            // Silence is judged on the raw peak so the display mapping can be
            // retuned without changing when a take auto-stops.
            if (peak < SILENCE_PEAK) s_quiet++;
            else s_quiet = 0;
            if (s_quiet >= SILENCE_BLOCKS) {
                ESP_LOGI(TAG, "silence timeout");
                s_recording = false;
                vibe_app_on_silence();
                break;
            }

            vibe_adpcm_state_t snap = s_adpcm;
            vibe_adpcm_encode(&s_adpcm, pcm, VIBE_AUDIO_SAMPS, adpcm);
            vibe_packet_pack(pkt, s_seq++, snap.predictor, (uint8_t)snap.step_index,
                             adpcm);
            vibe_ble_audio_send(pkt, VIBE_AUDIO_PKT_LEN);
        }

        send_eos();
        bsp_audio_suspend();
        ESP_LOGI(TAG, "capture stop");

        // Handle the stop cue immediately after the capture stream is closed.
        // This removes the old timing hole where a later transition could
        // replace the end cue before the audio task reached the idle loop.
        if (!s_recording && take_pending_beep(&beep)) {
            s_playing = true;
            play_button_beep(beep);
            s_playing = false;
        }
    }
}

esp_err_t vibe_audio_start(void)
{
    if (s_task) return ESP_OK;
    BaseType_t ok = xTaskCreate(audio_task, "vibe_audio", 4096, NULL, 5, &s_task);
    return ok == pdPASS ? ESP_OK : ESP_ERR_NO_MEM;
}

void vibe_audio_set_recording(bool on)
{
    s_recording = on;
}

bool vibe_audio_recording(void)
{
    return s_recording;
}

void vibe_audio_beep(vibe_beep_t type)
{
    if (type == VIBE_BEEP_START || type == VIBE_BEEP_END ||
        type == VIBE_BEEP_EDIT || type == VIBE_BEEP_READY ||
        type == VIBE_BEEP_SEND || type == VIBE_BEEP_BOOT ||
        type == VIBE_BEEP_DISCONNECT || type == VIBE_BEEP_SLEEP) {
        portENTER_CRITICAL(&s_beep_mu);
        s_beep_pending |= (uint8_t)type;
        portEXIT_CRITICAL(&s_beep_mu);
        ESP_LOGI(TAG, "queued %s beep (volume %u)",
                 type == VIBE_BEEP_START ? "start" :
                 type == VIBE_BEEP_END ? "end" :
                 type == VIBE_BEEP_EDIT ? "edit" :
                 type == VIBE_BEEP_READY ? "ready" :
                 type == VIBE_BEEP_BOOT ? "boot" :
                 type == VIBE_BEEP_DISCONNECT ? "disconnect" :
                 type == VIBE_BEEP_SLEEP ? "sleep" : "send", s_level);
    }
}

void vibe_audio_set_volume_level(uint8_t level)
{
    s_level = level < VIBE_VOLUME_LEVELS ? level : VIBE_VOLUME_LEVELS - 1U;
}

uint8_t vibe_audio_volume_level(void)
{
    return s_level;
}

void vibe_audio_drain(uint32_t timeout_ms)
{
    for (uint32_t waited = 0; waited < timeout_ms; waited += 20) {
        if (!s_beep_pending && !s_playing) return;
        vTaskDelay(pdMS_TO_TICKS(20));
    }
}
