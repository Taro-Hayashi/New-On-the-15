#include <stdio.h>

#include <pb_decode.h>
#include <pb_encode.h>
#include <zephyr/logging/log.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/util.h>
#include <zmk/activity.h>
#include <zmk/endpoints.h>
#include <zmk/studio/core.h>
#include <zmk/studio/custom.h>
#include <zmk/usb.h>

#include <onthe15/battery_settings.h>
#include <zmk_matrix_lighting/matrix_lighting.h>
#if IS_ENABLED(CONFIG_ZMK_POWER_SETTINGS)
#include <zmk_feature/power_settings.h>
#define onthe15_power_settings zmk_power_settings
#define onthe15_power_settings_get zmk_power_settings_get
#define onthe15_power_settings_has_unsaved_changes zmk_power_settings_has_unsaved_changes
#define onthe15_power_settings_set_memory zmk_power_settings_set_memory
#define onthe15_power_settings_save zmk_power_settings_save
#define onthe15_power_settings_discard zmk_power_settings_discard
#define onthe15_power_settings_reset zmk_power_settings_reset
#else
#include <onthe15/power_settings.h>
#endif
#include <onthe15/status_settings.h>
#include <onthe15/studio/build_info.h>
#include <onthe15/studio/studio.pb.h>

LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

BUILD_ASSERT(onthe15_studio_Response_size + 64U <= CONFIG_ZMK_STUDIO_RPC_TX_BUF_SIZE,
             "On the 15 Studio response and framing exceed the RPC TX buffer");
BUILD_ASSERT(sizeof(ONTHE15_STUDIO_FIRMWARE_VERSION) - 1U <= ONTHE15_STUDIO_VERSION_MAX_LENGTH,
             "On the 15 firmware version exceeds its protobuf field");
BUILD_ASSERT(sizeof(ONTHE15_STUDIO_GIT_SHA) - 1U <= ONTHE15_STUDIO_GIT_SHA_MAX_LENGTH,
             "On the 15 Git SHA exceeds its protobuf field");

static bool studio_rpc_handle_request(const zmk_custom_CallRequest *raw_request,
                                      pb_callback_t *encode_response);

static struct zmk_rpc_custom_subsystem_meta studio_subsystem_meta = {
    /* Local development UI. Replace with the pinned HTTPS production URL
     * before distributing a DYA firmware artifact. */
    ZMK_RPC_CUSTOM_SUBSYSTEM_UI_URLS("https://studio.tarohayashi.com/"),
    .security = ZMK_STUDIO_RPC_HANDLER_UNSECURED,
};

ZMK_RPC_CUSTOM_SUBSYSTEM(onthe15__studio, &studio_subsystem_meta, studio_rpc_handle_request);
ZMK_RPC_CUSTOM_SUBSYSTEM_RESPONSE_BUFFER(onthe15__studio, onthe15_studio_Response);

static void set_error_response(onthe15_studio_Response *response, const char *message) {
    onthe15_studio_ErrorResponse error = onthe15_studio_ErrorResponse_init_zero;

    snprintf(error.message, sizeof(error.message), "%s", message);
    response->which_response_type = onthe15_studio_Response_error_tag;
    response->response_type.error = error;
}

static void set_firmware_info_response(onthe15_studio_Response *response) {
    onthe15_studio_GetFirmwareInfoResponse info =
        onthe15_studio_GetFirmwareInfoResponse_init_zero;

    snprintf(info.version, sizeof(info.version), "%s", ONTHE15_STUDIO_FIRMWARE_VERSION);
    snprintf(info.git_sha, sizeof(info.git_sha), "%s", ONTHE15_STUDIO_GIT_SHA);
    info.schema_version = ONTHE15_STUDIO_SCHEMA_VERSION;

    response->which_response_type = onthe15_studio_Response_firmware_info_tag;
    response->response_type.firmware_info = info;
}

