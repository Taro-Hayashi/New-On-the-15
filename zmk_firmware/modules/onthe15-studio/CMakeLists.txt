if(CONFIG_ZMK_ONTHE15_STUDIO_RPC)
    find_package(Git REQUIRED)

    execute_process(
        COMMAND ${GIT_EXECUTABLE} -C ${CMAKE_CURRENT_SOURCE_DIR} describe --always --dirty
        OUTPUT_VARIABLE ONTHE15_STUDIO_FIRMWARE_VERSION
        OUTPUT_STRIP_TRAILING_WHITESPACE
        COMMAND_ERROR_IS_FATAL ANY
    )
    execute_process(
        COMMAND ${GIT_EXECUTABLE} -C ${CMAKE_CURRENT_SOURCE_DIR} rev-parse HEAD
        OUTPUT_VARIABLE ONTHE15_STUDIO_GIT_SHA
        OUTPUT_STRIP_TRAILING_WHITESPACE
        COMMAND_ERROR_IS_FATAL ANY
    )

    string(LENGTH "${ONTHE15_STUDIO_FIRMWARE_VERSION}" ONTHE15_STUDIO_VERSION_LENGTH)
    string(LENGTH "${ONTHE15_STUDIO_GIT_SHA}" ONTHE15_STUDIO_GIT_SHA_LENGTH)
    if(ONTHE15_STUDIO_VERSION_LENGTH GREATER 32)
        message(FATAL_ERROR "On the 15 firmware version exceeds the RPC limit of 32 bytes")
    endif()
    if(ONTHE15_STUDIO_GIT_SHA_LENGTH GREATER 40)
        message(FATAL_ERROR "On the 15 Git SHA exceeds the RPC limit of 40 bytes")
    endif()

    target_compile_definitions(app PRIVATE
        ONTHE15_STUDIO_FIRMWARE_VERSION="${ONTHE15_STUDIO_FIRMWARE_VERSION}"
        ONTHE15_STUDIO_GIT_SHA="${ONTHE15_STUDIO_GIT_SHA}"
    )
    target_include_directories(app PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${CMAKE_CURRENT_SOURCE_DIR}/../../include
    )
    target_sources(app PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src/studio_handler.c)

    list(APPEND CMAKE_MODULE_PATH ${ZEPHYR_BASE}/modules/nanopb)
    include(nanopb)
    set(NANOPB_GENERATE_CPP_APPEND_PATH TRUE)
    set(NANOPB_GENERATE_CPP_STANDALONE OFF)

    zephyr_library()
    nanopb_generate_cpp(proto_srcs proto_hdrs
        RELPATH ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/proto/onthe15/studio/studio.proto
    )
    target_include_directories(${ZEPHYR_CURRENT_LIBRARY} PUBLIC ${CMAKE_CURRENT_BINARY_DIR})
    target_sources(${ZEPHYR_CURRENT_LIBRARY} PRIVATE ${proto_srcs} ${proto_hdrs})
    target_include_directories(app PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/proto)
    add_dependencies(app ${ZEPHYR_CURRENT_LIBRARY})
endif()
