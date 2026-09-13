//! SK6812 backlight control shared by the split binaries.
//!
//! This is the same VBUS-gated PWM0 + EasyDMA driver as in `main.rs` (see the
//! comments there for the timing rationale); extracted as a module so the
//! split-central and split-peripheral binaries can share it.

use core::sync::atomic::{AtomicBool, AtomicI8, AtomicU8, AtomicU16, Ordering};

use core::future::pending;
use defmt::{info, unwrap};
use embassy_nrf::Peri;
use embassy_nrf::gpio::{Input, Level};
use embassy_nrf::peripherals::{P1_15, PWM0};
use embassy_nrf::pwm::{
    Config as PwmConfig, Prescaler, SequenceConfig, SequenceLoad, SequencePwm, SingleSequenceMode,
    SingleSequencer,
};
use embassy_sync::blocking_mutex::raw::CriticalSectionRawMutex;
use embassy_sync::signal::Signal;
use embassy_time::{Duration, Timer};

use rmk::embassy_futures::select::{Either, Either3, select, select3};

/// Total SK6812 chain length, defined per binary at the crate root
/// (`BACKLIGHT_LED_COUNT`): 38 for the x7/x8 superset, 66 for x15.
pub const SK6812_COUNT: usize = crate::BACKLIGHT_LED_COUNT;
/// First LEDs in the chain are underglow (LED1-6); they are used only for the
/// power-on animation and stay off afterwards.
pub const UNDERGLOW_COUNT: usize = 6;
/// PWM ticks per bit at 16 MHz (Prescaler::Div1): 20 ticks = 1.25 us.
const PWM_TOP: u16 = 20;
/// 0-bit: high for 6 ticks = 0.375 us (SK6812 spec: 0.3 us +/- 0.15).
const BIT0: u16 = 0x8000 | 6;
/// 1-bit: high for 10 ticks = 0.625 us (SK6812 spec: 0.6 us +/- 0.15).
const BIT1: u16 = 0x8000 | 10;
/// Trailing all-low periods appended to each frame: 40 x 1.25 us = 50 us,
/// which satisfies the SK6812 latch/reset time.
const RESET_WORDS: usize = 40;
const FRAME_WORDS: usize = SK6812_COUNT * 24 + RESET_WORDS;

pub const BACKLIGHT_TOGGLE_USER_ID: u8 = 12;
pub const UNDERGLOW_TOGGLE_USER_ID: u8 = 13;
pub const HUE_UP_USER_ID: u8 = 14;
pub const HUE_DOWN_USER_ID: u8 = 15;
pub const SATURATION_UP_USER_ID: u8 = 16;
pub const SATURATION_DOWN_USER_ID: u8 = 17;
pub const BACKLIGHT_BRIGHTNESS_UP_USER_ID: u8 = 18;
pub const BACKLIGHT_BRIGHTNESS_DOWN_USER_ID: u8 = 19;
pub const UNDERGLOW_BRIGHTNESS_UP_USER_ID: u8 = 20;
pub const UNDERGLOW_BRIGHTNESS_DOWN_USER_ID: u8 = 21;
pub const BACKLIGHT_LAYER_COLOR_TOGGLE_USER_ID: u8 = 22;
pub const UNDERGLOW_LAYER_COLOR_TOGGLE_USER_ID: u8 = 23;
pub const AUTO_OFF_TOGGLE_USER_ID: u8 = 24;
pub const BRIGHTNESS_MODEL_VERSION_USER_ID: u8 = 25;
const BRIGHTNESS_MODEL_VERSION: u8 = 1;

const DEFAULT_HUE_STEP: u8 = 12; // 180 degrees (cyan)
const DEFAULT_SATURATION_STEP: u8 = 10;
const DEFAULT_BRIGHTNESS_STEP: u8 = 1;
const HUE_STEPS: u8 = 24;
const PERCENT_STEPS: u8 = 10;

