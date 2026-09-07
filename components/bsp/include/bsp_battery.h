// components/bsp/include/bsp_battery.h
// CellWise CW2017 电量计:I2C 0x63,与 ES8311 共用总线。
// 芯片自带 Li-Poly profile,直接给 SOC%,无需外部分压电阻与查表。
#pragma once

#include "esp_err.h"

// 初始化。内部会调 bsp_i2c_init()(幂等)。
// 芯片不应答时返回 ESP_ERR_NOT_FOUND —— 上层可据此在 UI 上标记该项不可用。
esp_err_t bsp_battery_init(void);

// 剩余电量百分比 0..100;读失败返回 -1。
int bsp_battery_soc(void);

// 电池电压 mV;读失败返回 -1。
int bsp_battery_mv(void);

// 让电量计进入睡眠。深度睡眠只断 MCU 核心,挂在常通 3.3V 轨上的 CW2017
// 仍会持续耗电,入睡前需要单独点名。唤醒后由 bsp_battery_init() 恢复。
esp_err_t bsp_battery_sleep(void);
