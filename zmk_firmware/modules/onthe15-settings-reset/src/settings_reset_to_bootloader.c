/*
 * Copyright (c) 2026 The On the 15 v4 Contributors
 *
 * SPDX-License-Identifier: MIT
 */

#include <zephyr/init.h>
#include <zephyr/sys/reboot.h>

#if IS_ENABLED(CONFIG_RETENTION_BOOT_MODE)
#include <zephyr/retention/bootmode.h>
#else
#define ONTHE15_UF2_REBOOT_TYPE 0x57
#endif

/*
 * ZMK erases settings synchronously at POST_KERNEL priority 60. Run after
 * that so the controller returns to the UF2 bootloader and is ready for the
 * normal firmware to be copied without another reset.
 *
 * Not immediately after, though: bootmode_set() writes through the retention
 * area, whose device initializes at CONFIG_RETENTION_INIT_PRIORITY (86 on this
 * board). Running at 61 left the boot mode unwritten and the board came back up
 * into the same image instead of the bootloader.
 */
static int settings_reset_to_bootloader(void) {
#if IS_ENABLED(CONFIG_RETENTION_BOOT_MODE)
    int err = bootmode_set(BOOT_MODE_TYPE_BOOTLOADER);
    if (err < 0) {
        return err;
    }

    sys_reboot(SYS_REBOOT_WARM);
#else
    sys_reboot(ONTHE15_UF2_REBOOT_TYPE);
#endif
    return 0;
}

SYS_INIT(settings_reset_to_bootloader, POST_KERNEL, 90);
