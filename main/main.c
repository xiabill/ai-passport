// main/main.c —— Vibe Typeless companion: 开机进入语音页，不再走硬件 demo 菜单。
#include "bsp_audio.h"
#include "bsp_battery.h"
#include "bsp_button.h"
#include "bsp_display.h"
#include "bsp_i2c.h"
#include "bsp_pins.h"
#include "vibe_app.h"

#include "esp_log.h"
#include "esp_sleep.h"

static const char *TAG = "main";

// 按键回调跑在 button 任务里，只做轻量派发。
static void on_key(bsp_btn_t btn, bsp_btn_ev_t ev, void *user)
{
    (void)user;
    vibe_app_on_button(btn, ev);
}

void app_main(void)
{
    ESP_LOGI(TAG, "FoloToy AI Passport vibe-typeless 启动");
    esp_sleep_wakeup_cause_t wakeup = esp_sleep_get_wakeup_cause();
    if (wakeup != ESP_SLEEP_WAKEUP_UNDEFINED) {
        ESP_LOGI(TAG, "休眠唤醒原因: %d", wakeup);
    }

    bsp_i2c_init();
    bsp_i2c_scan();

    if (bsp_display_init() != ESP_OK || !bsp_lvgl_init()) {
        ESP_LOGE(TAG, "显示/LVGL 初始化失败。"
                      "检查 SPI 接线(MOSI=%d SCLK=%d CS=%d DC=%d BL=%d)",
                 BSP_LCD_MOSI, BSP_LCD_SCLK, BSP_LCD_CS, BSP_LCD_DC, BSP_LCD_BL);
        return;
    }
    bsp_display_backlight(100);

    if (bsp_button_init(on_key, NULL) != ESP_OK) {
        ESP_LOGE(TAG, "按键初始化失败");
        return;
    }
    if (bsp_audio_init() != ESP_OK) {
        ESP_LOGE(TAG, "音频初始化失败，录音不可用");
    }
    if (bsp_battery_init() != ESP_OK) {
        ESP_LOGW(TAG, "电量计不可用");
    }

    if (bsp_lvgl_lock(1000)) {
        esp_err_t err = vibe_app_start();
        bsp_lvgl_unlock();
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "vibe_app_start 失败: %s", esp_err_to_name(err));
        }
    }
}
