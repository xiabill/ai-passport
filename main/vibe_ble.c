#include "vibe_ble.h"
#include "vibe_ui.h"
#include "vibe_app.h"
#include "vibe_ota.h"

#include "esp_app_desc.h"
#include "vibe_protocol.h"
#include "demo_radio.h"

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
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

static const ble_uuid128_t s_ver_uuid = BLE_UUID128_INIT(
    0x31, 0x56, 0x4F, 0x4C, 0x4F, 0x46, 0x10, 0x9E,
    0x6B, 0x4A, 0x00, 0x00, 0x05, 0x00, 0x10, 0xF0);
static const ble_uuid128_t s_ota_uuid = BLE_UUID128_INIT(
    0x31, 0x56, 0x4F, 0x4C, 0x4F, 0x46, 0x10, 0x9E,
    0x6B, 0x4A, 0x00, 0x00, 0x06, 0x00, 0x10, 0xF0);

static uint16_t s_audio_handle;
static uint16_t s_event_handle;
static volatile uint16_t s_conn = BLE_HS_CONN_HANDLE_NONE;
// A second connection waiting to claim the device; see VIBE_CTRL_CLAIM.
static volatile uint16_t s_pending = BLE_HS_CONN_HANDLE_NONE;
static esp_timer_handle_t s_claim_timer;
static uint8_t s_addr_type;
static bool s_audio_sub;
static bool s_event_sub;
static uint32_t s_sent;
static uint32_t s_dropped;
static uint32_t s_drop_streak;
static char s_name[16];
static int s_gear = -1;  // -1 unknown, 0 idle, 1 fast
static esp_timer_handle_t s_idle_timer;
static esp_timer_handle_t s_eco_adv_timer;
static bool s_eco_mode;
static bool s_adv_paused;
static bool s_radio_down;

#define ECO_ADV_GRACE_US (60 * 1000000LL)

static int gap_event(struct ble_gap_event *event, void *arg);
static void take_over(uint16_t handle);
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
            {
                // Lets the bridge tell whether the device needs an upgrade.
                .uuid = &s_ver_uuid.u,
                .access_cb = chr_access,
                .flags = BLE_GATT_CHR_F_READ,
            },
            {
                // Firmware image stream; see vibe_ota.c for the framing.
                .uuid = &s_ota_uuid.u,
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
    (void)attr_handle;
    (void)arg;
    // During a handover the outgoing Mac can still land a write or two before
    // its link is gone. Only the current one gets to steer the device.
    if (ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR && conn_handle != s_conn) {
        uint8_t v = 0;
        if (conn_handle == s_pending && OS_MBUF_PKTLEN(ctxt->om) >= 1) {
            os_mbuf_copydata(ctxt->om, 0, 1, &v);
            if (v == VIBE_CTRL_CLAIM) take_over(conn_handle);
        }
        return 0;
    }
    if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
        if (ble_uuid_cmp(ctxt->chr->uuid, &s_ver_uuid.u) == 0) {
            const esp_app_desc_t *desc = esp_app_get_description();
            const char *v = desc ? desc->version : "";
            return os_mbuf_append(ctxt->om, v, strlen(v)) == 0
                ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
        }
        return BLE_ATT_ERR_READ_NOT_PERMITTED;
    }
    if (ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
        if (ble_uuid_cmp(ctxt->chr->uuid, &s_ota_uuid.u) == 0) {
            uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
            static uint8_t chunk[512];
            if (len > sizeof(chunk)) return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
            os_mbuf_copydata(ctxt->om, 0, len, chunk);
            vibe_ota_feed(chunk, len);
            return 0;
        }
        uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
        uint8_t v = 0;
        if (len < 1) return 0;
        os_mbuf_copydata(ctxt->om, 0, 1, &v);

        if (v == VIBE_CTRL_ACTIONS) {
            // 0x91 followed by one action code per gesture.
            uint8_t actions[VIBE_GESTURE_COUNT] = {0};
            uint16_t n = len - 1;
            if (n > VIBE_GESTURE_COUNT) n = VIBE_GESTURE_COUNT;
            os_mbuf_copydata(ctxt->om, 1, n, actions);
            vibe_app_on_actions(actions, n);
        } else if (v == VIBE_CTRL_LABEL && len >= 4) {
            uint8_t hdr[3];
            uint8_t data[200];
            os_mbuf_copydata(ctxt->om, 1, 3, hdr);
            uint16_t n = len - 4;
            if (n > sizeof(data)) n = sizeof(data);
            os_mbuf_copydata(ctxt->om, 4, n, data);
            vibe_ui_label_chunk(hdr[0], (uint16_t)(hdr[1] | (hdr[2] << 8)), data, n);
        } else if (v == VIBE_CTRL_LABEL_CLEAR && len >= 2) {
            uint8_t slot = 0;
            os_mbuf_copydata(ctxt->om, 1, 1, &slot);
            vibe_ui_label_clear(slot);
        } else if (v == VIBE_CTRL_POWER_MODE_STANDARD || v == VIBE_CTRL_POWER_MODE_ECO ||
                   v == VIBE_CTRL_POWER_MODE_ULTRA) {
            vibe_app_on_power_mode((uint8_t)(v - VIBE_CTRL_POWER_MODE_STANDARD));
        } else {
            vibe_app_on_typeless(v);
        }
        return 0;
    }
    return BLE_ATT_ERR_READ_NOT_PERMITTED;
}

