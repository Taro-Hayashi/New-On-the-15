/* SPDX-License-Identifier: MIT */

/*
 * On the 15 power-up intro.
 *
 * The six underglow LEDs sit three to the left edge and three to the right, so
 * the ripple works in symmetric pairs: it opens at the innermost pair, travels
 * out to the corners, returns, and hands over to the backlight, which fades up
 * underneath. The pairing and the LED count are specific to this board, which
 * is why the intro lives here rather than in the lighting module - the module
 * only lends the frame out and cross-fades into the saved effect afterwards.
 */

#include <string.h>
#include <zephyr/drivers/led_strip.h>
#include <zephyr/kernel.h>

#include <zmk_matrix_lighting/matrix_lighting.h>

#define UNDERGLOW_LEDS 6U
#define STEPS 5U
#define PHASES 6U
#define RIPPLE_FRAME_INTERVAL K_MSEC(30)
#define FADE_FRAME_INTERVAL K_MSEC(60)

/* Left edge runs top to bottom, right edge bottom to top, so these are the
 * pairs at equal height: innermost first. */
static const uint8_t ripple_center[] = {2, 3};
static const uint8_t ripple_mid[] = {1, 4};
static const uint8_t ripple_outer[] = {0, 5};

/* Large enough for every On the 15 strip: 66 on the x15, 38 on the others. */
static struct led_rgb frame[72];
static size_t led_count;
static uint8_t animation_frame;

static void animation_work_handler(struct k_work *work);
K_WORK_DELAYABLE_DEFINE(animation_work, animation_work_handler);

static struct led_rgb hsb_to_rgb(uint16_t hue, uint8_t saturation,
                                 uint8_t brightness) {
    const uint8_t region = hue / 60;
    const uint16_t remainder = (hue % 60) * 255 / 60;
    const uint16_t value = brightness * 255 / 100;
    const uint16_t sat = saturation * 255 / 100;
    const uint8_t p = value * (255 - sat) / 255;
    const uint8_t q = value * (255 - (sat * remainder / 255)) / 255;
    const uint8_t t = value * (255 - (sat * (255 - remainder) / 255)) / 255;

    switch (region % 6) {
    case 0:
        return (struct led_rgb){.r = value, .g = t, .b = p};
    case 1:
        return (struct led_rgb){.r = q, .g = value, .b = p};
    case 2:
        return (struct led_rgb){.r = p, .g = value, .b = t};
    case 3:
        return (struct led_rgb){.r = p, .g = q, .b = value};
    case 4:
        return (struct led_rgb){.r = t, .g = p, .b = value};
    default:
        return (struct led_rgb){.r = value, .g = p, .b = q};
    }
}

static void set_pair(const struct zmk_matrix_lighting_settings *settings,
                     const uint8_t pair[2], uint8_t level) {
    const uint16_t hue =
        settings->separate_color ? settings->underglow_hue : settings->hue;
    const uint8_t saturation = settings->separate_color
                                   ? settings->underglow_saturation
                                   : settings->saturation;
    const struct led_rgb color =
        hsb_to_rgb(hue, saturation, settings->underglow_brightness * level / STEPS);

    for (int i = 0; i < 2; i++) {
        frame[pair[i]] = color;
    }
}

static void animation_work_handler(struct k_work *work) {
    ARG_UNUSED(work);

    if (animation_frame >= STEPS * PHASES) {
        zmk_matrix_lighting_startup_done();
        return;
    }

    struct zmk_matrix_lighting_settings settings;
    zmk_matrix_lighting_settings_get(&settings);

    const uint8_t phase = animation_frame / STEPS;
    const uint8_t step = animation_frame % STEPS + 1;
    const uint8_t fade_out = STEPS - step;
    const struct led_rgb backlight_color =
        hsb_to_rgb(settings.hue, settings.saturation,
                   settings.backlight_enabled
                       ? settings.backlight_brightness * step / STEPS
                       : 0);
    const uint16_t underglow_hue =
        settings.separate_color ? settings.underglow_hue : settings.hue;
    const uint8_t underglow_saturation = settings.separate_color
                                             ? settings.underglow_saturation
                                             : settings.saturation;
    const struct led_rgb underglow_color =
        hsb_to_rgb(underglow_hue, underglow_saturation,
                   settings.underglow_enabled
                       ? settings.underglow_brightness * step / STEPS
                       : 0);

    memset(frame, 0, sizeof(frame));

    switch (phase) {
    case 0:
        set_pair(&settings, ripple_center, step);
        break;
    case 1:
        set_pair(&settings, ripple_center, fade_out);
        set_pair(&settings, ripple_mid, step);
        break;
    case 2:
        set_pair(&settings, ripple_mid, fade_out);
        set_pair(&settings, ripple_outer, step);
        break;
    case 3:
        set_pair(&settings, ripple_outer, fade_out);
        set_pair(&settings, ripple_mid, step);
        break;
    case 4:
        for (size_t i = UNDERGLOW_LEDS; i < led_count; i++) {
            frame[i] = backlight_color;
        }
        set_pair(&settings, ripple_mid, fade_out);
        set_pair(&settings, ripple_center, step);
        break;
    default:
        if (settings.underglow_enabled) {
            for (size_t i = 0; i < UNDERGLOW_LEDS; i++) {
                frame[i] = underglow_color;
            }
            set_pair(&settings, ripple_center, STEPS);
        } else {
            set_pair(&settings, ripple_center, fade_out);
        }
        for (size_t i = UNDERGLOW_LEDS; i < led_count; i++) {
            frame[i] = settings.backlight_enabled
                           ? hsb_to_rgb(settings.hue, settings.saturation,
                                        settings.backlight_brightness)
                           : (struct led_rgb){0};
        }
        break;
    }

    if (zmk_matrix_lighting_startup_set_pixels(frame, led_count) < 0) {
        zmk_matrix_lighting_startup_done();
        return;
    }

    animation_frame++;
    k_work_reschedule(&animation_work,
                      phase >= 4 ? FADE_FRAME_INTERVAL : RIPPLE_FRAME_INTERVAL);
}

bool zmk_matrix_lighting_startup_begin(void) {
    led_count = zmk_matrix_lighting_led_count();

    /* The ripple needs the three pairs, and the frame has to hold the strip. */
    if (zmk_matrix_lighting_underglow_count() < UNDERGLOW_LEDS ||
        led_count > ARRAY_SIZE(frame)) {
        return false;
    }

    animation_frame = 0;
    k_work_reschedule(&animation_work, K_NO_WAIT);
    return true;
}