static HUE_STEP: AtomicU8 = AtomicU8::new(DEFAULT_HUE_STEP);
static SATURATION_STEP: AtomicU8 = AtomicU8::new(DEFAULT_SATURATION_STEP);
static BRIGHTNESS_STEP: AtomicU8 = AtomicU8::new(DEFAULT_BRIGHTNESS_STEP);
static TEST_BRIGHTNESS_LEVEL: AtomicU8 = AtomicU8::new(0);
static UNDERGLOW_BRIGHTNESS_OFFSET: AtomicI8 = AtomicI8::new(0);
static BACKLIGHT_ENABLED: AtomicBool = AtomicBool::new(true);
static UNDERGLOW_ENABLED: AtomicBool = AtomicBool::new(false);
static BACKLIGHT_LAYER_COLOR_ENABLED: AtomicBool = AtomicBool::new(false);
static UNDERGLOW_LAYER_COLOR_ENABLED: AtomicBool = AtomicBool::new(false);
static ACTIVE_LAYER: AtomicU8 = AtomicU8::new(0);
static AUTO_OFF_ENABLED: AtomicBool = AtomicBool::new(false);
static AUTO_OFF_ACTIVE: AtomicBool = AtomicBool::new(false);
static SETTINGS_ENABLED: AtomicBool = AtomicBool::new(false);
static DIRTY_SETTINGS: AtomicU16 = AtomicU16::new(0);
static BRIGHTNESS_MIGRATION_PENDING: AtomicBool = AtomicBool::new(false);
#[derive(Clone, Copy)]
enum BacklightUpdate {
    Settings,
    Layer(u8),
}
static SETTINGS_CHANGED: Signal<CriticalSectionRawMutex, BacklightUpdate> = Signal::new();
static ACTIVITY_CHANGED: Signal<CriticalSectionRawMutex, ()> = Signal::new();
/// Steady state after the power-on animation: the whole backlight range
/// (everything after the underglow LEDs) stays lit.
const STEADY_RANGE: core::ops::Range<usize> = UNDERGLOW_COUNT..SK6812_COUNT;
/// Power-on ripple animation: fade steps per phase and frame interval.
/// 6 phases x 5 steps x 30 ms = 0.9 s total.
const ANIM_STEPS: u32 = 5;
const ANIM_FRAME_INTERVAL: Duration = Duration::from_millis(30);
/// Ripple LED pairs (0-based chain indices) on the underglow LEDs (LED1-6):
/// the light travels LED3/4 -> LED2/5 -> LED1/6 -> LED2/5 -> LED3/4.
const RIPPLE_CENTER: [usize; 2] = [2, 3];
const RIPPLE_MID: [usize; 2] = [1, 4];
const RIPPLE_OUTER: [usize; 2] = [0, 5];

/// Settle time after a VBUS edge. This preserves the previous 2 x 100 ms
/// debounce window without waking the executor every 100 ms while stable.
const VBUS_DEBOUNCE: Duration = Duration::from_millis(200);
const AUTO_OFF_TIMEOUT: Duration = Duration::from_secs(10 * 60);

#[derive(Clone, Copy)]
pub struct Color {
    red: u8,
    green: u8,
    blue: u8,
}

pub const OFF: Color = Color {
    red: 0,
    green: 0,
    blue: 0,
};

fn current_color(value: u8) -> Color {
    color_with_offset(value, 0)
}

fn color_with_offset(value: u8, hue_offset_steps: u8) -> Color {
    let hue_step = (HUE_STEP.load(Ordering::Relaxed) + hue_offset_steps) % HUE_STEPS;
    let hue = hue_step as u16 * 15;
    let saturation = SATURATION_STEP.load(Ordering::Relaxed) as u16 * 255 / 10;
    let chroma = value as u16 * saturation / 255;
    let sector = hue / 60;
    let remainder = hue % 60;
    let x = if sector % 2 == 0 {
        chroma * remainder / 60
    } else {
        chroma * (60 - remainder) / 60
    };
    let (red, green, blue) = match sector {
        0 => (chroma, x, 0),
        1 => (x, chroma, 0),
        2 => (0, chroma, x),
        3 => (0, x, chroma),
        4 => (x, 0, chroma),
        _ => (chroma, 0, x),
    };
    let minimum = value as u16 - chroma;
    Color {
        red: (red + minimum) as u8,
        green: (green + minimum) as u8,
        blue: (blue + minimum) as u8,
    }
}

fn maximum_level() -> u8 {
    let test_level = TEST_BRIGHTNESS_LEVEL.load(Ordering::Relaxed);
    if test_level != 0 {
        return test_level;
    }
    if SETTINGS_ENABLED.load(Ordering::Relaxed) {
        (BRIGHTNESS_STEP.load(Ordering::Relaxed) as u16 * 255 / PERCENT_STEPS as u16) as u8
    } else {
        32
    }
}

fn underglow_level() -> u8 {
    let test_level = TEST_BRIGHTNESS_LEVEL.load(Ordering::Relaxed);
    if test_level != 0 {
        return test_level;
    }
    let base = BRIGHTNESS_STEP.load(Ordering::Relaxed) as i8;
    let offset = UNDERGLOW_BRIGHTNESS_OFFSET.load(Ordering::Relaxed);
    let effective = (base + offset).clamp(0, PERCENT_STEPS as i8) as u16;
    (effective * 255 / PERCENT_STEPS as u16) as u8
}

/// Overrides both LED groups with an exact raw brightness for storage-free
/// hardware-test firmware. Normal firmware leaves this at zero.
pub fn set_test_brightness_level(level: u8) {
    TEST_BRIGHTNESS_LEVEL.store(level, Ordering::Relaxed);
}

fn encode_brightness_offset(offset: i8) -> u8 {
    (offset.clamp(-(PERCENT_STEPS as i8), PERCENT_STEPS as i8) + PERCENT_STEPS as i8) as u8
}

fn decode_brightness_offset(value: u8) -> i8 {
    value.min(PERCENT_STEPS * 2) as i8 - PERCENT_STEPS as i8
}

