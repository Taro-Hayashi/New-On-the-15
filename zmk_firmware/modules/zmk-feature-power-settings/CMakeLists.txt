if(CONFIG_ZMK_POWER_SETTINGS)
    zephyr_include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)
    zephyr_library()
    zephyr_library_include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)
    zephyr_library_sources(
        src/power_settings.c
        src/power_settings_validation.c
        src/behavior_power_settings.c
    )
    zephyr_library_sources_ifdef(CONFIG_ZMK_POWER_SETTINGS_SYNC_API
        src/power_settings_sync.c
    )
    zephyr_library_sources_ifdef(CONFIG_ZMK_POWER_SETTINGS_SPLIT_SYNC
        src/power_settings_split.c
    )

    if(CONFIG_ZMK_POWER_SETTINGS_STUDIO_RPC)
        target_sources(app PRIVATE src/studio_settings_handler.c)

        list(APPEND CMAKE_MODULE_PATH ${ZEPHYR_BASE}/modules/nanopb)
        include(nanopb)
        set(NANOPB_GENERATE_CPP_APPEND_PATH TRUE)
        set(NANOPB_GENERATE_CPP_STANDALONE OFF)

        nanopb_generate_cpp(power_settings_proto_srcs power_settings_proto_hdrs
            RELPATH ${CMAKE_CURRENT_SOURCE_DIR}
            ${CMAKE_CURRENT_SOURCE_DIR}/proto/zmk/settings/core.proto
        )
        target_include_directories(${ZEPHYR_CURRENT_LIBRARY} PUBLIC ${CMAKE_CURRENT_BINARY_DIR})
        target_sources(${ZEPHYR_CURRENT_LIBRARY} PRIVATE
            ${power_settings_proto_srcs}
            ${power_settings_proto_hdrs}
        )
        target_include_directories(app PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/proto)
        add_dependencies(app ${ZEPHYR_CURRENT_LIBRARY})
    endif()
endif()
