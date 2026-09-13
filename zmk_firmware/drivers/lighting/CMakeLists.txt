zephyr_library()
zephyr_library_include_directories(${CMAKE_CURRENT_LIST_DIR}/../../include)
zephyr_library_sources_ifdef(CONFIG_ONTHE15_LIGHTING_STARTUP onthe15_lighting_startup.c)