fn adjusted_underglow_offset(base: u8, offset: i8, delta: i8) -> i8 {
    let base = base.min(PERCENT_STEPS) as i8;
    let visible_offset = if base + offset > PERCENT_STEPS as i8 {
        PERCENT_STEPS as i8 - base
    } else if base + offset < 0 {
        -base
    } else {
        offset
    };
    (visible_offset + delta).clamp(-(PERCENT_STEPS as i8), PERCENT_STEPS as i8)
}

pub fn brightness_storage_state(
    backlight_step: u8,
    stored_underglow: u8,
    version: Option<u8>,
) -> (i8, bool) {
    if version == Some(BRIGHTNESS_MODEL_VERSION) {
        (decode_brightness_offset(stored_underglow), false)
    } else {
        (
            stored_underglow.min(PERCENT_STEPS) as i8 - backlight_step.min(PERCENT_STEPS) as i8,
            true,
        )
    }
}

/// Encodes one frame into PWM compare words (GRB, MSB first) plus the
/// trailing low latch periods.
fn encode_frame(frame: &[Color; SK6812_COUNT], words: &mut [u16; FRAME_WORDS]) {
    let mut w = 0;
    for color in frame {
        for byte in [color.green, color.red, color.blue] {
            for bit in (0..8).rev() {
                words[w] = if byte & (1 << bit) != 0 { BIT1 } else { BIT0 };
                w += 1;
            }
        }
    }
    // Latch: keep the line low for >= 50 us after the payload.
    while w < FRAME_WORDS {
        words[w] = 0x8000;
        w += 1;
    }
}

/// Sends one full per-LED frame to the SK6812 chain via PWM0 + EasyDMA.
pub async fn send_frame(pwm: &mut SequencePwm<'_>, frame: &[Color; SK6812_COUNT]) {
    let mut words = [0u16; FRAME_WORDS];
    encode_frame(frame, &mut words);
    let sequencer = SingleSequencer::new(pwm, &words, SequenceConfig::default());
    unwrap!(sequencer.start(SingleSequenceMode::Times(1)));
    // Keep the sequencer (which borrows `words`) alive until the DMA
    // sequence has finished; dropping it early stops the PWM mid-frame.
    // 1.25 us per word, plus scheduling margin.
    const FRAME_MICROS: u64 = FRAME_WORDS as u64 * 5 / 4;
    Timer::after(Duration::from_micros(FRAME_MICROS + 500)).await;
}

/// Steady frame after the power-on animation: all backlight LEDs cyan,
/// underglow LEDs off.
fn steady_frame_for_layer(layer: u8) -> [Color; SK6812_COUNT] {
    let mut frame = [OFF; SK6812_COUNT];
    if AUTO_OFF_ACTIVE.load(Ordering::Relaxed) {
        return frame;
    }
    if BACKLIGHT_ENABLED.load(Ordering::Relaxed) {
        let offset = if BACKLIGHT_LAYER_COLOR_ENABLED.load(Ordering::Relaxed) {
            layer.wrapping_mul(2) % HUE_STEPS
        } else {
            0
        };
        for slot in &mut frame[STEADY_RANGE] {
            *slot = color_with_offset(maximum_level(), offset);
        }
    }
    if UNDERGLOW_ENABLED.load(Ordering::Relaxed) {
        let offset = if UNDERGLOW_LAYER_COLOR_ENABLED.load(Ordering::Relaxed) {
            layer.wrapping_mul(2) % HUE_STEPS
        } else {
            0
        };
        for slot in &mut frame[..UNDERGLOW_COUNT] {
            *slot = color_with_offset(underglow_level(), offset);
        }
    }
    frame
}

fn steady_frame() -> [Color; SK6812_COUNT] {
    steady_frame_for_layer(ACTIVE_LAYER.load(Ordering::Relaxed))
}

async fn fade_to_layer(pwm: &mut SequencePwm<'_>, from_layer: u8, to_layer: u8) {
    let from = steady_frame_for_layer(from_layer);
    let to = steady_frame_for_layer(to_layer);
    for step in 1..=ANIM_STEPS {
        let mut frame = [OFF; SK6812_COUNT];
        for (slot, (from, to)) in frame.iter_mut().zip(from.iter().zip(to.iter())) {
            let mix = |a: u8, b: u8| {
                ((a as u32 * (ANIM_STEPS - step) + b as u32 * step) / ANIM_STEPS) as u8
            };
            *slot = Color {
                red: mix(from.red, to.red),
                green: mix(from.green, to.green),
                blue: mix(from.blue, to.blue),
            };
        }
        send_frame(pwm, &frame).await;
        Timer::after(Duration::from_millis(20)).await;
    }
}

/// Brightness interpolated over an animation phase: level = max * step / steps.
fn faded_level(step: u32) -> u8 {
    ((maximum_level() as u32 * step) / ANIM_STEPS) as u8
}

