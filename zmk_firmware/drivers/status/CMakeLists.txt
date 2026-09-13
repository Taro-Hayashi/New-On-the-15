zephyr_library()
zephyr_library_include_directories(${APPLICATION_SOURCE_DIR}/include)
zephyr_library_include_directories(${CMAKE_CURRENT_LIST_DIR}/../../include)
zephyr_library_sources_ifdef(CONFIG_ONTHE15_STATUS_INDICATOR
    status_indicator.c
    behavior_indicator_toggle.c
    behavior_status_settings.c
)
zephyr_library_sources_ifdef(CONFIG_ONTHE15_BT_FEEDBACK_BEHAVIOR behavior_bt_feedback.c)
