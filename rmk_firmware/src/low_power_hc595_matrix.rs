//! Project-local 74HC595 matrix scanner with an interrupt-driven idle state.
//!
//! RMK's current `Hc595Matrix` clears every column and waits on a 1 ms timer
//! when no key is pressed. This variant drives every column high while idle so
//! a col-to-row key press raises one of the pulled-down row inputs, then waits
//! on the row GPIO interrupts. Key identification and release detection still
//! use the normal one-hot column scan.

use core::sync::atomic::{AtomicBool, Ordering};

use embassy_nrf::pac;
use embassy_time::{Duration, Timer};
use embedded_hal::digital::{InputPin, OutputPin};
use embedded_hal_async::digital::Wait;
use embedded_hal_async::spi::SpiDevice;
use rmk::debounce::{DebounceState, DebouncerTrait};
use rmk::embassy_futures::select::{Either3, select_array, select3};
use rmk::event::{KeyboardEvent, SubscribableEvent};
use rmk::macros::input_device;
use rmk::matrix::{KeyState, MatrixTrait};

const SR_MAX_BYTES: usize = 4;
const SR_CLEAR_SETTLE_US: u64 = 3;
const SR_COLUMN_SETTLE_US: u64 = 40;
const SYSTEM_OFF_TIMEOUT: Duration = Duration::from_secs(15 * 60);

static VBUS_PRESENT: AtomicBool = AtomicBool::new(false);
static REMOTE_ACTIVITY: embassy_sync::signal::Signal<rmk::RawMutex, ()> =
    embassy_sync::signal::Signal::new();

pub fn set_vbus_present(present: bool) {
    VBUS_PRESENT.store(present, Ordering::Release);
}

#[embassy_executor::task]
pub async fn remote_activity_task() -> ! {
    let mut keyboard_events = KeyboardEvent::subscriber();
    loop {
        let _ = keyboard_events.next_message_pure().await;
        REMOTE_ACTIVITY.signal(());
    }
}

#[input_device(publish = KeyboardEvent)]
pub struct LowPowerHc595Matrix<
    SPI: SpiDevice<u8>,
    LATCH: OutputPin,
    In: Wait + InputPin,
    D: DebouncerTrait<ROW, COL>,
    const ROW: usize,
    const COL: usize,
    const ROW_OFFSET: usize = 0,
    const COL_OFFSET: usize = 0,
    const SYSTEM_OFF: bool = false,
> {
    spi: SPI,
    latch: LATCH,
    row_pins: [In; ROW],
    debouncer: D,
    key_states: [[KeyState; ROW]; COL],
    scan_pos: (usize, usize),
    rescan_needed: bool,
}

impl<
    SPI: SpiDevice<u8>,
    LATCH: OutputPin,
    In: Wait + InputPin,
    D: DebouncerTrait<ROW, COL>,
    const ROW: usize,
    const COL: usize,
    const ROW_OFFSET: usize,
    const COL_OFFSET: usize,
    const SYSTEM_OFF: bool,