/// One crossfade phase: `from` fades out while `to` fades in, as a smooth
/// gradient of ANIM_STEPS frames with an ANIM_FRAME_INTERVAL await between
/// frames.
async fn crossfade(pwm: &mut SequencePwm<'_>, from: [usize; 2], to: [usize; 2]) {
    for step in 1..=ANIM_STEPS {
        let mut frame = [OFF; SK6812_COUNT];
        for i in from {
            frame[i] = current_color(faded_level(ANIM_STEPS - step));
        }
        for i in to {
            frame[i] = current_color(faded_level(step));
        }
        send_frame(pwm, &frame).await;
        Timer::after(ANIM_FRAME_INTERVAL).await;
    }
}

/// Power-on ripple animation, 0.9 s total, played on the underglow LEDs:
/// LED3/4 fade in, the light travels outwards to LED2/5 then LED1/6, comes
/// back the same way to LED3/4, and finally crossfades into the steady
/// all-backlight state (underglow off).
pub async fn play_power_on_animation(pwm: &mut SequencePwm<'_>) {
    // Phase 1: fade in the center pair.
    for step in 1..=ANIM_STEPS {
        let mut frame = [OFF; SK6812_COUNT];
        for i in RIPPLE_CENTER {
            frame[i] = current_color(faded_level(step));
        }
        send_frame(pwm, &frame).await;
        Timer::after(ANIM_FRAME_INTERVAL).await;
    }

    // Phases 2-4: center -> mid -> outer -> mid.
    crossfade(pwm, RIPPLE_CENTER, RIPPLE_MID).await;
    crossfade(pwm, RIPPLE_MID, RIPPLE_OUTER).await;
    crossfade(pwm, RIPPLE_OUTER, RIPPLE_MID).await;

    // Phase 5: mid -> center while the backlight steady range fades in at
    // the same time as the returning center pair.
    for step in 1..=ANIM_STEPS {
        let mut frame = [OFF; SK6812_COUNT];
        if BACKLIGHT_ENABLED.load(Ordering::Relaxed) {
            for slot in &mut frame[STEADY_RANGE] {
                *slot = current_color(faded_level(step));
            }
        }
        for i in RIPPLE_MID {
            frame[i] = current_color(faded_level(ANIM_STEPS - step));
        }
        for i in RIPPLE_CENTER {
            frame[i] = current_color(faded_level(step));
        }
        send_frame(pwm, &frame).await;
        Timer::after(ANIM_FRAME_INTERVAL).await;
    }

    // Phase 6: settle the underglow into its saved state over the fully lit
    // backlight.
    for step in 1..=ANIM_STEPS {
        let mut frame = steady_frame();
        if UNDERGLOW_ENABLED.load(Ordering::Relaxed) {
            let level = underglow_level() as u32 * step / ANIM_STEPS;
            for slot in &mut frame[..UNDERGLOW_COUNT] {
                *slot = current_color(level as u8);
            }
        } else {
            for i in RIPPLE_CENTER {
                frame[i] = current_color(faded_level(ANIM_STEPS - step));
            }
        }
        send_frame(pwm, &frame).await;
        Timer::after(ANIM_FRAME_INTERVAL).await;
    }

    send_frame(pwm, &steady_frame()).await;
}

pub fn configure(
    backlight_enabled: bool,
    underglow_enabled: bool,
    hue_step: u8,
    saturation_step: u8,
    brightness_step: u8,
    underglow_brightness_offset: i8,
    backlight_layer_color_enabled: bool,
    underglow_layer_color_enabled: bool,
    auto_off_enabled: bool,
    brightness_migration_pending: bool,
) {
    BACKLIGHT_ENABLED.store(backlight_enabled, Ordering::Relaxed);
    UNDERGLOW_ENABLED.store(underglow_enabled, Ordering::Relaxed);
    HUE_STEP.store(hue_step % HUE_STEPS, Ordering::Relaxed);
    SATURATION_STEP.store(saturation_step.min(PERCENT_STEPS), Ordering::Relaxed);
    BRIGHTNESS_STEP.store(brightness_step.min(PERCENT_STEPS), Ordering::Relaxed);
    UNDERGLOW_BRIGHTNESS_OFFSET.store(
        underglow_brightness_offset.clamp(-(PERCENT_STEPS as i8), PERCENT_STEPS as i8),
        Ordering::Relaxed,
    );
    BACKLIGHT_LAYER_COLOR_ENABLED.store(backlight_layer_color_enabled, Ordering::Relaxed);
    UNDERGLOW_LAYER_COLOR_ENABLED.store(underglow_layer_color_enabled, Ordering::Relaxed);
    AUTO_OFF_ENABLED.store(auto_off_enabled, Ordering::Relaxed);
    AUTO_OFF_ACTIVE.store(false, Ordering::Relaxed);
    SETTINGS_ENABLED.store(true, Ordering::Relaxed);
    BRIGHTNESS_MIGRATION_PENDING.store(brightness_migration_pending, Ordering::Relaxed);
    if brightness_migration_pending {
        DIRTY_SETTINGS.fetch_or(1 << 5, Ordering::Relaxed);
    }
    SETTINGS_CHANGED.signal(BacklightUpdate::Settings);
}

