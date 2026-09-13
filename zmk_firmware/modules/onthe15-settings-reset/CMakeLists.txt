if(CONFIG_ONTHE15_SETTINGS_RESET_TO_BOOTLOADER)
    zephyr_library()
    zephyr_library_sources(src/settings_reset_to_bootloader.c)
endif()
