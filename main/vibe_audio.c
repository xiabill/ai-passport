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

static TaskHandle_t s_task;
static volatile bool s_recording;
static vibe_adpcm_state_t s_adpcm;
static uint16_t s_seq;
static int s_quiet;

static uint8_t peak_level(const int16_t *pcm, int n)
{
    int peak = 0;
    for (int i = 0; i < n; i++) {
        int v = pcm[i];
        if (v < 0) v = -v;
        if (v > peak) peak = v;
    }
    int level = peak / 1024;
    if (level > 16) level = 16;
    return (uint8_t)level;
}

static void send_eos(void)
{
    uint8_t hdr[VIBE_AUDIO_HDR_LEN];
    vibe_packet_eos(hdr, s_seq++);
    vibe_ble_audio_send(hdr, VIBE_AUDIO_HDR_LEN);
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

    for (;;) {
        if (!s_recording) {
            vTaskDelay(pdMS_TO_TICKS(20));
            continue;
        }

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
