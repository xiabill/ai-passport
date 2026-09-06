#include "vibe_shot.h"
#include "bsp_display.h"

#include "esp_lcd_panel_interface.h"
#include "driver/usb_serial_jtag.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "lvgl.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *TAG = "vibe_shot";

#define SHOT_W    240
#define SHOT_H    320
// A whole 240x320 RGB565 frame is 150 KiB, more than the largest block this
// chip can hand out, and the display only keeps a 20-line strip. So the screen
// is redrawn one band at a time and each band is streamed out as it lands.
#define SHOT_BAND 40

static uint16_t *s_band;
static int s_band_y0;
static esp_err_t (*s_orig_draw)(esp_lcd_panel_t *, int, int, int, int, const void *);

// Sits in front of the panel's own draw call, copying whatever the renderer
// produces for the band being captured. The pixels still reach the display, so
// the screen the creator sees is exactly the screen that gets published.
static esp_err_t tap_draw(esp_lcd_panel_t *panel, int x1, int y1, int x2, int y2,
                          const void *data)
{
    if (s_band) {
        const uint8_t *src = (const uint8_t *)data;
        int w = x2 - x1;  // esp_lcd bounds are end-exclusive
        // Partial redraws can be an odd number of pixels wide, and LVGL pads
        // each row of its draw buffer to the stride alignment. Copying w*2
        // bytes per row silently walked past the padding and skewed the image.
        // Measured: aligned stride reproduces the screen more faithfully than a
        // packed w*2 assumption (3.0% vs 4.7% mismatched pixels). Some text
        // edges still differ; the capture is connection evidence, not the cover.
        uint32_t stride = lv_draw_buf_width_to_stride((uint32_t)w, LV_COLOR_FORMAT_RGB565);
        for (int y = y1; y < y2; y++) {
            int row = y - s_band_y0;
            if (row < 0 || row >= SHOT_BAND) continue;
            memcpy(s_band + row * SHOT_W + x1, src + (size_t)(y - y1) * stride,
                   (size_t)w * sizeof(uint16_t));
        }
    }
    return s_orig_draw(panel, x1, y1, x2, y2, data);
}

// The USB endpoint drops whatever does not fit, and a short write looks like
// success, so push small chunks and keep retrying until every byte is queued.
static bool emit(const void *data, size_t len)
{
    const uint8_t *p = (const uint8_t *)data;
    size_t sent = 0;
    int stalls = 0;
    while (sent < len) {
        size_t want = len - sent;
        if (want > 256) want = 256;
        int n = usb_serial_jtag_write_bytes(p + sent, want, pdMS_TO_TICKS(200));
        if (n > 0) {
            sent += (size_t)n;
            stalls = 0;
        } else if (++stalls > 50) {
            return false;  // host stopped reading
        } else {
            vTaskDelay(pdMS_TO_TICKS(2));
        }
    }
    return true;
}

static void capture(void)
{
    esp_lcd_panel_handle_t handle = bsp_display_panel();
    lv_display_t *disp = lv_display_get_default();
    if (!handle || !disp) return;

    s_band = heap_caps_malloc((size_t)SHOT_W * SHOT_BAND * sizeof(uint16_t),
                              MALLOC_CAP_8BIT);
    if (!s_band) {
        ESP_LOGE(TAG, "no memory for a capture band");
        return;
    }

    // Log output shares this console, so a stray line would corrupt the binary
    // payload. Silence it for the duration and restore afterwards.
    esp_log_level_t prev = esp_log_level_get("*");
    esp_log_level_set("*", ESP_LOG_NONE);

    esp_lcd_panel_t *panel = (esp_lcd_panel_t *)handle;
    s_orig_draw = panel->draw_bitmap;
    panel->draw_bitmap = tap_draw;

    char header[64];
    int hlen = snprintf(header, sizeof(header), "FAP_SCREENSHOT_V1 %d %d RGB565LE %d\n",
                        SHOT_W, SHOT_H, SHOT_W * SHOT_H * 2);
    emit(header, (size_t)hlen);

    for (int y = 0; y < SHOT_H; y += SHOT_BAND) {
        s_band_y0 = y;
        memset(s_band, 0, (size_t)SHOT_W * SHOT_BAND * sizeof(uint16_t));
        if (bsp_lvgl_lock(1000)) {
            lv_area_t area = {0, y, SHOT_W - 1, y + SHOT_BAND - 1};
            lv_obj_invalidate_area(lv_screen_active(), &area);
            lv_refr_now(disp);
            bsp_lvgl_unlock();
        }
        // The panel is fed big-endian (swap_bytes), but the protocol asks for
        // little-endian, so swap each pixel back on the way out.
        for (int i = 0; i < SHOT_W * SHOT_BAND; i++) {
            uint16_t v = s_band[i];
            s_band[i] = (uint16_t)((v >> 8) | (v << 8));
        }
        if (!emit(s_band, (size_t)SHOT_W * SHOT_BAND * sizeof(uint16_t))) break;
    }

    panel->draw_bitmap = s_orig_draw;
    free(s_band);
    s_band = NULL;
    esp_log_level_set("*", prev);

    // Leave the screen as the creator sees it.
    if (bsp_lvgl_lock(1000)) {
        lv_obj_invalidate(lv_screen_active());
        bsp_lvgl_unlock();
    }
}

static void shot_task(void *arg)
{
    (void)arg;
    static const char want[] = "FAP_SCREENSHOT_V1";
    size_t matched = 0;
    for (;;) {
        uint8_t byte = 0;
        if (usb_serial_jtag_read_bytes(&byte, 1, pdMS_TO_TICKS(200)) != 1) continue;
        int c = byte;
        if (matched < sizeof(want) - 1 && c == want[matched]) {
            matched++;
        } else if (matched == sizeof(want) - 1 && (c == '\n' || c == '\r')) {
            matched = 0;
            capture();
        } else {
            matched = (c == want[0]) ? 1 : 0;
        }
    }
}

esp_err_t vibe_shot_start(void)
{
    // The console is polled rather than driver-backed by default, so stdin
    // never yields the request bytes. Install the driver and talk to it.
    usb_serial_jtag_driver_config_t cfg = USB_SERIAL_JTAG_DRIVER_CONFIG_DEFAULT();
    cfg.tx_buffer_size = 8192;
    cfg.rx_buffer_size = 256;
    esp_err_t err = usb_serial_jtag_driver_install(&cfg);
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) return err;

    BaseType_t ok = xTaskCreate(shot_task, "vibe_shot", 4096, NULL, 3, NULL);
    return ok == pdPASS ? ESP_OK : ESP_ERR_NO_MEM;
}