static void set_battery_settings_response(onthe15_studio_Response *response) {
    struct onthe15_battery_settings current;
    onthe15_battery_settings_get(&current);

    onthe15_studio_BatterySettingsResponse result =
        onthe15_studio_BatterySettingsResponse_init_zero;
    result.has_settings = true;
    result.settings.chemistry = current.battery_type == ONTHE15_BATTERY_ALKALINE
                                    ? onthe15_studio_BatteryChemistry_BATTERY_CHEMISTRY_ALKALINE
                                    : onthe15_studio_BatteryChemistry_BATTERY_CHEMISTRY_NIMH;
    result.settings.low_warning = current.low_warning_enabled;
    result.dirty = onthe15_battery_settings_has_unsaved_changes();

    response->which_response_type = onthe15_studio_Response_battery_settings_tag;
    response->response_type.battery_settings = result;
}

static void set_status_settings_response(onthe15_studio_Response *response) {
    struct onthe15_status_settings current;
    onthe15_status_settings_get(&current);

    onthe15_studio_StatusSettingsResponse result =
        onthe15_studio_StatusSettingsResponse_init_zero;
    result.has_settings = true;
    result.settings.connected_indicator = current.connected_indicator_enabled;
    result.settings.disconnected_indicator = current.disconnected_indicator_enabled;
    result.settings.layer_change_indicator = current.layer_change_indicator_enabled;
    result.settings.feedback_indicator = current.feedback_indicator_enabled;
    result.dirty = onthe15_status_settings_has_unsaved_changes();

    response->which_response_type = onthe15_studio_Response_status_settings_tag;
    response->response_type.status_settings = result;
}

static void set_lighting_effects_response(onthe15_studio_Response *response) {
    onthe15_studio_LightingEffectsResponse result =
        onthe15_studio_LightingEffectsResponse_init_zero;
    struct zmk_matrix_lighting_effect_info info;

    for (size_t i = 0; zmk_matrix_lighting_effect_info(i, &info); i++) {
        const uint32_t bit = 1U << info.effect;
        result.supported |= bit;
        if (info.uses_hue) {
            result.uses_hue |= bit;
        }
        if (info.uses_saturation) {
            result.uses_saturation |= bit;
        }
        if (info.uses_speed) {
            result.uses_speed |= bit;
        }
    }

    response->which_response_type = onthe15_studio_Response_lighting_effects_tag;
    response->response_type.lighting_effects = result;
}

static void set_lighting_settings_response(onthe15_studio_Response *response) {
    struct zmk_matrix_lighting_settings current;
    zmk_matrix_lighting_settings_get(&current);

    onthe15_studio_LightingSettingsResponse result =
        onthe15_studio_LightingSettingsResponse_init_zero;
    result.has_settings = true;
    result.settings.hue = current.hue;
    result.settings.saturation = current.saturation;
    result.settings.underglow_hue = current.underglow_hue;
    result.settings.underglow_saturation = current.underglow_saturation;
    result.settings.separate_color = current.separate_color;
    result.settings.backlight_brightness = current.backlight_brightness;
    result.settings.underglow_brightness = current.underglow_brightness;
    result.settings.backlight_enabled = current.backlight_enabled;
    result.settings.underglow_enabled = current.underglow_enabled;
    result.settings.backlight_layer_color = current.backlight_layer_color;
    result.settings.underglow_layer_color = current.underglow_layer_color;
    result.settings.auto_off = current.auto_off;
    result.settings.effect = (onthe15_studio_LightingEffect)current.effect;
    result.settings.effect_speed = current.effect_speed;
    result.dirty = zmk_matrix_lighting_settings_has_unsaved_changes();

    response->which_response_type = onthe15_studio_Response_lighting_settings_tag;
    response->response_type.lighting_settings = result;
}

