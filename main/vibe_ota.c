#include "vibe_ota.h"

#include "esp_log.h"
#include "esp_ota_ops.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include <string.h>

static const char *TAG = "vibe_ota";

static vibe_ota_state_t s_state;
static esp_ota_handle_t s_handle;
static const esp_partition_t *s_target;
static uint32_t s_expected;
static uint32_t s_received;

static void fail(const char *why)
{
    ESP_LOGE(TAG, "%s", why);
    if (s_handle) {
        esp_ota_abort(s_handle);
        s_handle = 0;
    }
    s_target = NULL;
    s_expected = s_received = 0;
    s_state = VIBE_OTA_FAILED;
}

static void finish_task(void *arg)
{
    (void)arg;
    // Give the bridge a moment to see the completed state before rebooting.
    vTaskDelay(pdMS_TO_TICKS(1500));
    esp_restart();
}

static void begin(uint32_t length)
{
    s_target = esp_ota_get_next_update_partition(NULL);
    if (!s_target) {
        fail("no OTA slot available");
        return;
    }
    if (length == 0 || length > s_target->size) {
        ESP_LOGE(TAG, "image is %u bytes; slot %s holds %u",
                 (unsigned)length, s_target->label, (unsigned)s_target->size);
        s_state = VIBE_OTA_FAILED;
        return;
    }
    esp_err_t err = esp_ota_begin(s_target, length, &s_handle);
    if (err != ESP_OK) {
        s_handle = 0;
        fail(esp_err_to_name(err));
        return;
    }
    s_expected = length;
    s_received = 0;
    s_state = VIBE_OTA_RECEIVING;
    ESP_LOGI(TAG, "receiving %u bytes into %s", (unsigned)length, s_target->label);
}

void vibe_ota_feed(const uint8_t *data, size_t len)
{
    if (!data || len == 0) return;

    if (s_state != VIBE_OTA_RECEIVING) {
        // Only a well-formed header starts a transfer, so stray writes on the
        // characteristic cannot put the device into an upgrade.
        if (len >= VIBE_OTA_HEADER_LEN && data[0] == 'F' && data[1] == 'W') {
            uint32_t length = (uint32_t)data[2] | ((uint32_t)data[3] << 8) |
                              ((uint32_t)data[4] << 16) | ((uint32_t)data[5] << 24);
            begin(length);
            if (len > VIBE_OTA_HEADER_LEN && s_state == VIBE_OTA_RECEIVING) {
                vibe_ota_feed(data + VIBE_OTA_HEADER_LEN, len - VIBE_OTA_HEADER_LEN);
            }
        }
        return;
    }

    size_t take = len;
    if (s_received + take > s_expected) take = s_expected - s_received;
    esp_err_t err = esp_ota_write(s_handle, data, take);
    if (err != ESP_OK) {
        fail(esp_err_to_name(err));
        return;
    }
    s_received += take;
    if (s_received < s_expected) return;

    s_state = VIBE_OTA_APPLYING;
    err = esp_ota_end(s_handle);
    s_handle = 0;
    if (err != ESP_OK) {
        // A truncated or corrupt image is rejected here, before it can be
        // marked bootable.
        fail(esp_err_to_name(err));
        return;
    }
    err = esp_ota_set_boot_partition(s_target);
    if (err != ESP_OK) {
        fail(esp_err_to_name(err));
        return;
    }
    ESP_LOGI(TAG, "installed into %s; restarting", s_target->label);
    s_state = VIBE_OTA_DONE;
    xTaskCreate(finish_task, "vibe_ota_end", 2048, NULL, 5, NULL);
}

void vibe_ota_abort(void)
{
    if (s_state == VIBE_OTA_RECEIVING) fail("aborted by the bridge");
}

vibe_ota_state_t vibe_ota_state(void) { return s_state; }

uint8_t vibe_ota_percent(void)
{
    if (s_expected == 0) return 0;
    return (uint8_t)((uint64_t)s_received * 100U / s_expected);
}
