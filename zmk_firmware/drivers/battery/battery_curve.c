/* SPDX-License-Identifier: MIT */
#include <stddef.h>
#include "battery_curve.h"

struct battery_curve_point { uint16_t millivolts; uint8_t percent; };

/* Panasonic BK-4MCC, 25 C, typical 160 mA discharge curve. */
static const struct battery_curve_point nimh_curve[] = {
    {1000, 0}, {1130, 5}, {1200, 10}, {1242, 20}, {1258, 30}, {1268, 40},
    {1275, 50}, {1282, 60}, {1290, 70}, {1305, 80}, {1340, 90}, {1450, 100},
};

/* Energizer EN92 AAA, 21 C, 24-ohm intermittent low-drain curve, digitized by
 * elapsed service fraction. The upper endpoint agrees with the repository's
 * lp7 loaded measurement (1.522 V before the display left 100%).
 * https://data.energizer.com/pdfs/en92.pdf */
static const struct battery_curve_point alkaline_curve[] = {
    {800, 0}, {900, 5}, {1000, 12}, {1100, 25}, {1200, 45}, {1250, 58},
    {1300, 70}, {1350, 80}, {1400, 88}, {1450, 94}, {1500, 98}, {1520, 100},
};

static uint8_t interpolate(const struct battery_curve_point *curve, size_t count,
                           uint16_t cell_mv) {
    if (cell_mv <= curve[0].millivolts) return curve[0].percent;
    for (size_t i = 1; i < count; i++) {
        const struct battery_curve_point *lower = &curve[i - 1];
        const struct battery_curve_point *upper = &curve[i];
        if (cell_mv <= upper->millivolts) {
            return lower->percent +
                   (cell_mv - lower->millivolts) * (upper->percent - lower->percent) /
                       (upper->millivolts - lower->millivolts);
        }
    }
    return curve[count - 1].percent;
}

uint8_t onthe15_battery_state_of_charge(enum onthe15_battery_type type, uint16_t cell_mv) {
    if (type == ONTHE15_BATTERY_ALKALINE) {
        return interpolate(alkaline_curve, sizeof(alkaline_curve) / sizeof(alkaline_curve[0]), cell_mv);
    }
    return interpolate(nimh_curve, sizeof(nimh_curve) / sizeof(nimh_curve[0]), cell_mv);
}
