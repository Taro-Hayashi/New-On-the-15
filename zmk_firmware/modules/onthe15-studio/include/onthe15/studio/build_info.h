#pragma once

#define ONTHE15_STUDIO_SCHEMA_VERSION 5U
#define ONTHE15_STUDIO_VERSION_MAX_LENGTH 32U
#define ONTHE15_STUDIO_GIT_SHA_MAX_LENGTH 40U

#ifndef ONTHE15_STUDIO_FIRMWARE_VERSION
#error "ONTHE15_STUDIO_FIRMWARE_VERSION must be supplied by the module build"
#endif

#ifndef ONTHE15_STUDIO_GIT_SHA
#error "ONTHE15_STUDIO_GIT_SHA must be supplied by the module build"
#endif
