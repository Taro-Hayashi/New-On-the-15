/* SPDX-License-Identifier: MIT */
#pragma once
#include <stdint.h>
#include <onthe15/battery_settings.h>

uint8_t onthe15_battery_state_of_charge(enum onthe15_battery_type type, uint16_t cell_mv);
