#include "vibe_ble.h"
#include "vibe_app.h"
#include "vibe_protocol.h"
#include "demo_radio.h"

#include "esp_log.h"
#include "esp_timer.h"
#include "host/ble_att.h"
#include "host/ble_gap.h"
#include "host/ble_gatt.h"
#include "host/ble_hs.h"
#include "host/ble_uuid.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "os/os_mbuf.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

#include <stdio.h>
#include <string.h>

static const char *TAG = "vibe_ble";

// F0100001-0000-4A6B-9E10-464F4C4F5631  ("FOLOV1" in the node field)
static const ble_uuid128_t s_svc_uuid = BLE_UUID128_INIT(
    0x31, 0x56, 0x4F, 0x4C, 0x4F, 0x46, 0x10, 0x9E,
    0x6B, 0x4A, 0x00, 0x00, 0x01, 0x00, 0x10, 0xF0);
static const ble_uuid128_t s_audio_uuid = BLE_UUID128_INIT(
    0x31, 0x56, 0x4F, 0x4C, 0x4F, 0x46, 0x10, 0x9E,
    0x6B, 0x4A, 0x00, 0x00, 0x02, 0x00, 0x10, 0xF0);
static const ble_uuid128_t s_event_uuid = BLE_UUID128_INIT(
    0x31, 0x56, 0x4F, 0x4C, 0x4F, 0x46, 0x10, 0x9E,
    0x6B, 0x4A, 0x00, 0x00, 0x03, 0x00, 0x10, 0xF0);
static const ble_uuid128_t s_ctrl_uuid = BLE_UUID128_INIT(
    0x31, 0x56, 0x4F, 0x4C, 0x4F, 0x46, 0x10, 0x9E,
    0x6B, 0x4A, 0x00, 0x00, 0x04, 0x00, 0x10, 0xF0);

static uint16_t s_audio_handle;
static uint16_t s_event_handle;
static uint16_t s_conn = BLE_HS_CONN_HANDLE_NONE;
static uint8_t s_addr_type;
static bool s_audio_sub;
static bool s_event_sub;
static uint32_t s_sent;
static uint32_t s_dropped;
static char s_name[16];
static int s_gear = -1;  // -1 unknown, 0 idle, 1 fast
static esp_timer_handle_t s_idle_timer;
static esp_timer_handle_t s_eco_adv_timer;
static bool s_eco_mode;
static bool s_adv_paused;
static bool s_light_sleeping;

#define ECO_ADV_GRACE_US (60 * 1000000LL)

static int gap_event(struct ble_gap_event *event, void *arg);
static int chr_access(uint16_t conn_handle, uint16_t attr_handle,
                      struct ble_gatt_access_ctxt *ctxt, void *arg);

static const struct ble_gatt_svc_def s_svcs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &s_svc_uuid.u,
        .characteristics = (struct ble_gatt_chr_def[]){
            {
                .uuid = &s_audio_uuid.u,
                .access_cb = chr_access,
                .flags = BLE_GATT_CHR_F_NOTIFY,
                .val_handle = &s_audio_handle,
            },
            {
                .uuid = &s_event_uuid.u,
                .access_cb = chr_access,
                .flags = BLE_GATT_CHR_F_NOTIFY,
                .val_handle = &s_event_handle,
            },
            {
                .uuid = &s_ctrl_uuid.u,
                .access_cb = chr_access,
                .flags = BLE_GATT_CHR_F_WRITE_NO_RSP | BLE_GATT_CHR_F_WRITE,
            },
            {0},
        },
    },
    {0},
};

static int chr_access(uint16_t conn_handle, uint16_t attr_handle,
                      struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;
    if (ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
        uint8_t v = 0;
        if (OS_MBUF_PKTLEN(ctxt->om) >= 1) {
            os_mbuf_copydata(ctxt->om, 0, 1, &v);
            if (v == VIBE_CTRL_POWER_MODE_STANDARD || v == VIBE_CTRL_POWER_MODE_ECO) {
                vibe_app_on_power_mode(v == VIBE_CTRL_POWER_MODE_ECO ? 1 : 0);
            } else {
                vibe_app_on_typeless(v);
            }
        }
        return 0;
    }
    return BLE_ATT_ERR_READ_NOT_PERMITTED;
}