pub fn settings_snapshot() -> [(u8, u8); 9] {
    [
        (
            BACKLIGHT_TOGGLE_USER_ID,
            BACKLIGHT_ENABLED.load(Ordering::Relaxed) as u8,
        ),
        (
            UNDERGLOW_TOGGLE_USER_ID,
            UNDERGLOW_ENABLED.load(Ordering::Relaxed) as u8,
        ),
        (HUE_UP_USER_ID, HUE_STEP.load(Ordering::Relaxed)),
        (
            SATURATION_UP_USER_ID,
            SATURATION_STEP.load(Ordering::Relaxed),
        ),
        (
            BACKLIGHT_BRIGHTNESS_UP_USER_ID,
            BRIGHTNESS_STEP.load(Ordering::Relaxed),
        ),
        (
            UNDERGLOW_BRIGHTNESS_UP_USER_ID,
            encode_brightness_offset(UNDERGLOW_BRIGHTNESS_OFFSET.load(Ordering::Relaxed)),
        ),
        (
            BACKLIGHT_LAYER_COLOR_TOGGLE_USER_ID,
            BACKLIGHT_LAYER_COLOR_ENABLED.load(Ordering::Relaxed) as u8,
        ),
        (
            UNDERGLOW_LAYER_COLOR_TOGGLE_USER_ID,
            UNDERGLOW_LAYER_COLOR_ENABLED.load(Ordering::Relaxed) as u8,
        ),
        (
            AUTO_OFF_TOGGLE_USER_ID,
            AUTO_OFF_ENABLED.load(Ordering::Relaxed) as u8,
        ),
    ]
}

pub fn setting_value(id: u8) -> Option<u8> {
    Some(match id {
        BACKLIGHT_TOGGLE_USER_ID => BACKLIGHT_ENABLED.load(Ordering::Relaxed) as u8,
        UNDERGLOW_TOGGLE_USER_ID => UNDERGLOW_ENABLED.load(Ordering::Relaxed) as u8,
        HUE_UP_USER_ID => HUE_STEP.load(Ordering::Relaxed),
        SATURATION_UP_USER_ID => SATURATION_STEP.load(Ordering::Relaxed),
        BACKLIGHT_BRIGHTNESS_UP_USER_ID => BRIGHTNESS_STEP.load(Ordering::Relaxed),
        UNDERGLOW_BRIGHTNESS_UP_USER_ID => {
            encode_brightness_offset(UNDERGLOW_BRIGHTNESS_OFFSET.load(Ordering::Relaxed))
        }
        BACKLIGHT_LAYER_COLOR_TOGGLE_USER_ID => {
            BACKLIGHT_LAYER_COLOR_ENABLED.load(Ordering::Relaxed) as u8
        }
        UNDERGLOW_LAYER_COLOR_TOGGLE_USER_ID => {
            UNDERGLOW_LAYER_COLOR_ENABLED.load(Ordering::Relaxed) as u8
        }
        AUTO_OFF_TOGGLE_USER_ID => AUTO_OFF_ENABLED.load(Ordering::Relaxed) as u8,
        _ => return None,
    })
}

fn setting_index(id: u8) -> Option<u8> {
    Some(match id {
        BACKLIGHT_TOGGLE_USER_ID => 0,
        UNDERGLOW_TOGGLE_USER_ID => 1,
        HUE_UP_USER_ID => 2,
        SATURATION_UP_USER_ID => 3,
        BACKLIGHT_BRIGHTNESS_UP_USER_ID => 4,
        UNDERGLOW_BRIGHTNESS_UP_USER_ID => 5,
        BACKLIGHT_LAYER_COLOR_TOGGLE_USER_ID => 6,
        UNDERGLOW_LAYER_COLOR_TOGGLE_USER_ID => 7,
        AUTO_OFF_TOGGLE_USER_ID => 8,
        _ => return None,
    })
}

