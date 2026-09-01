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

static const char *TAG = "vibe_audio";

#define SILENCE_PEAK 500
#define SILENCE_BLOCKS (30 * 50)  // 30 s of 20 ms blocks
#define BEEP_SAMPLE_RATE 8000U
#define BEEP_SAMPLES 256U
#define BEEP_AMPLITUDE 6000

static TaskHandle_t s_task;
static volatile bool s_recording;
static vibe_adpcm_state_t s_adpcm;
static uint16_t s_seq;
static int s_quiet;
static volatile bool s_beep_pending;

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

static void play_button_beep(void)
{
    ESP_LOGI(TAG, "button beep");
    if (bsp_audio_set_format(BEEP_SAMPLE_RATE, 16, 1) != ESP_OK) {
        ESP_LOGW(TAG, "button beep format failed");
        return;
    }

    // 约 32 ms 的短方波，带极短淡入淡出，避免在扬声器上产生爆音。
    bsp_audio_set_volume(25);
    int16_t pcm[64];
    for (unsigned base = 0; base < BEEP_SAMPLES; base += 64) {
        for (unsigned i = 0; i < 64; i++) {
            unsigned n = base + i;
            int amp = BEEP_AMPLITUDE;
            if (n < 12) amp = (amp * (int)n) / 12;
            else if (n >= BEEP_SAMPLES - 12) {
                amp = (amp * (int)(BEEP_SAMPLES - n)) / 12;
            }
            pcm[i] = ((n / 2U) & 1U) ? (int16_t)amp : (int16_t)-amp;
        }
        if (bsp_audio_write(pcm, sizeof(pcm)) != ESP_OK) {
            ESP_LOGW(TAG, "button beep write failed");
            break;
        }
    }
    // The codec write fills the DMA queue asynchronously. Let the 32 ms tone
    // drain before closing the codec, otherwise suspend can truncate it.
    vTaskDelay(pdMS_TO_TICKS(45));
    bsp_audio_suspend();
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
        // 在录音开始前或刚结束后播放，避免和 I2S 采集并行访问 codec。
        if (s_beep_pending && (!capture_started || !s_recording)) {
            s_beep_pending = false;
            play_button_beep();
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

void vibe_audio_beep(void)
{
    s_beep_pending = true;
}