static int advertise(void)
{
    struct ble_hs_adv_fields fields = {0};
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.uuids128 = (ble_uuid128_t *)&s_svc_uuid;
    fields.num_uuids128 = 1;
    fields.uuids128_is_complete = 1;
    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) return rc;

    struct ble_hs_adv_fields rsp = {0};
    rsp.name = (const uint8_t *)s_name;
    rsp.name_len = strlen(s_name);
    rsp.name_is_complete = 1;
    rc = ble_gap_adv_rsp_set_fields(&rsp);
    if (rc != 0) return rc;

    struct ble_gap_adv_params params = {0};
    params.conn_mode = BLE_GAP_CONN_MODE_UND;
    params.disc_mode = BLE_GAP_DISC_MODE_GEN;
    params.itvl_min = 160;  // 100 ms (0.625 ms units)
    params.itvl_max = 240;  // 150 ms
    return ble_gap_adv_start(s_addr_type, NULL, BLE_HS_FOREVER, &params, gap_event,
                             NULL);
}

static void set_name_from_addr(void)
{
    uint8_t addr[6] = {0};
    ble_hs_id_copy_addr(s_addr_type, addr, NULL);
    snprintf(s_name, sizeof(s_name), "FoloVibe-%02X%02X", addr[5], addr[4]);
    ble_svc_gap_device_name_set(s_name);
    ESP_LOGI(TAG, "GAP name %s", s_name);
}

static void apply_gear(int gear)
{
    if (s_conn == BLE_HS_CONN_HANDLE_NONE) return;
    if (s_gear == gear) return;
    struct ble_gap_upd_params p = {0};
    if (gear) {
        p.itvl_min = 6;   // 7.5 ms
        p.itvl_max = 12;  // 15 ms
        p.latency = 0;
        p.supervision_timeout = 400;
    } else {
        p.itvl_min = 24;  // 30 ms
        p.itvl_max = 40;  // 50 ms
        p.latency = 20;
        p.supervision_timeout = 600;  // 6 s > 2*(1+20)*50 ms
    }
    int rc = ble_gap_update_params(s_conn, &p);
    if (rc == 0 || rc == BLE_HS_EALREADY) {
        s_gear = gear;
        ESP_LOGI(TAG, "link gear %s", gear ? "fast" : "idle");
    } else {
        ESP_LOGW(TAG, "conn update rc=%d", rc);
    }
}

static void idle_timer_cb(void *arg)
{
    (void)arg;
    apply_gear(0);
}

static void eco_adv_timeout_cb(void *arg)
{
    (void)arg;
    if (s_eco_mode && s_conn == BLE_HS_CONN_HANDLE_NONE && !s_adv_paused) {
        s_adv_paused = true;
        ble_gap_adv_stop();
        ESP_LOGI(TAG, "eco mode: advertising paused while idle");
    }
}

static void arm_eco_adv_timer(void)
{
    if (!s_eco_adv_timer || !s_eco_mode || s_conn != BLE_HS_CONN_HANDLE_NONE) return;
    esp_timer_stop(s_eco_adv_timer);
    esp_timer_start_once(s_eco_adv_timer, ECO_ADV_GRACE_US);
}

void vibe_ble_link_fast(bool fast)
{
    if (s_idle_timer) esp_timer_stop(s_idle_timer);
    if (fast) {
        apply_gear(1);
    } else if (s_idle_timer) {
        esp_timer_start_once(s_idle_timer, 2000000);
    } else {
        apply_gear(0);
    }
}