/// Apply a canonical LED setting without writing storage.
///
/// This is used by VIA Custom Set; Custom Save persists the resulting snapshot.
pub fn set_setting(id: u8, value: u8) -> Option<u8> {
    let value = match id {
        BACKLIGHT_TOGGLE_USER_ID => {
            let value = (value != 0) as u8;
            BACKLIGHT_ENABLED.store(value != 0, Ordering::Relaxed);
            value
        }
        UNDERGLOW_TOGGLE_USER_ID => {
            let value = (value != 0) as u8;
            UNDERGLOW_ENABLED.store(value != 0, Ordering::Relaxed);
            value
        }
        HUE_UP_USER_ID => {
            let value = value % HUE_STEPS;
            HUE_STEP.store(value, Ordering::Relaxed);
            value
        }
        SATURATION_UP_USER_ID => {
            let value = value.min(PERCENT_STEPS);
            SATURATION_STEP.store(value, Ordering::Relaxed);
            value
        }
        BACKLIGHT_BRIGHTNESS_UP_USER_ID => {
            let value = value.min(PERCENT_STEPS);
            BRIGHTNESS_STEP.store(value, Ordering::Relaxed);
            value
        }
        UNDERGLOW_BRIGHTNESS_UP_USER_ID => {
            let value = value.min(PERCENT_STEPS * 2);
            UNDERGLOW_BRIGHTNESS_OFFSET.store(decode_brightness_offset(value), Ordering::Relaxed);
            value
        }
        BACKLIGHT_LAYER_COLOR_TOGGLE_USER_ID => {
            let value = (value != 0) as u8;
            BACKLIGHT_LAYER_COLOR_ENABLED.store(value != 0, Ordering::Relaxed);
            value
        }
        UNDERGLOW_LAYER_COLOR_TOGGLE_USER_ID => {
            let value = (value != 0) as u8;
            UNDERGLOW_LAYER_COLOR_ENABLED.store(value != 0, Ordering::Relaxed);
            value
        }
        AUTO_OFF_TOGGLE_USER_ID => {
            let value = (value != 0) as u8;
            AUTO_OFF_ENABLED.store(value != 0, Ordering::Relaxed);
            AUTO_OFF_ACTIVE.store(false, Ordering::Relaxed);
            value
        }
        _ => return None,
    };
    on_activity();
    DIRTY_SETTINGS.fetch_or(1 << setting_index(id)?, Ordering::Relaxed);
    SETTINGS_CHANGED.signal(BacklightUpdate::Settings);
    Some(value)
}

pub async fn save_settings() {
    let dirty = DIRTY_SETTINGS.swap(0, Ordering::Relaxed);
    for (index, (id, value)) in settings_snapshot().into_iter().enumerate() {
        let bit = 1 << index;
        if dirty & bit != 0 && !rmk::storage::write_user_setting(id, value).await {
            DIRTY_SETTINGS.fetch_or(bit, Ordering::Relaxed);
        }
    }
    if BRIGHTNESS_MIGRATION_PENDING.swap(false, Ordering::Relaxed)
        && !rmk::storage::write_user_setting(
            BRIGHTNESS_MODEL_VERSION_USER_ID,
            BRIGHTNESS_MODEL_VERSION,
        )
        .await
    {
        BRIGHTNESS_MIGRATION_PENDING.store(true, Ordering::Relaxed);
    }
}

pub fn brightness_migration_pending() -> bool {
    BRIGHTNESS_MIGRATION_PENDING.load(Ordering::Relaxed)
}

pub async fn on_user_action(id: u8) -> Option<u8> {
    let (setting_id, value) = match id {
        BACKLIGHT_TOGGLE_USER_ID => {
            let value = !BACKLIGHT_ENABLED.load(Ordering::Relaxed);
            BACKLIGHT_ENABLED.store(value, Ordering::Relaxed);
            (BACKLIGHT_TOGGLE_USER_ID, value as u8)
        }
        UNDERGLOW_TOGGLE_USER_ID => {
            let value = !UNDERGLOW_ENABLED.load(Ordering::Relaxed);
            UNDERGLOW_ENABLED.store(value, Ordering::Relaxed);
            (UNDERGLOW_TOGGLE_USER_ID, value as u8)
        }
        HUE_UP_USER_ID => {
            let value = (HUE_STEP.load(Ordering::Relaxed) + 1) % HUE_STEPS;
            HUE_STEP.store(value, Ordering::Relaxed);
            (HUE_UP_USER_ID, value)
        }
        HUE_DOWN_USER_ID => {
            let value = (HUE_STEP.load(Ordering::Relaxed) + HUE_STEPS - 1) % HUE_STEPS;
            HUE_STEP.store(value, Ordering::Relaxed);
            (HUE_UP_USER_ID, value)
        }
        SATURATION_UP_USER_ID => {
            let value = (SATURATION_STEP.load(Ordering::Relaxed) + 1).min(PERCENT_STEPS);
            SATURATION_STEP.store(value, Ordering::Relaxed);
            (SATURATION_UP_USER_ID, value)
        }
        SATURATION_DOWN_USER_ID => {
            let value = SATURATION_STEP.load(Ordering::Relaxed).saturating_sub(1);
            SATURATION_STEP.store(value, Ordering::Relaxed);
            (SATURATION_UP_USER_ID, value)
        }
        BACKLIGHT_BRIGHTNESS_UP_USER_ID => {
            let value = (BRIGHTNESS_STEP.load(Ordering::Relaxed) + 1).min(PERCENT_STEPS);
            BRIGHTNESS_STEP.store(value, Ordering::Relaxed);
            (BACKLIGHT_BRIGHTNESS_UP_USER_ID, value)
        }
        BACKLIGHT_BRIGHTNESS_DOWN_USER_ID => {
            let value = BRIGHTNESS_STEP.load(Ordering::Relaxed).saturating_sub(1);
            BRIGHTNESS_STEP.store(value, Ordering::Relaxed);
            (BACKLIGHT_BRIGHTNESS_UP_USER_ID, value)
        }
        UNDERGLOW_BRIGHTNESS_UP_USER_ID => {
            let offset = adjusted_underglow_offset(
                BRIGHTNESS_STEP.load(Ordering::Relaxed),
                UNDERGLOW_BRIGHTNESS_OFFSET.load(Ordering::Relaxed),
                1,
            );
            UNDERGLOW_BRIGHTNESS_OFFSET.store(offset, Ordering::Relaxed);
            (
                UNDERGLOW_BRIGHTNESS_UP_USER_ID,
                encode_brightness_offset(offset),
            )
        }
        UNDERGLOW_BRIGHTNESS_DOWN_USER_ID => {
            let offset = adjusted_underglow_offset(
                BRIGHTNESS_STEP.load(Ordering::Relaxed),
                UNDERGLOW_BRIGHTNESS_OFFSET.load(Ordering::Relaxed),
                -1,
            );
            UNDERGLOW_BRIGHTNESS_OFFSET.store(offset, Ordering::Relaxed);
            (
                UNDERGLOW_BRIGHTNESS_UP_USER_ID,
                encode_brightness_offset(offset),
            )
        }
        BACKLIGHT_LAYER_COLOR_TOGGLE_USER_ID => {
            let value = !BACKLIGHT_LAYER_COLOR_ENABLED.load(Ordering::Relaxed);
            BACKLIGHT_LAYER_COLOR_ENABLED.store(value, Ordering::Relaxed);
            (BACKLIGHT_LAYER_COLOR_TOGGLE_USER_ID, value as u8)
        }
        UNDERGLOW_LAYER_COLOR_TOGGLE_USER_ID => {
            let value = !UNDERGLOW_LAYER_COLOR_ENABLED.load(Ordering::Relaxed);
            UNDERGLOW_LAYER_COLOR_ENABLED.store(value, Ordering::Relaxed);
            (UNDERGLOW_LAYER_COLOR_TOGGLE_USER_ID, value as u8)
        }
        AUTO_OFF_TOGGLE_USER_ID => {
            let value = !AUTO_OFF_ENABLED.load(Ordering::Relaxed);
            AUTO_OFF_ENABLED.store(value, Ordering::Relaxed);
            AUTO_OFF_ACTIVE.store(false, Ordering::Relaxed);
            (AUTO_OFF_TOGGLE_USER_ID, value as u8)
        }
        _ => return None,
    };

    SETTINGS_CHANGED.signal(BacklightUpdate::Settings);
    let _ = rmk::storage::write_user_setting(setting_id, value).await;
    Some(value)
}