static void set_power_settings_response(onthe15_studio_Response *response) {
    struct onthe15_power_settings current;
    onthe15_power_settings_get(&current);

    onthe15_studio_PowerSettingsResponse result =
        onthe15_studio_PowerSettingsResponse_init_zero;
    result.has_settings = true;
    result.settings.idle_timeout_ms = current.idle_timeout_ms;
    result.settings.deep_sleep_timeout_ms = current.deep_sleep_timeout_ms;
    result.dirty = onthe15_power_settings_has_unsaved_changes();

    response->which_response_type = onthe15_studio_Response_power_settings_tag;
    response->response_type.power_settings = result;
}

static void set_power_diagnostics_response(onthe15_studio_Response *response) {
    onthe15_studio_PowerDiagnostics result = onthe15_studio_PowerDiagnostics_init_zero;
    const uint32_t inactive_ms = zmk_activity_get_inactive_time_ms();
    const uint32_t sleep_timeout_ms = zmk_activity_get_sleep_timeout_ms();

    result.uptime_ms = k_uptime_get_32();
    result.inactive_ms = inactive_ms;
    result.deep_sleep_remaining_ms =
        sleep_timeout_ms == 0U || inactive_ms >= sleep_timeout_ms
            ? 0U
            : sleep_timeout_ms - inactive_ms;
    result.usb_powered = zmk_usb_is_powered();
    result.activity = (onthe15_studio_PowerActivity)zmk_activity_get_state();

    switch (zmk_endpoint_get_selected().transport) {
    case ZMK_TRANSPORT_USB:
        result.selected_transport =
            onthe15_studio_SelectedTransport_SELECTED_TRANSPORT_USB;
        break;
    case ZMK_TRANSPORT_BLE:
        result.selected_transport =
            onthe15_studio_SelectedTransport_SELECTED_TRANSPORT_BLE;
        break;
    default:
        result.selected_transport =
            onthe15_studio_SelectedTransport_SELECTED_TRANSPORT_NONE;
        break;
    }

    response->which_response_type = onthe15_studio_Response_power_diagnostics_tag;
    response->response_type.power_diagnostics = result;
}

static bool request_requires_unlock(pb_size_t request_type) {
    return request_type == onthe15_studio_Request_set_battery_settings_tag ||
           request_type == onthe15_studio_Request_save_battery_settings_tag ||
           request_type == onthe15_studio_Request_discard_battery_settings_tag ||
           request_type == onthe15_studio_Request_reset_battery_settings_tag ||
           request_type == onthe15_studio_Request_set_status_settings_tag ||
           request_type == onthe15_studio_Request_save_status_settings_tag ||
           request_type == onthe15_studio_Request_discard_status_settings_tag ||
           request_type == onthe15_studio_Request_reset_status_settings_tag ||
           request_type == onthe15_studio_Request_set_lighting_settings_tag ||
           request_type == onthe15_studio_Request_save_lighting_settings_tag ||
           request_type == onthe15_studio_Request_discard_lighting_settings_tag ||
           request_type == onthe15_studio_Request_reset_lighting_settings_tag ||
           request_type == onthe15_studio_Request_set_power_settings_tag ||
           request_type == onthe15_studio_Request_save_power_settings_tag ||
           request_type == onthe15_studio_Request_discard_power_settings_tag ||
           request_type == onthe15_studio_Request_reset_power_settings_tag;
}