// Manufacturer data in the scan response: the test company ID, then one byte
// saying whether some Mac is using the device. A Mac only connects to a free
// device on its own; a busy one is taken over only when the user asks.
#define VIBE_ADV_COMPANY 0xFFFF

static int advertise(void)
{
    // Called again on every connect and disconnect to refresh the busy flag,
    // and the fields cannot change under a running advertisement.
    if (ble_gap_adv_active()) ble_gap_adv_stop();
    const bool busy = s_conn != BLE_HS_CONN_HANDLE_NONE;
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
    const uint8_t mfg[3] = { VIBE_ADV_COMPANY & 0xFF, VIBE_ADV_COMPANY >> 8, busy ? 1 : 0 };
    rsp.mfg_data = mfg;
    rsp.mfg_data_len = sizeof(mfg);
    rc = ble_gap_adv_rsp_set_fields(&rsp);
    if (rc != 0) return rc;

    struct ble_gap_adv_params params = {0};
    params.conn_mode = BLE_GAP_CONN_MODE_UND;
    params.disc_mode = BLE_GAP_DISC_MODE_GEN;
    // A connected device keeps advertising so another Mac can take it over,
    // but nobody is waiting on that, so it does so at a tenth of the rate.
    params.itvl_min = busy ? 1600 : 160;  // 1 s : 100 ms (0.625 ms units)
    params.itvl_max = busy ? 2400 : 240;  // 1.5 s : 150 ms
    return ble_gap_adv_start(s_addr_type, NULL, BLE_HS_FOREVER, &params, gap_event,
                             NULL);
}