pub fn on_layer_change(layer: u8) {
    ACTIVE_LAYER.store(layer, Ordering::Relaxed);
    SETTINGS_CHANGED.signal(BacklightUpdate::Layer(layer));
}

#[cfg(feature = "split")]
pub fn apply_user_state(id: u8, value: u8) {
    match id {
        BACKLIGHT_TOGGLE_USER_ID => BACKLIGHT_ENABLED.store(value != 0, Ordering::Relaxed),
        UNDERGLOW_TOGGLE_USER_ID => UNDERGLOW_ENABLED.store(value != 0, Ordering::Relaxed),
        HUE_UP_USER_ID | HUE_DOWN_USER_ID => HUE_STEP.store(value % HUE_STEPS, Ordering::Relaxed),
        SATURATION_UP_USER_ID | SATURATION_DOWN_USER_ID => {
            SATURATION_STEP.store(value.min(PERCENT_STEPS), Ordering::Relaxed)
        }
        BACKLIGHT_BRIGHTNESS_UP_USER_ID | BACKLIGHT_BRIGHTNESS_DOWN_USER_ID => {
            BRIGHTNESS_STEP.store(value.min(PERCENT_STEPS), Ordering::Relaxed)
        }
        UNDERGLOW_BRIGHTNESS_UP_USER_ID | UNDERGLOW_BRIGHTNESS_DOWN_USER_ID => {
            UNDERGLOW_BRIGHTNESS_OFFSET.store(decode_brightness_offset(value), Ordering::Relaxed)
        }
        BACKLIGHT_LAYER_COLOR_TOGGLE_USER_ID => {
            BACKLIGHT_LAYER_COLOR_ENABLED.store(value != 0, Ordering::Relaxed)
        }
        UNDERGLOW_LAYER_COLOR_TOGGLE_USER_ID => {
            UNDERGLOW_LAYER_COLOR_ENABLED.store(value != 0, Ordering::Relaxed)
        }
        AUTO_OFF_TOGGLE_USER_ID => {
            AUTO_OFF_ENABLED.store(value != 0, Ordering::Relaxed);
            AUTO_OFF_ACTIVE.store(false, Ordering::Relaxed);
        }
        _ => return,
    }
    SETTINGS_CHANGED.signal(BacklightUpdate::Settings);
}

pub fn on_activity() {
    ACTIVITY_CHANGED.signal(());
}

#[cfg(test)]
mod tests {
    use super::adjusted_underglow_offset;

