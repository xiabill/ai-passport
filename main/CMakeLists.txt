idf_component_register(
    SRCS "main.c"
         "ui_pixel.c"
         "ui_pixel_math.c"
         "demo_radio.c"
         "vibe_adpcm.c"
         "vibe_protocol.c"
         "vibe_state.c"
         "vibe_ble.c"
         "vibe_audio.c"
         "vibe_ui.c"
         "vibe_power.c"
         "ui_font_cjk.c"
         "vibe_app.c"
    INCLUDE_DIRS "."
    REQUIRES bsp bt esp_driver_usb_serial_jtag esp_event esp_hw_support esp_netif esp_timer nvs_flash
)