static bool studio_rpc_handle_request(const zmk_custom_CallRequest *raw_request,
                                      pb_callback_t *encode_response) {
    onthe15_studio_Response *response =
        ZMK_RPC_CUSTOM_SUBSYSTEM_RESPONSE_BUFFER_ALLOCATE(onthe15__studio, encode_response);
    onthe15_studio_Request request = onthe15_studio_Request_init_zero;
    pb_istream_t stream =
        pb_istream_from_buffer(raw_request->payload.bytes, raw_request->payload.size);

    if (!pb_decode(&stream, onthe15_studio_Request_fields, &request)) {
        LOG_WRN("Failed to decode On the 15 Studio request: %s", PB_GET_ERROR(&stream));
        set_error_response(response, "Failed to decode request");
        return true;
    }

    if (request_requires_unlock(request.which_request_type) &&
        zmk_studio_core_get_lock_state() != ZMK_STUDIO_CORE_LOCK_STATE_UNLOCKED) {
        set_error_response(response, "Studio Unlock required");
        return true;
    }

    switch (request.which_request_type) {
    case onthe15_studio_Request_get_firmware_info_tag:
        set_firmware_info_response(response);
        break;
    case onthe15_studio_Request_get_battery_settings_tag:
        set_battery_settings_response(response);
        break;
    case onthe15_studio_Request_set_battery_settings_tag: {
        const onthe15_studio_SetBatterySettingsRequest *set_request =
            &request.request_type.set_battery_settings;
        if (!set_request->has_settings ||
            set_request->settings.chemistry >
                onthe15_studio_BatteryChemistry_BATTERY_CHEMISTRY_ALKALINE) {
            set_error_response(response, "Invalid battery settings");
            break;
        }
        const struct onthe15_battery_settings settings = {
            .low_warning_enabled = set_request->settings.low_warning,
            .battery_type = set_request->settings.chemistry ==
                                    onthe15_studio_BatteryChemistry_BATTERY_CHEMISTRY_ALKALINE
                                ? ONTHE15_BATTERY_ALKALINE
                                : ONTHE15_BATTERY_NIMH,
        };
        if (onthe15_battery_settings_set_memory(&settings) < 0) {
            set_error_response(response, "Failed to apply battery settings");
            break;
        }
        set_battery_settings_response(response);
        break;
    }
    case onthe15_studio_Request_save_battery_settings_tag:
        if (onthe15_battery_settings_save() < 0) {
            set_error_response(response, "Failed to save battery settings");
            break;
        }
        set_battery_settings_response(response);
        break;
    case onthe15_studio_Request_discard_battery_settings_tag:
        onthe15_battery_settings_discard();
        set_battery_settings_response(response);
        break;
    case onthe15_studio_Request_reset_battery_settings_tag:
        onthe15_battery_settings_reset();
        set_battery_settings_response(response);
        break;
    case onthe15_studio_Request_get_status_settings_tag:
        set_status_settings_response(response);
        break;
    case onthe15_studio_Request_set_status_settings_tag: {
        const onthe15_studio_SetStatusSettingsRequest *set_request =
            &request.request_type.set_status_settings;
        if (!set_request->has_settings) {
            set_error_response(response, "Invalid status settings");
            break;
        }
        /* SetStatusSettings replaces the whole struct, and a protobuf bool that
         * the client left out decodes as false - so the Web UI must always send
         * every switch, not just the one the user toggled. */
        const struct onthe15_status_settings settings = {
            .connected_indicator_enabled = set_request->settings.connected_indicator,
            .disconnected_indicator_enabled = set_request->settings.disconnected_indicator,
            .layer_change_indicator_enabled = set_request->settings.layer_change_indicator,
            .feedback_indicator_enabled = set_request->settings.feedback_indicator,
        };
        if (onthe15_status_settings_set_memory(&settings) < 0) {
            set_error_response(response, "Failed to apply status settings");
            break;
        }
        set_status_settings_response(response);
        break;
    }
    case onthe15_studio_Request_save_status_settings_tag:
        if (onthe15_status_settings_save() < 0) {
            set_error_response(response, "Failed to save status settings");
            break;
        }
        set_status_settings_response(response);
        break;
    case onthe15_studio_Request_discard_status_settings_tag:
        onthe15_status_settings_discard();
        set_status_settings_response(response);
        break;
    case onthe15_studio_Request_reset_status_settings_tag:
        onthe15_status_settings_reset();
        set_status_settings_response(response);
        break;
    case onthe15_studio_Request_get_lighting_settings_tag:
        set_lighting_settings_response(response);
        break;
    case onthe15_studio_Request_get_lighting_effects_tag:
        set_lighting_effects_response(response);
        break;
    case onthe15_studio_Request_set_lighting_settings_tag: {
        const onthe15_studio_SetLightingSettingsRequest *set_request =
            &request.request_type.set_lighting_settings;
        if (!set_request->has_settings || set_request->settings.hue > 359 ||
            set_request->settings.saturation > 100 ||
            set_request->settings.underglow_hue > 359 ||
            set_request->settings.underglow_saturation > 100 ||
            set_request->settings.backlight_brightness > 100 ||
            set_request->settings.underglow_brightness > 100 ||
            set_request->settings.effect_speed < 1 ||
            set_request->settings.effect_speed > 10) {
            set_error_response(response, "Invalid lighting settings");
            break;
        }
        const struct zmk_matrix_lighting_settings settings = {
            .hue = set_request->settings.hue,
            .saturation = set_request->settings.saturation,
            .underglow_hue = set_request->settings.separate_color
                                 ? set_request->settings.underglow_hue
                                 : set_request->settings.hue,
            .underglow_saturation = set_request->settings.separate_color
                                        ? set_request->settings.underglow_saturation
                                        : set_request->settings.saturation,
            .separate_color = set_request->settings.separate_color,
            .backlight_brightness = set_request->settings.backlight_brightness,
            .underglow_brightness = set_request->settings.underglow_brightness,
            .backlight_enabled = set_request->settings.backlight_enabled,
            .underglow_enabled = set_request->settings.underglow_enabled,
            .backlight_layer_color = set_request->settings.backlight_layer_color,
            .underglow_layer_color = set_request->settings.underglow_layer_color,
            .auto_off = set_request->settings.auto_off,
            .effect = (enum zmk_matrix_lighting_effect)set_request->settings.effect,
            .effect_speed = set_request->settings.effect_speed,
        };
        if (zmk_matrix_lighting_settings_set_memory(&settings) < 0) {
            set_error_response(response, "Failed to apply lighting settings");
            break;
        }
        set_lighting_settings_response(response);
        break;
    }
    case onthe15_studio_Request_save_lighting_settings_tag:
        if (zmk_matrix_lighting_settings_save() < 0) {
            set_error_response(response, "Failed to save lighting settings");
            break;
        }
        set_lighting_settings_response(response);
        break;
    case onthe15_studio_Request_discard_lighting_settings_tag:
        zmk_matrix_lighting_settings_discard();
        set_lighting_settings_response(response);
        break;
    case onthe15_studio_Request_reset_lighting_settings_tag:
        zmk_matrix_lighting_settings_reset();
        set_lighting_settings_response(response);
        break;
    case onthe15_studio_Request_get_power_settings_tag:
        set_power_settings_response(response);
        break;
    case onthe15_studio_Request_set_power_settings_tag: {
        const onthe15_studio_SetPowerSettingsRequest *set_request =
            &request.request_type.set_power_settings;
        if (!set_request->has_settings) {
            set_error_response(response, "Invalid power settings");
            break;
        }
        const struct onthe15_power_settings settings = {
            .idle_timeout_ms = set_request->settings.idle_timeout_ms,
            .deep_sleep_timeout_ms = set_request->settings.deep_sleep_timeout_ms,
        };
        if (onthe15_power_settings_set_memory(&settings) < 0) {
            set_error_response(response, "Invalid power settings");
            break;
        }
        set_power_settings_response(response);
        break;
    }
    case onthe15_studio_Request_save_power_settings_tag:
        if (onthe15_power_settings_save() < 0) {
            set_error_response(response, "Failed to save power settings");
            break;
        }
        set_power_settings_response(response);
        break;
    case onthe15_studio_Request_discard_power_settings_tag:
        onthe15_power_settings_discard();
        set_power_settings_response(response);
        break;
    case onthe15_studio_Request_reset_power_settings_tag:
        onthe15_power_settings_reset();
        set_power_settings_response(response);
        break;
    case onthe15_studio_Request_get_power_diagnostics_tag:
        set_power_diagnostics_response(response);
        break;
    default:
        LOG_WRN("Unsupported On the 15 Studio request type: %u",
                (unsigned int)request.which_request_type);
        set_error_response(response, "Unsupported request type");
        break;
    }

    return true;
}