void vibe_ble_set_power_mode(bool eco)
{
    s_eco_mode = eco;
    if (s_eco_adv_timer) esp_timer_stop(s_eco_adv_timer);
    if (!eco && s_adv_paused && s_conn == BLE_HS_CONN_HANDLE_NONE) {
        s_adv_paused = false;
        advertise();
    } else if (eco && s_conn == BLE_HS_CONN_HANDLE_NONE) {
        arm_eco_adv_timer();
    }
    ESP_LOGI(TAG, "BLE power mode %s", eco ? "eco" : "standard");
}

void vibe_ble_note_activity(void)
{
    if (!s_eco_mode) return;
    if (s_eco_adv_timer) esp_timer_stop(s_eco_adv_timer);
    if (s_adv_paused && s_conn == BLE_HS_CONN_HANDLE_NONE) {
        s_adv_paused = false;
        advertise();
    }
    arm_eco_adv_timer();
}

void vibe_ble_prepare_light_sleep(void)
{
    s_light_sleeping = true;
    if (s_idle_timer) esp_timer_stop(s_idle_timer);
    if (s_eco_adv_timer) esp_timer_stop(s_eco_adv_timer);
    // A connected Mac is deliberately released before light sleep. This
    // avoids keeping the radio link alive while the CPU and audio path sleep.
    if (s_conn != BLE_HS_CONN_HANDLE_NONE) {
        int rc = ble_gap_terminate(s_conn, BLE_ERR_REM_USER_CONN_TERM);
        if (rc != 0 && rc != BLE_HS_EALREADY) {
            ESP_LOGW(TAG, "light sleep BLE disconnect rc=%d", rc);
        }
    }
    // This is harmless when no advertising is active and prevents a pending
    // advertising cycle from starting while the device is asleep.
    ble_gap_adv_stop();
}

void vibe_ble_resume_after_light_sleep(void)
{
    s_light_sleeping = false;
    if (s_conn == BLE_HS_CONN_HANDLE_NONE) {
        s_adv_paused = false;
        advertise();
        arm_eco_adv_timer();
    }
}

static int gap_event(struct ble_gap_event *event, void *arg)
{
    (void)arg;
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status != 0) {
            s_conn = BLE_HS_CONN_HANDLE_NONE;
            if (!s_light_sleeping) advertise();
            return 0;
        }
        if (s_light_sleeping) {
            ble_gap_terminate(event->connect.conn_handle, BLE_ERR_REM_USER_CONN_TERM);
            return 0;
        }
        s_conn = event->connect.conn_handle;
        s_audio_sub = false;
        s_event_sub = false;
        ble_att_set_preferred_mtu(185);
        s_gear = -1;
        apply_gear(0);
        s_adv_paused = false;
        if (s_eco_adv_timer) esp_timer_stop(s_eco_adv_timer);
        vibe_app_on_ble_link(true);
        ESP_LOGI(TAG, "connected handle=%u", s_conn);
        return 0;

    case BLE_GAP_EVENT_DISCONNECT:
        ESP_LOGI(TAG, "disconnect reason=%d", event->disconnect.reason);
        s_conn = BLE_HS_CONN_HANDLE_NONE;
        s_audio_sub = false;
        s_event_sub = false;
        s_gear = -1;
        if (s_idle_timer) esp_timer_stop(s_idle_timer);
        if (s_eco_adv_timer) esp_timer_stop(s_eco_adv_timer);
        vibe_app_on_audio_sub(false);
        vibe_app_on_ble_link(false);
        if (!s_light_sleeping) {
            advertise();
            arm_eco_adv_timer();
        }
        return 0;

    case BLE_GAP_EVENT_SUBSCRIBE:
        if (event->subscribe.attr_handle == s_audio_handle) {
            s_audio_sub = event->subscribe.cur_notify;
            vibe_app_on_audio_sub(s_audio_sub);
            ESP_LOGI(TAG, "audio notify %d", s_audio_sub);
        } else if (event->subscribe.attr_handle == s_event_handle) {
            s_event_sub = event->subscribe.cur_notify;
        }
        return 0;

    case BLE_GAP_EVENT_MTU:
        ESP_LOGI(TAG, "MTU %u", event->mtu.value);
        return 0;

    case BLE_GAP_EVENT_ADV_COMPLETE:
        if (s_conn == BLE_HS_CONN_HANDLE_NONE && !s_adv_paused && !s_light_sleeping) advertise();
        return 0;

    default:
        return 0;
    }
}