    #[test]
    fn discards_hidden_overflow_before_adjusting_down() {
        assert_eq!(adjusted_underglow_offset(7, 5, -1), 2);
    }

    #[test]
    fn discards_hidden_underflow_before_adjusting_up() {
        assert_eq!(adjusted_underglow_offset(3, -5, 1), -2);
    }

    #[test]
    fn keeps_visible_offset_when_not_clamped() {
        assert_eq!(adjusted_underglow_offset(5, 2, 1), 3);
        assert_eq!(adjusted_underglow_offset(5, 2, -1), 1);
    }
}

/// PWM config for the SK6812 data line, shared by the cold-boot animation in
/// main() and backlight_vbus_task.
pub fn backlight_pwm_config() -> PwmConfig {
    let mut config = PwmConfig::default();
    config.prescaler = Prescaler::Div1; // 16 MHz PWM clock
    config.max_duty = PWM_TOP;
    config.sequence_load = SequenceLoad::Common;
    // Idle low: the data line must never sit high while the 5V domain is
    // unpowered (no back-powering through the SK6812 protection diodes).
    config.ch0_idle_level = Level::Low;
    config
}

/// Waits for vbus_sense edges and gates the SK6812 backlight on 5V presence; see
/// `main.rs` for the full rationale. `initially_powered`: true when main()
/// already detected 5V at boot and played the power-on animation.
#[embassy_executor::task]
pub async fn backlight_vbus_task(
    mut vbus_sense: Input<'static>,
    pwm: Peri<'static, PWM0>,
    data_pin: Peri<'static, P1_15>,
    initially_powered: bool,
) -> ! {
    crate::low_power_hc595_matrix::set_vbus_present(vbus_sense.is_high());
    let mut pwm = unwrap!(SequencePwm::new_1ch(pwm, data_pin, backlight_pwm_config()));

    let mut powered = initially_powered;
    let mut rendered_layer = ACTIVE_LAYER.load(Ordering::Relaxed);
    let mut last_activity = embassy_time::Instant::now();
    if powered {
        // The cold-boot animation already ran; restore the steady frame in
        // case the line glitched while the PWM was re-initialized.
        send_frame(&mut pwm, &steady_frame()).await;
    }

    loop {
        // Reconcile the current level before arming the edge wait. This also
        // catches a VBUS change that happened during BLE/USB/storage init.
        if vbus_sense.is_high() == powered {
            let auto_off_timer = async {
                if AUTO_OFF_ENABLED.load(Ordering::Relaxed) {
                    Timer::at(last_activity + AUTO_OFF_TIMEOUT).await;
                } else {
                    pending::<()>().await;
                }
            };
            let activity_or_timeout = select(ACTIVITY_CHANGED.wait(), auto_off_timer);
            match select3(
                vbus_sense.wait_for_any_edge(),
                SETTINGS_CHANGED.wait(),
                activity_or_timeout,
            )
            .await
            {
                Either3::First(_) => {}
                Either3::Second(update) => {
                    last_activity = embassy_time::Instant::now();
                    AUTO_OFF_ACTIVE.store(false, Ordering::Relaxed);
                    if powered {
                        match update {
                            BacklightUpdate::Settings => {
                                send_frame(&mut pwm, &steady_frame()).await;
                            }
                            BacklightUpdate::Layer(layer) => {
                                fade_to_layer(&mut pwm, rendered_layer, layer).await;
                                rendered_layer = layer;
                            }
                        }
                    } else if let BacklightUpdate::Layer(layer) = update {
                        rendered_layer = layer;
                    }
                    continue;
                }
                Either3::Third(Either::First(_)) => {
                    last_activity = embassy_time::Instant::now();
                    let was_off = AUTO_OFF_ACTIVE.swap(false, Ordering::Relaxed);
                    if powered && was_off {
                        send_frame(&mut pwm, &steady_frame()).await;
                    }
                    continue;
                }
                Either3::Third(Either::Second(_)) => {
                    AUTO_OFF_ACTIVE.store(true, Ordering::Relaxed);
                    if powered {
                        send_frame(&mut pwm, &[OFF; SK6812_COUNT]).await;
                    }
                    continue;
                }
            }
        }

        Timer::after(VBUS_DEBOUNCE).await;
        let stable = vbus_sense.is_high();
        crate::low_power_hc595_matrix::set_vbus_present(stable);
        if stable == powered {
            continue;
        }

        powered = stable;
        if powered {
            last_activity = embassy_time::Instant::now();
            AUTO_OFF_ACTIVE.store(false, Ordering::Relaxed);
            info!("5V detected: power-on animation, then steady backlight");
            // Clear the SK6812s' random power-up state before animating.
            send_frame(&mut pwm, &[OFF; SK6812_COUNT]).await;
            send_frame(&mut pwm, &[OFF; SK6812_COUNT]).await;
            play_power_on_animation(&mut pwm).await;
        } else {
            info!("5V lost: backlight line held low");
            // Do not transmit anything: the 5V rail is down. The line
            // already idles low, preventing back-powering.
        }
    }
}