static void set_name_from_addr(void)
{
    uint8_t addr[6] = {0};
    ble_hs_id_copy_addr(s_addr_type, addr, NULL);
    // NimBLE stores the address little-endian: addr[5] and addr[4] are the
    // vendor prefix, identical on every FoloToy board, so naming from them gave
    // every device the same name and two of them could not be told apart. The
    // low bytes are the part that differs from one board to the next.
    snprintf(s_name, sizeof(s_name), "FoloVibe-%02X%02X", addr[1], addr[0]);
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
        // 6 s, matching the idle gear. The old 4 s was *shorter* than idle,
        // so the link was least tolerant exactly while streaming audio: one
        // burst of interference could drop a take mid-sentence.
        p.supervision_timeout = 600;
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

void vibe_ble_prepare_sleep(void)
{
    s_radio_down = true;
    if (s_idle_timer) esp_timer_stop(s_idle_timer);
    if (s_eco_adv_timer) esp_timer_stop(s_eco_adv_timer);
    // A connected Mac is deliberately released before sleeping. ble_gap_terminate
    // only *starts* the teardown: the packet still has to go out over the air and
    // be acknowledged, which takes at least one connection interval. Cutting power
    // immediately after left the Mac holding a connection to a device that was
    // already gone, so it kept ignoring the new advertisements after wake-up until
    // its own supervision timeout expired — the device looked stuck until it was
    // power-cycled. Wait for the disconnect to actually land.
    if (s_conn != BLE_HS_CONN_HANDLE_NONE) {
        // Speed the link up first so the teardown does not wait on the idle
        // interval plus slave latency.
        apply_gear(1);
        int rc = ble_gap_terminate(s_conn, BLE_ERR_REM_USER_CONN_TERM);
        if (rc != 0 && rc != BLE_HS_EALREADY) {
            ESP_LOGW(TAG, "sleep BLE disconnect rc=%d", rc);
        } else {
            const uint32_t step_ms = 10, limit_ms = 1200;
            uint32_t waited = 0;
            while (s_conn != BLE_HS_CONN_HANDLE_NONE && waited < limit_ms) {
                vTaskDelay(pdMS_TO_TICKS(step_ms));
                waited += step_ms;
            }
            if (s_conn != BLE_HS_CONN_HANDLE_NONE) {
                ESP_LOGW(TAG, "disconnect not confirmed after %u ms", waited);
            } else {
                ESP_LOGI(TAG, "link released in %u ms", waited);
            }
        }
    }
    // This is harmless when no advertising is active and prevents a pending
    // advertising cycle from starting while the device is asleep.
    ble_gap_adv_stop();
}

void vibe_ble_resume_radio(void)
{
    s_radio_down = false;
    if (s_conn == BLE_HS_CONN_HANDLE_NONE) {
        s_adv_paused = false;
        advertise();
        arm_eco_adv_timer();
    }
}

static void log_peer(const char *what, uint16_t handle)
{
    struct ble_gap_conn_desc d;
    if (ble_gap_conn_find(handle, &d) != 0) return;
    const uint8_t *a = d.peer_id_addr.val;
    ESP_LOGI(TAG, "%s handle=%u peer=%02X:%02X:%02X:%02X:%02X:%02X", what, handle,
             a[5], a[4], a[3], a[2], a[1], a[0]);
}

// The waiting connection asked for the device: drop the current one and
// promote it. Its notifications are enabled after this, so they land on the
// promoted handle.
static void take_over(uint16_t handle)
{
    if (handle != s_pending) return;
    esp_timer_stop(s_claim_timer);
    const uint16_t old = s_conn;
    s_pending = BLE_HS_CONN_HANDLE_NONE;
    s_conn = handle;
    s_audio_sub = false;
    s_event_sub = false;
    vibe_app_on_audio_sub(false);
    vibe_ui_labels_reset();
    s_gear = -1;
    apply_gear(0);
    log_peer("claimed by", handle);
    if (old != BLE_HS_CONN_HANDLE_NONE) ble_gap_terminate(old, BLE_ERR_REM_USER_CONN_TERM);
    if (!s_radio_down) advertise();
}

static void claim_timeout_cb(void *arg)
{
    (void)arg;
    const uint16_t h = s_pending;
    if (h == BLE_HS_CONN_HANDLE_NONE) return;
    ESP_LOGI(TAG, "handle=%u never claimed the device; dropping it", h);
    ble_gap_terminate(h, BLE_ERR_REM_USER_CONN_TERM);
}

static int gap_event(struct ble_gap_event *event, void *arg)
{
    (void)arg;
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status != 0) {
            // A failed attempt says nothing about a link that is already up.
            if (!s_radio_down) advertise();
            return 0;
        }
        if (s_radio_down) {
            ble_gap_terminate(event->connect.conn_handle, BLE_ERR_REM_USER_CONN_TERM);
            return 0;
        }
        log_peer("connect", event->connect.conn_handle);
        // Already in use: the newcomer gets a short window to claim the device
        // and is dropped if it does not. The current Mac keeps working until
        // then, and keeps the device if nobody asks.
        if (s_conn != BLE_HS_CONN_HANDLE_NONE && s_conn != event->connect.conn_handle) {
            if (s_pending != BLE_HS_CONN_HANDLE_NONE) {
                ble_gap_terminate(s_pending, BLE_ERR_REM_USER_CONN_TERM);
            }
            s_pending = event->connect.conn_handle;
            esp_timer_stop(s_claim_timer);
            esp_timer_start_once(s_claim_timer, VIBE_CLAIM_WINDOW_MS * 1000ULL);
            ESP_LOGI(TAG, "handle=%u waiting to claim; handle=%u keeps the device",
                     s_pending, s_conn);
            if (!s_radio_down) advertise();
            return 0;
        }
        s_conn = event->connect.conn_handle;
        vibe_ui_labels_reset();
        s_audio_sub = false;
        s_event_sub = false;
        ble_att_set_preferred_mtu(185);
        s_gear = -1;
        apply_gear(0);
        s_adv_paused = false;
        if (s_eco_adv_timer) esp_timer_stop(s_eco_adv_timer);
        vibe_app_on_ble_link(true);
        ESP_LOGI(TAG, "connected handle=%u", s_conn);
        if (!s_radio_down) advertise();
        return 0;

    case BLE_GAP_EVENT_DISCONNECT:
        ESP_LOGI(TAG, "disconnect handle=%u reason=%d",
                 event->disconnect.conn.conn_handle, event->disconnect.reason);
        if (event->disconnect.conn.conn_handle == s_pending) {
            s_pending = BLE_HS_CONN_HANDLE_NONE;
            esp_timer_stop(s_claim_timer);
            return 0;
        }
        if (event->disconnect.conn.conn_handle != s_conn) return 0;  // the one we handed off
        s_conn = BLE_HS_CONN_HANDLE_NONE;
        s_audio_sub = false;
        s_event_sub = false;
        s_gear = -1;
        if (s_idle_timer) esp_timer_stop(s_idle_timer);
        if (s_eco_adv_timer) esp_timer_stop(s_eco_adv_timer);
        vibe_app_on_audio_sub(false);
        vibe_app_on_ble_link(false);
        if (!s_radio_down) {
            advertise();
            arm_eco_adv_timer();
        }
        return 0;

    case BLE_GAP_EVENT_SUBSCRIBE:
        if (event->subscribe.conn_handle != s_conn) return 0;
        if (event->subscribe.attr_handle == s_audio_handle) {
            s_audio_sub = event->subscribe.cur_notify;
            vibe_app_on_audio_sub(s_audio_sub);
            ESP_LOGI(TAG, "audio notify %d", s_audio_sub);
        } else if (event->subscribe.attr_handle == s_event_handle) {
            s_event_sub = event->subscribe.cur_notify;
            ESP_LOGI(TAG, "event notify %d", s_event_sub);
        }
        return 0;

    case BLE_GAP_EVENT_MTU:
        ESP_LOGI(TAG, "MTU %u", event->mtu.value);
        return 0;

    case BLE_GAP_EVENT_ADV_COMPLETE:
        if (!s_adv_paused && !s_radio_down) advertise();
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
    if (!s_claim_timer) {
        const esp_timer_create_args_t ct = {
            .callback = claim_timeout_cb,
            .name = "ble_claim",
        };
        esp_timer_create(&ct, &s_claim_timer);
    }
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
        // A run of these means the send queue is not draining; left unnoticed
        // it ends as a supervision timeout, so say so once per run.
        if (++s_drop_streak == 10) ESP_LOGW(TAG, "out of BLE buffers; audio backing up");
        return ESP_ERR_NO_MEM;
    }
    int rc = ble_gatts_notify_custom(s_conn, handle, om);
    if (rc != 0) {
        os_mbuf_free_chain(om);
        s_dropped++;
        if (++s_drop_streak == 10) ESP_LOGW(TAG, "audio notify failing rc=%d", rc);
        return ESP_FAIL;
    }
    s_sent++;
    s_drop_streak = 0;
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
    if (!s_event_sub) {
        ESP_LOGW(TAG, "drop event %u: button-event notify is not subscribed", ev);
        return ESP_ERR_INVALID_STATE;
    }
    esp_err_t err = notify_buf(s_event_handle, &ev, 1);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "event %u notify failed: %s", ev, esp_err_to_name(err));
    } else {
        ESP_LOGI(TAG, "event %u sent to Mac", ev);
    }
    return err;
}

void vibe_ble_stats(uint32_t *sent, uint32_t *dropped)
{
    if (sent) *sent = s_sent;
    if (dropped) *dropped = s_dropped;
}