> LowPowerHc595Matrix<SPI, LATCH, In, D, ROW, COL, ROW_OFFSET, COL_OFFSET, SYSTEM_OFF>
{
    const NUM_BYTES: usize = {
        if COL > SR_MAX_BYTES * 8 {
            panic!("LowPowerHc595Matrix supports up to 32 columns");
        }
        COL.div_ceil(8)
    };

    pub async fn new(spi: SPI, latch: LATCH, row_pins: [In; ROW], debouncer: D) -> Self {
        let mut matrix = Self {
            spi,
            latch,
            row_pins,
            debouncer,
            key_states: [[KeyState::new(); ROW]; COL],
            scan_pos: (0, 0),
            rescan_needed: false,
        };
        matrix.clear_columns().await;
        matrix
    }

    async fn pulse_latch(&mut self, data: &[u8]) {
        self.latch.set_low().ok();
        let _ = self.spi.write(data).await;
        self.latch.set_high().ok();
    }

    fn col_bitmask(col_idx: usize) -> [u8; SR_MAX_BYTES] {
        let mut buf = [0u8; SR_MAX_BYTES];
        let byte_pos = col_idx / 8;
        let bit_pos = col_idx % 8;
        buf[Self::NUM_BYTES - 1 - byte_pos] = 1 << bit_pos;
        buf
    }

    async fn clear_columns(&mut self) {
        let zeros = [0u8; SR_MAX_BYTES];
        self.pulse_latch(&zeros[..Self::NUM_BYTES]).await;
    }

    async fn drive_all_columns(&mut self) {
        let ones = [0xffu8; SR_MAX_BYTES];
        self.pulse_latch(&ones[..Self::NUM_BYTES]).await;
    }

    async fn wait_for_row_high(&mut self) {
        self.drive_all_columns().await;
        Timer::after_micros(SR_COLUMN_SETTLE_US).await;

        // Avoid sleeping when a key was pressed before the GPIO wait futures
        // were armed. `wait_for_high` is level-sensitive as well, so a press
        // in the small interval after this check also completes immediately.
        if self
            .row_pins
            .iter_mut()
            .any(|row_pin| row_pin.is_high().ok().unwrap_or(false))
        {
            return;
        }

        loop {
            let waits = self
                .row_pins
                .each_mut()
                .map(|row_pin| row_pin.wait_for_high());
            if !SYSTEM_OFF {
                let _ = select_array(waits).await;
                return;
            }

            match select3(
                select_array(waits),
                Timer::after(SYSTEM_OFF_TIMEOUT),
                REMOTE_ACTIVITY.wait(),
            )
            .await
            {
                Either3::First(_) => return,
                Either3::Second(_) => {}
                Either3::Third(_) => continue,
            }

            // VBUS may have become known or changed after this idle timer was
            // armed. Recheck at the destructive boundary; while USB is present,
            // stay awake and check again after another timeout interval.
            if VBUS_PRESENT.load(Ordering::Acquire) {
                continue;
            }

            // Do not enter System OFF if a press raced the timeout. A subsequent
            // idle period starts a fresh timer after that key is processed.
            if self
                .row_pins
                .iter_mut()
                .any(|row_pin| row_pin.is_high().ok().unwrap_or(false))
            {
                return;
            }

            enter_system_off();
        }
    }

    async fn read_keyboard_event(&mut self) -> KeyboardEvent {
        loop {
            let (col_start, row_start) = self.scan_pos;

            for col_idx in col_start..COL {
                self.clear_columns().await;
                Timer::after_micros(SR_CLEAR_SETTLE_US).await;

                let bitmask = Self::col_bitmask(col_idx);
                self.pulse_latch(&bitmask[..Self::NUM_BYTES]).await;
                Timer::after_micros(SR_COLUMN_SETTLE_US).await;

                let r_start = if col_idx == col_start { row_start } else { 0 };

                for row_idx in r_start..ROW {
                    let pin_high = self.row_pins[row_idx].is_high().ok().unwrap_or(false);
                    let debounce_state = self.debouncer.detect_change_with_debounce(
                        row_idx,
                        col_idx,
                        pin_high,
                        &self.key_states[col_idx][row_idx],
                    );

                    if let DebounceState::Debounced = debounce_state {
                        self.key_states[col_idx][row_idx].toggle_pressed();
                        self.scan_pos = (col_idx, row_idx);
                        self.rescan_needed = true;
                        self.clear_columns().await;
                        return KeyboardEvent::key(
                            (row_idx + ROW_OFFSET) as u8,
                            (col_idx + COL_OFFSET) as u8,
                            self.key_states[col_idx][row_idx].pressed,
                        );
                    }

                    if self.key_states[col_idx][row_idx].pressed {
                        self.rescan_needed = true;
                    }
                }
            }

            self.clear_columns().await;

            if !self.rescan_needed {
                self.wait_for_row_high().await;
            }
            self.rescan_needed = false;

            // Keep RMK's existing scan/debounce cadence while a key is held
            // or immediately after waking. Idle time is spent in GPIO wait.
            Timer::after_millis(1).await;
            self.scan_pos = (0, 0);
        }
    }
}

impl<
    SPI: SpiDevice<u8>,
    LATCH: OutputPin,
    In: Wait + InputPin,
    D: DebouncerTrait<ROW, COL>,
    const ROW: usize,
    const COL: usize,
    const ROW_OFFSET: usize,
    const COL_OFFSET: usize,
    const SYSTEM_OFF: bool,
> MatrixTrait<ROW, COL>
    for LowPowerHc595Matrix<SPI, LATCH, In, D, ROW, COL, ROW_OFFSET, COL_OFFSET, SYSTEM_OFF>
{
    async fn wait_for_key(&mut self) {
        self.wait_for_row_high().await;
    }
}

fn enter_system_off() -> ! {
    // The matrix is already in its all-columns-high wake state. Configure the
    // three pulled-down row pins for level-high GPIO sensing, which is retained
    // in System OFF and resets the nRF52840 when any switch closes.
    for pin in [14, 13, 12] {
        pac::P1.pin_cnf(pin).modify(|w| {
            w.set_dir(pac::gpio::vals::Dir::Input);
            w.set_input(pac::gpio::vals::Input::Connect);
            w.set_pull(pac::gpio::vals::Pull::Pulldown);
            w.set_sense(pac::gpio::vals::Sense::High);
        });
    }

    // Keep application indicators and the SK6812 data line low across
    // System OFF. QSPI was already placed in Deep Power-Down at startup.
    pac::P0.outclr().write(|w| {
        w.set_pin(28, true);
        w.set_pin(29, true);
    });
    pac::P1.outclr().write(|w| w.set_pin(15, true));

    embassy_nrf::power::set_system_off();
    loop {
        cortex_m::asm::wfe();
    }
}
