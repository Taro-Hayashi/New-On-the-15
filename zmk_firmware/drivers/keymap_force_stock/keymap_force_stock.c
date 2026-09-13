/*
 * Copyright (c) 2026 The On the 15 v4 Contributors
 *
 * SPDX-License-Identifier: MIT
 */

#include <zephyr/init.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include <zmk/keymap.h>

LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

/*
 * zmk_keymap_reset_settings() has to run after settings_load(), which main()
 * calls once every SYS_INIT level has already finished - so there is no init
 * hook late enough to use. Reset from a short delayed work item instead; this
 * is the same call ZMK Studio's "restore stock keymap" makes at runtime, so
 * running it after boot is a supported use rather than a startup-order trick.
 * The keyboard therefore honours a stored keymap for the first fraction of a
 * second and then falls back to the compiled one, which is harmless for a
 * hardware-test image.
 */
#define KEYMAP_FORCE_STOCK_DELAY K_MSEC(1000)

static void keymap_force_stock_work_handler(struct k_work *work) {
    ARG_UNUSED(work);

    int ret = zmk_keymap_reset_settings();
    if (ret < 0) {
        LOG_ERR("Failed to discard the stored keymap (%d)", ret);
        return;
    }

    LOG_INF("Hardware-test image: stored keymap discarded, running the compiled one");
}

static K_WORK_DELAYABLE_DEFINE(keymap_force_stock_work, keymap_force_stock_work_handler);

static int keymap_force_stock_init(void) {
    k_work_schedule(&keymap_force_stock_work, KEYMAP_FORCE_STOCK_DELAY);
    return 0;
}

SYS_INIT(keymap_force_stock_init, APPLICATION, CONFIG_APPLICATION_INIT_PRIORITY);
