zephyr_library()
zephyr_library_include_directories(
    ${APPLICATION_SOURCE_DIR}/include
    ${CMAKE_CURRENT_LIST_DIR}/../../include
)
zephyr_library_sources_ifdef(CONFIG_ONTHE15_POWER_SETTINGS power_settings.c)

