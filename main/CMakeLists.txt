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
         "ui_font_cjk.c"
         "vibe_ui.c"
         "vibe_power.c"
         "vibe_app.c"
    INCLUDE_DIRS "."
    REQUIRES bsp bt esp_event esp_hw_support esp_netif esp_timer nvs_flash
)
