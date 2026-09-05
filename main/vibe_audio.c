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
// The ES8311's DAC feeds a fixed-gain speaker amplifier. Keep headroom in the
// PCM signal, but leave enough level for the cue to remain audible in normal
// use. The previous 900/36 combination was effectively inaudible here.
#define BEEP_AMPLITUDE 1800
#define BEEP_VOLUME 52U
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

static uint8_t peak_level(const int16_t *pcm, int n)
{
    int peak = 0;
    for (int i = 0; i < n; i++) {
        int v = pcm[i];
        if (v < 0) v = -v;
        if (v > peak) peak = v;
    }
    // Compress the raw 16-bit peak into a calmer 0..16 display range. A
    // normal speaking voice should stay green/yellow; only close, loud peaks
    // should reach red.
    int level = peak / 2048;
    if (level > 16) level = 16;
    return (uint8_t)level;
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
    if (pending & VIBE_BEEP_END) *type = VIBE_BEEP_END;
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
    // Use a sparse two-note palette. Fewer simultaneous/high harmonics means
    // less energy for the fixed-gain PA to amplify, while the direction of
    // the interval still distinguishes start, end and edit actions.
    static const beep_segment_t start[] = {
        {440U, 640U},  // A4, 40 ms
        {0U,   240U},  // 15 ms gap
        {554U, 800U},  // C#5, 50 ms
    };
    static const beep_segment_t end[] = {
        {554U, 720U},  // C#5, 45 ms
        {0U,   240U},  // 15 ms gap
        {440U, 1440U}, // A4, 90 ms
    };
    static const beep_segment_t edit[] = {
        {659U, 560U},  // E5, 35 ms
        {0U,   240U},  // 15 ms gap
        {554U, 960U},  // C#5, 60 ms
    };
    static const beep_segment_t ready[] = {
        {392U, 560U},  // G4, 35 ms
        {0U,   240U},  // 15 ms gap
        {523U, 800U},  // C5, 50 ms
    };
    static const beep_segment_t send[] = {
        {784U, 480U},  // G5, 30 ms
        {0U,   160U},  // 10 ms gap
        {988U, 640U},  // B5, 40 ms
    };

    const beep_segment_t *segments;
    unsigned segment_count;
    const char *label;
    if (type == VIBE_BEEP_START) {
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
    ESP_LOGI(TAG, "button chime %s (%ums, sine, volume=%u)", label, duration_ms, BEEP_VOLUME);
    if (bsp_audio_set_format(BEEP_SAMPLE_RATE, 16, 1) != ESP_OK) {
        ESP_LOGW(TAG, "button %s beep format failed", label);
        return;
    }

    // Keep headroom at both stages. Check the codec volume call explicitly so
    // a muted/reopened codec cannot make the cue disappear silently.
    if (bsp_audio_set_volume(BEEP_VOLUME) != ESP_OK) {
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

            // A short per-note envelope removes clicks at both note and gap
            // boundaries. Keep this as a pure sine: the codec and speaker add
            // enough character by themselves, while extra harmonics can push
            // the small amplifier into audible distortion.
            const unsigned note_samples = segments[current].samples;
            const unsigned envelope_samples = note_samples / 6U < 96U
                ? (note_samples / 6U < 8U ? 8U : note_samples / 6U)
                : 96U;
            float gain = 1.0f;
            if (local < envelope_samples) {
                gain = (float)local / (float)envelope_samples;
            } else if (local + envelope_samples > note_samples) {
                gain = (float)(note_samples - local) / (float)envelope_samples;
            }
            const float phase = 2.0f * BEEP_PI * (float)hz * (float)local /
                                (float)BEEP_SAMPLE_RATE;
            pcm[i] = (int16_t)(sinf(phase) * (float)BEEP_AMPLITUDE * gain);
        }
        if (bsp_audio_write(pcm, sizeof(pcm)) != ESP_OK) {
            ESP_LOGW(TAG, "button %s beep write failed", label);
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
            play_button_beep(beep);
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

            uint8_t level = peak_level(pcm, VIBE_AUDIO_SAMPS);
            vibe_app_note_peak(level);
            if (level == 0) {
                int peak = 0;
                for (int i = 0; i < VIBE_AUDIO_SAMPS; i++) {
                    int v = pcm[i];
                    if (v < 0) v = -v;
                    if (v > peak) peak = v;
                }
                if (peak < SILENCE_PEAK) s_quiet++;
                else s_quiet = 0;
            } else {
                s_quiet = 0;
            }
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
            play_button_beep(beep);
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
        type == VIBE_BEEP_SEND) {
        portENTER_CRITICAL(&s_beep_mu);
        s_beep_pending |= (uint8_t)type;
        portEXIT_CRITICAL(&s_beep_mu);
        ESP_LOGI(TAG, "queued %s beep (volume %u)",
                 type == VIBE_BEEP_START ? "start" :
                 type == VIBE_BEEP_END ? "end" :
                 type == VIBE_BEEP_EDIT ? "edit" :
                 type == VIBE_BEEP_READY ? "ready" : "send", BEEP_VOLUME);
    }
}