static void on_reset(int reason)
{
    ESP_LOGE(TAG, "nimble reset %d", reason);
}

static void on_sync(void)
{
    int rc = ble_hs_util_ensure_addr(0);
    if (rc == 0) rc = ble_hs_id_infer_auto(0, &s_addr_type);
    if (rc == 0) {
        set_name_from_addr();
        rc = advertise();
    }
    if (rc != 0) ESP_LOGE(TAG, "sync/adv failed %d", rc);
}

static void host_task(void *arg)
{
    (void)arg;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

esp_err_t vibe_ble_start(void)
{
    esp_err_t err = demo_radio_nvs_prepare();
    if (err != ESP_OK) return err;

    err = nimble_port_init();
    if (err != ESP_OK) return err;

    ble_hs_cfg.reset_cb = on_reset;
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.sm_bonding = 0;
    ble_hs_cfg.sm_mitm = 0;
    ble_hs_cfg.sm_sc = 0;

    ble_svc_gap_init();
    ble_svc_gatt_init();
    int rc = ble_gatts_count_cfg(s_svcs);
    if (rc == 0) rc = ble_gatts_add_svcs(s_svcs);
    if (rc != 0) {
        ESP_LOGE(TAG, "gatt register %d", rc);
        return ESP_FAIL;
    }

    strcpy(s_name, "FoloVibe");
    ble_svc_gap_device_name_set(s_name);
    ble_att_set_preferred_mtu(185);
    if (!s_idle_timer) {
        const esp_timer_create_args_t t = {
            .callback = idle_timer_cb,
            .name = "ble_idle",
        };
        esp_timer_create(&t, &s_idle_timer);
    }
    if (!s_eco_adv_timer) {
        const esp_timer_create_args_t t = {
            .callback = eco_adv_timeout_cb,
            .name = "ble_eco_adv",
        };
        esp_timer_create(&t, &s_eco_adv_timer);
    }
    nimble_port_freertos_init(host_task);
    return ESP_OK;
}

bool vibe_ble_connected(void)
{
    return s_conn != BLE_HS_CONN_HANDLE_NONE;
}

bool vibe_ble_audio_subscribed(void)
{
    return s_audio_sub;
}

const char *vibe_ble_name(void)
{
    return s_name[0] ? s_name : "FoloVibe";
}

static esp_err_t notify_buf(uint16_t handle, const uint8_t *data, size_t len)
{
    if (s_conn == BLE_HS_CONN_HANDLE_NONE) {
        s_dropped++;
        return ESP_ERR_INVALID_STATE;
    }
    struct os_mbuf *om = ble_hs_mbuf_from_flat(data, len);
    if (!om) {
        s_dropped++;
        return ESP_ERR_NO_MEM;
    }
    int rc = ble_gatts_notify_custom(s_conn, handle, om);
    if (rc != 0) {
        os_mbuf_free_chain(om);
        s_dropped++;
        return ESP_FAIL;
    }
    s_sent++;
    return ESP_OK;
}

esp_err_t vibe_ble_audio_send(const uint8_t *pkt, size_t len)
{
    if (!s_audio_sub) {
        s_dropped++;
        return ESP_ERR_INVALID_STATE;
    }
    return notify_buf(s_audio_handle, pkt, len);
}

esp_err_t vibe_ble_event_send(uint8_t ev)
{
    if (!s_event_sub) return ESP_ERR_INVALID_STATE;
    return notify_buf(s_event_handle, &ev, 1);
}

void vibe_ble_stats(uint32_t *sent, uint32_t *dropped)
{
    if (sent) *sent = s_sent;
    if (dropped) *dropped = s_dropped;
}
