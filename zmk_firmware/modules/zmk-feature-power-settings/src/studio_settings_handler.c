/* SPDX-License-Identifier: MIT */

#include <errno.h>
#include <stdio.h>
#include <string.h>

#include <pb_decode.h>
#include <pb_encode.h>
#include <zephyr/logging/log.h>
#include <zephyr/sys/iterable_sections.h>
#include <zephyr/sys/util.h>

#include <zmk/settings/core.pb.h>
#include <zmk/studio/custom.h>
#include <zmk_feature/power_settings.h>

LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

BUILD_ASSERT(zmk_settings_Response_size + 64U <= CONFIG_ZMK_STUDIO_RPC_TX_BUF_SIZE,
             "Settings response and framing exceed the RPC TX buffer");

static bool settings_rpc_handle_request(const zmk_custom_CallRequest *raw_request,
                                        pb_callback_t *encode_response);

static struct zmk_rpc_custom_subsystem_meta settings_rpc_meta = {
    ZMK_RPC_CUSTOM_SUBSYSTEM_UI_URLS(),
    .security = ZMK_STUDIO_RPC_HANDLER_SECURED,
};

ZMK_RPC_CUSTOM_SUBSYSTEM(zmk__settings, &settings_rpc_meta, settings_rpc_handle_request);
ZMK_RPC_CUSTOM_SUBSYSTEM_RESPONSE_BUFFER(zmk__settings, zmk_settings_Response);

static void set_error(zmk_settings_Response *response, const char *message) {
    response->which_response_type = zmk_settings_Response_error_tag;
    snprintf(response->response_type.error.message,
             sizeof(response->response_type.error.message), "%s", message);
}

static void fill_activity_settings(zmk_settings_ActivitySettings *result) {
    struct zmk_power_settings settings;
    zmk_power_settings_get(&settings);
    result->idle_ms = settings.idle_timeout_ms;
    result->sleep_ms = settings.deep_sleep_timeout_ms;
    result->source = ZMK_POWER_SETTINGS_CENTRAL_SOURCE_ID;
}

static int subsystem_index(void) {
    size_t count;
    STRUCT_SECTION_COUNT(zmk_rpc_custom_subsystem, &count);
    for (size_t index = 0; index < count; index++) {
        struct zmk_rpc_custom_subsystem *subsystem;
        STRUCT_SECTION_GET(zmk_rpc_custom_subsystem, index, &subsystem);
        if (strcmp(subsystem->identifier, "zmk__settings") == 0) {
            return (int)index;
        }
    }
    return -ENOENT;
}

static bool encode_notification(pb_ostream_t *stream, const pb_field_t *field,
                                void *const *arg) {
    const zmk_settings_Notification *notification = *arg;
    size_t size;
    return pb_encode_tag_for_field(stream, field) &&
           pb_get_encoded_size(&size, zmk_settings_Notification_fields, notification) &&
           pb_encode_varint(stream, size) &&
           pb_encode(stream, zmk_settings_Notification_fields, notification);
}

static int send_notification(void) {
    int index = subsystem_index();
    if (index < 0) {
        return index;
    }

    zmk_settings_Notification notification = zmk_settings_Notification_init_zero;
    notification.which_notification_type = zmk_settings_Notification_activity_settings_tag;
    notification.notification_type.activity_settings.has_settings = true;
    fill_activity_settings(&notification.notification_type.activity_settings.settings);

    struct zmk_studio_custom_notification event = {
        .subsystem_index = (uint8_t)index,
        .encode_payload = {.funcs = {.encode = encode_notification}, .arg = &notification},
    };
    raise_zmk_studio_custom_notification(event);
    return 0;
}

static int set_and_save(const zmk_settings_ActivitySettings *requested) {
    const struct zmk_power_settings settings = {
        .idle_timeout_ms = requested->idle_ms,
        .deep_sleep_timeout_ms = requested->sleep_ms,
    };
    if (!zmk_power_settings_is_valid(&settings)) {
        return -EINVAL;
    }

    int rc = zmk_power_settings_set_memory(&settings);
    if (rc < 0) {
        return rc;
    }
    rc = zmk_power_settings_save();
    if (rc < 0) {
        (void)zmk_power_settings_discard();
        return rc;
    }
    return send_notification();
}

static bool settings_rpc_handle_request(const zmk_custom_CallRequest *raw_request,
                                        pb_callback_t *encode_response) {
    zmk_settings_Response *response =
        ZMK_RPC_CUSTOM_SUBSYSTEM_RESPONSE_BUFFER_ALLOCATE(zmk__settings, encode_response);
    zmk_settings_Request request = zmk_settings_Request_init_zero;
    pb_istream_t stream =
        pb_istream_from_buffer(raw_request->payload.bytes, raw_request->payload.size);
    if (!pb_decode(&stream, zmk_settings_Request_fields, &request)) {
        set_error(response, "Failed to decode request");
        return true;
    }

    switch (request.which_request_type) {
    case zmk_settings_Request_get_activity_settings_tag:
        response->which_response_type = zmk_settings_Response_get_activity_settings_tag;
        response->response_type.get_activity_settings.has_settings = true;
        fill_activity_settings(&response->response_type.get_activity_settings.settings);
        break;
    case zmk_settings_Request_set_activity_settings_tag:
        if (!request.request_type.set_activity_settings.has_settings) {
            set_error(response, "Activity settings are required");
            break;
        }
        if (set_and_save(&request.request_type.set_activity_settings.settings) < 0) {
            set_error(response, "Invalid or unsaved activity settings");
            break;
        }
        response->which_response_type = zmk_settings_Response_set_activity_settings_tag;
        response->response_type.set_activity_settings.success = true;
        break;
    case zmk_settings_Request_get_all_activity_settings_tag:
        if (send_notification() < 0) {
            set_error(response, "Failed to report activity settings");
            break;
        }
        response->which_response_type = zmk_settings_Response_get_all_activity_settings_tag;
        response->response_type.get_all_activity_settings.request_sent = true;
        break;
    default:
        set_error(response, "Unsupported request");
        break;
    }
    return true;
}
