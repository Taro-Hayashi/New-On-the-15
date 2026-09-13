use core::convert::Infallible;
use core::future::pending;

use embassy_time::{Duration, Instant, Timer};
use embedded_hal::digital::OutputPin;
use rmk::core_traits::Runnable;
#[cfg(feature = "split")]
use rmk::embassy_futures::select::{Either3, select3};
use rmk::embassy_futures::select::{Either6, select6};
use rmk::event::{
    ActionEvent, BatteryStatusEvent, ConnectionStatus, ConnectionStatusChangeEvent,
    EventSubscriber, LayerChangeEvent, SleepStateEvent, SubscribableEvent,
};
#[cfg(feature = "split")]
use rmk::event::{CentralConnectedEvent, UserStateEvent, publish_user_state};
use rmk::host::custom_value::{
    CustomValueCommand, CustomValueRequest, CustomValueResponse, receive as receive_custom_value,
    reply as reply_custom_value,
};
use rmk::types::action::Action;
use rmk::types::battery::BatteryStatus;

pub const INDICATOR_TOGGLE_USER_ID: u8 = 11;
const LIGHTING_CHANNEL_ID: u8 = 0;
const QMK_RGBLIGHT_BRIGHTNESS: u8 = 0x80;
const QMK_RGBLIGHT_EFFECT: u8 = 0x81;
const QMK_RGBLIGHT_EFFECT_SPEED: u8 = 0x82;
const QMK_RGBLIGHT_COLOR: u8 = 0x83;
const QMK_RGBLIGHT_SOLID_EFFECT: u8 = 1;

const LOW_BATTERY_PERCENT: u8 = 20;
const LOW_BATTERY_RELEASE_PERCENT: u8 = 25;
const LOW_BATTERY_CONFIRM_DELAY: Duration = Duration::from_secs(30);

#[cfg_attr(not(feature = "split"), allow(dead_code))]
#[derive(Clone, Copy, PartialEq, Eq)]
enum Role {
    Standalone,
    #[cfg(feature = "split")]
    Central,
    #[cfg(feature = "split")]
    Peripheral,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Mode {
    Off,
    Connected,
    Disconnected,
    LowBattery,
    Maintenance,
    Function,
    FeedbackGreen,
    FeedbackRed,
    FeedbackBatteryType,
}

#[derive(Clone, Copy)]
enum LowBatteryTransition {
    Enter,
    Exit,
}

pub struct StatusIndicator<G, R> {
    green: G,
    red: R,
    #[cfg_attr(not(feature = "split"), allow(dead_code))]
    role: Role,
    connection: ConnectionStatus,
    layer: u8,
    sleeping: bool,
    #[cfg(feature = "split")]
    central_connected: bool,
    battery_percent: u8,
    low_battery: bool,
    low_battery_transition: Option<(LowBatteryTransition, Instant)>,
    connected_indicator_enabled: bool,
    mode: Mode,
    phase: u8,
    feedback_pulses: u8,
    feedback_first_green: bool,
    pattern_deadline: Option<Instant>,
}

impl<G, R> StatusIndicator<G, R>
where
    G: OutputPin<Error = Infallible>,
    R: OutputPin<Error = Infallible>,
{
    #[cfg(not(feature = "split"))]
    pub fn standalone(green: G, red: R, connected_indicator_enabled: bool) -> Self {
        Self::new(green, red, Role::Standalone, connected_indicator_enabled)
    }

    #[cfg(feature = "split")]
    pub fn central(green: G, red: R, connected_indicator_enabled: bool) -> Self {
        publish_user_state(INDICATOR_TOGGLE_USER_ID, connected_indicator_enabled as u8);
        Self::new(green, red, Role::Central, connected_indicator_enabled)
    }

    #[cfg(feature = "split")]
    pub fn peripheral(green: G, red: R) -> Self {
        Self::new(green, red, Role::Peripheral, false)
    }

    fn new(green: G, red: R, role: Role, connected_indicator_enabled: bool) -> Self {
        Self {
            green,
            red,
            role,
            connection: ConnectionStatus::default(),
            layer: 0,
            sleeping: false,
            #[cfg(feature = "split")]
            central_connected: false,
            battery_percent: 100,
            low_battery: false,
            low_battery_transition: None,
            connected_indicator_enabled,
            mode: Mode::Off,
            phase: 0,
            feedback_pulses: 0,
            feedback_first_green: true,
            pattern_deadline: None,
        }
    }

    fn persists_user_setting(&self) -> bool {
        #[cfg(feature = "split")]
        {
            return self.role != Role::Peripheral;
        }
        #[cfg(not(feature = "split"))]
        true
    }

    fn set_leds(&mut self, green: bool, red: bool) {
        if green {
            let _ = self.green.set_high();
        } else {
            let _ = self.green.set_low();
        }
        if red {
            let _ = self.red.set_high();
        } else {
            let _ = self.red.set_low();
        }
    }

    fn select_mode(&self) -> Mode {
        if matches!(
            self.mode,
            Mode::FeedbackGreen | Mode::FeedbackRed | Mode::FeedbackBatteryType
        ) {
            return self.mode;
        }
        if self.sleeping {
            return Mode::Off;
        }
        if self.layer == 1 {
            return Mode::Maintenance;
        }
        if self.layer >= 2 {
            return Mode::Function;
        }
        let usb_powered = !matches!(
            self.connection.usb,
            rmk::types::connection::UsbState::Disabled
        );
        if self.low_battery && !usb_powered {
            return Mode::LowBattery;
        }
        #[cfg(feature = "split")]
        if self.role == Role::Peripheral && !self.central_connected {
            return Mode::Disconnected;
        }
        if self.connection.decide_active().is_none() {
            return Mode::Disconnected;
        }
        if self.connected_indicator_enabled {
            Mode::Connected
        } else {
            Mode::Off
        }
    }

    fn refresh(&mut self) {
        self.mode = self.select_mode();
        self.phase = 0;
        self.apply_pattern_step();
    }

    fn schedule_after(&mut self, millis: u64) {
        self.pattern_deadline = Some(Instant::now() + Duration::from_millis(millis));
    }

    fn apply_pattern_step(&mut self) {
        self.pattern_deadline = None;
        match self.mode {
            Mode::Off => self.set_leds(false, false),
            Mode::Connected => self.set_leds(true, false),
            Mode::Maintenance => self.set_leds(true, true),
            Mode::Disconnected => {
                self.set_leds(false, self.phase == 0);
                self.phase = (self.phase + 1) % 2;
                self.schedule_after(500);
            }
            Mode::LowBattery => {
                const DELAYS: [u64; 5] = [150, 150, 150, 150, 4_400];
                self.set_leds(false, self.phase == 0 || self.phase == 2);
                let delay = DELAYS[self.phase as usize];
                self.phase = (self.phase + 1) % DELAYS.len() as u8;
                self.schedule_after(delay);
            }
            Mode::Function => {
                const DELAYS: [u64; 5] = [150, 150, 150, 150, 400];
                self.set_leds(self.phase == 0 || self.phase == 2, false);
                let delay = DELAYS[self.phase as usize];
                self.phase = (self.phase + 1) % DELAYS.len() as u8;
                self.schedule_after(delay);
            }
            Mode::FeedbackGreen | Mode::FeedbackRed => {
                let active = self.phase < self.feedback_pulses * 2 && self.phase % 2 == 0;
                self.set_leds(
                    self.mode == Mode::FeedbackGreen && active,
                    self.mode == Mode::FeedbackRed && active,
                );
                if self.phase >= self.feedback_pulses * 2 {
                    self.mode = Mode::Off;
                    self.refresh();
                } else {
                    self.phase += 1;
                    self.schedule_after(150);
                }
            }
            Mode::FeedbackBatteryType => {
                let active = self.phase == 0 || self.phase == 2;
                let green = if self.phase < 2 {
                    self.feedback_first_green
                } else {
                    !self.feedback_first_green
                };
                self.set_leds(active && green, active && !green);
                if self.phase >= 3 {
                    self.mode = Mode::Off;
                    self.refresh();
                } else {
                    self.phase += 1;
                    self.schedule_after(150);
                }
            }
        }
    }

    fn show_feedback(&mut self, green: bool, pulses: u8) {
        self.mode = if green {
            Mode::FeedbackGreen
        } else {
            Mode::FeedbackRed
        };
        self.feedback_pulses = pulses;
        self.phase = 0;
        self.apply_pattern_step();
    }

    fn show_battery_type_feedback(&mut self, alkaline: bool) {
        self.mode = Mode::FeedbackBatteryType;
        self.feedback_first_green = !alkaline;
        self.phase = 0;
        self.apply_pattern_step();
    }

    fn update_low_battery_request(&mut self) {
        if !crate::battery::low_battery_warning_enabled() {
            self.low_battery = false;
            self.low_battery_transition = None;
            return;
        }
        let requested = if !self.low_battery && self.battery_percent <= LOW_BATTERY_PERCENT {
            Some(LowBatteryTransition::Enter)
        } else if self.low_battery && self.battery_percent >= LOW_BATTERY_RELEASE_PERCENT {
            Some(LowBatteryTransition::Exit)
        } else {
            None
        };
        self.low_battery_transition =
            requested.map(|transition| (transition, Instant::now() + LOW_BATTERY_CONFIRM_DELAY));
    }

    fn finish_low_battery_transition(&mut self, now: Instant) {
        let Some((transition, deadline)) = self.low_battery_transition else {
            return;
        };
        if deadline > now {
            return;
        }
        match transition {
            LowBatteryTransition::Enter if self.battery_percent <= LOW_BATTERY_PERCENT => {
                self.low_battery = true
            }
            LowBatteryTransition::Exit if self.battery_percent >= LOW_BATTERY_RELEASE_PERCENT => {
                self.low_battery = false
            }
            _ => {}
        }
        self.low_battery_transition = None;
        self.refresh();
    }

    fn next_deadline(&self) -> Option<Instant> {
        [
            self.pattern_deadline,
            self.low_battery_transition.map(|(_, deadline)| deadline),
        ]
        .into_iter()
        .flatten()
        .min()
    }

    async fn on_action(&mut self, event: ActionEvent) {
        if event.keyboard_event.pressed {
            crate::backlight::on_activity();
        }
        let Action::User(id) = event.action else {
            return;
        };
        if event.keyboard_event.pressed {
            return;
        }
        match id {
            0..=4 => self.show_feedback(true, id + 1),
            7 => self.show_feedback(false, 3),
            INDICATOR_TOGGLE_USER_ID => {
                self.connected_indicator_enabled = !self.connected_indicator_enabled;
                if self.persists_user_setting() {
                    let _ = rmk::storage::write_user_setting(
                        INDICATOR_TOGGLE_USER_ID,
                        self.connected_indicator_enabled as u8,
                    )
                    .await;
                }
                #[cfg(feature = "split")]
                if self.role == Role::Central {
                    publish_user_state(
                        INDICATOR_TOGGLE_USER_ID,
                        self.connected_indicator_enabled as u8,
                    );
                }
                self.refresh();
            }
            crate::battery::LOW_BATTERY_WARNING_USER_ID => {
                let enabled = !crate::battery::low_battery_warning_enabled();
                crate::battery::set_low_battery_warning_enabled(enabled);
                if !enabled {
                    self.low_battery = false;
                    self.low_battery_transition = None;
                } else {
                    self.update_low_battery_request();
                }
                if self.persists_user_setting() {
                    let _ = rmk::storage::write_user_setting(
                        crate::battery::LOW_BATTERY_WARNING_USER_ID,
                        enabled as u8,
                    )
                    .await;
                }
                #[cfg(feature = "split")]
                if self.role == Role::Central {
                    publish_user_state(crate::battery::LOW_BATTERY_WARNING_USER_ID, enabled as u8);
                }
                self.show_feedback(enabled, 3);
            }
            crate::battery::BATTERY_TYPE_USER_ID => {
                let battery_type = crate::battery::toggle_battery_type();
                if self.persists_user_setting() {
                    let _ = rmk::storage::write_user_setting(
                        crate::battery::BATTERY_TYPE_USER_ID,
                        battery_type as u8,
                    )
                    .await;
                }
                #[cfg(feature = "split")]
                if self.role == Role::Central {
                    publish_user_state(crate::battery::BATTERY_TYPE_USER_ID, battery_type as u8);
                }
                self.show_battery_type_feedback(
                    battery_type == crate::battery::BatteryType::Alkaline,
                );
            }
            _ => {
                let value = crate::backlight::on_user_action(id).await;
                #[cfg(feature = "split")]
                if self.role == Role::Central {
                    if let Some(value) = value {
                        publish_user_state(id, value);
                    }
                }
                if id == crate::backlight::AUTO_OFF_TOGGLE_USER_ID {
                    if let Some(value) = value {
                        self.show_feedback(value != 0, 2);
                    }
                }
            }
        }
    }

    async fn on_custom_value(&mut self, request: CustomValueRequest) {
        if request.channel_id != LIGHTING_CHANNEL_ID {
            reply_custom_value(CustomValueResponse::Unhandled).await;
            return;
        }

        if request.command == CustomValueCommand::Save {
            crate::backlight::save_settings().await;
            reply_custom_value(CustomValueResponse::Handled([0; 29])).await;
            return;
        }

        if matches!(
            request.value_id,
            QMK_RGBLIGHT_BRIGHTNESS
                | QMK_RGBLIGHT_EFFECT
                | QMK_RGBLIGHT_EFFECT_SPEED
                | QMK_RGBLIGHT_COLOR
        ) {
            let mut payload = [0; 29];
            match request.command {
                CustomValueCommand::Get => match request.value_id {
                    QMK_RGBLIGHT_BRIGHTNESS => {
                        let brightness = crate::backlight::setting_value(
                            crate::backlight::BACKLIGHT_BRIGHTNESS_UP_USER_ID,
                        )
                        .unwrap_or(0);
                        payload[0] = (brightness as u16 * 255 / 10) as u8;
                    }
                    QMK_RGBLIGHT_EFFECT => payload[0] = QMK_RGBLIGHT_SOLID_EFFECT,
                    QMK_RGBLIGHT_EFFECT_SPEED => payload[0] = 0,
                    QMK_RGBLIGHT_COLOR => {
                        let hue = crate::backlight::setting_value(crate::backlight::HUE_UP_USER_ID)
                            .unwrap_or(0);
                        let saturation = crate::backlight::setting_value(
                            crate::backlight::SATURATION_UP_USER_ID,
                        )
                        .unwrap_or(0);
                        payload[0] = (hue as u16 * 255 / 24) as u8;
                        payload[1] = (saturation as u16 * 255 / 10) as u8;
                    }
                    _ => unreachable!(),
                },
                CustomValueCommand::Set if request.value_id == QMK_RGBLIGHT_BRIGHTNESS => {
                    let brightness = ((request.payload[0] as u16 * 10 + 127) / 255).min(10) as u8;
                    crate::backlight::set_setting(
                        crate::backlight::BACKLIGHT_BRIGHTNESS_UP_USER_ID,
                        brightness,
                    );
                    #[cfg(feature = "split")]
                    if self.role == Role::Central {
                        publish_user_state(
                            crate::backlight::BACKLIGHT_BRIGHTNESS_UP_USER_ID,
                            brightness,
                        );
                    }
                }
                CustomValueCommand::Set if request.value_id == QMK_RGBLIGHT_COLOR => {
                    let hue = ((request.payload[0] as u16 * 24 + 127) / 255 % 24) as u8;
                    let saturation = ((request.payload[1] as u16 * 10 + 127) / 255).min(10) as u8;
                    crate::backlight::set_setting(crate::backlight::HUE_UP_USER_ID, hue);
                    crate::backlight::set_setting(
                        crate::backlight::SATURATION_UP_USER_ID,
                        saturation,
                    );
                    #[cfg(feature = "split")]
                    if self.role == Role::Central {
                        publish_user_state(crate::backlight::HUE_UP_USER_ID, hue);
                        publish_user_state(crate::backlight::SATURATION_UP_USER_ID, saturation);
                    }
                }
                CustomValueCommand::Set => {}
                CustomValueCommand::Save => unreachable!(),
            }
            reply_custom_value(CustomValueResponse::Handled(payload)).await;
            return;
        }

        let setting_id = match request.value_id {
            1 => crate::backlight::BACKLIGHT_TOGGLE_USER_ID,
            2 => crate::backlight::UNDERGLOW_TOGGLE_USER_ID,
            3 => crate::backlight::HUE_UP_USER_ID,
            4 => crate::backlight::SATURATION_UP_USER_ID,
            5 => crate::backlight::BACKLIGHT_BRIGHTNESS_UP_USER_ID,
            6 => crate::backlight::UNDERGLOW_BRIGHTNESS_UP_USER_ID,
            7 => crate::backlight::BACKLIGHT_LAYER_COLOR_TOGGLE_USER_ID,
            8 => crate::backlight::UNDERGLOW_LAYER_COLOR_TOGGLE_USER_ID,
            9 => crate::backlight::AUTO_OFF_TOGGLE_USER_ID,
            _ => {
                reply_custom_value(CustomValueResponse::Unhandled).await;
                return;
            }
        };

        let mut payload = [0; 29];
        match request.command {
            CustomValueCommand::Get => {
                payload[0] = crate::backlight::setting_value(setting_id).unwrap_or(0);
            }
            CustomValueCommand::Set => {
                let previous = crate::backlight::setting_value(setting_id);
                let Some(value) = crate::backlight::set_setting(setting_id, request.payload[0])
                else {
                    reply_custom_value(CustomValueResponse::Unhandled).await;
                    return;
                };
                #[cfg(feature = "split")]
                if self.role == Role::Central {
                    publish_user_state(setting_id, value);
                }
                if setting_id == crate::backlight::AUTO_OFF_TOGGLE_USER_ID
                    && previous != Some(value)
                {
                    self.show_feedback(value != 0, 2);
                }
            }
            CustomValueCommand::Save => unreachable!(),
        }
        reply_custom_value(CustomValueResponse::Handled(payload)).await;
    }

    fn on_connection(&mut self, event: ConnectionStatusChangeEvent) {
        self.connection = event.0;
        self.refresh();
    }

    fn on_layer(&mut self, event: LayerChangeEvent) {
        self.layer = event.0;
        crate::backlight::on_layer_change(event.0);
        #[cfg(feature = "split")]
        if self.role == Role::Central {
            publish_user_state(31, event.0);
        }
        self.refresh();
    }

    #[cfg(feature = "split")]
    fn publish_split_state(&self) {
        publish_user_state(
            INDICATOR_TOGGLE_USER_ID,
            self.connected_indicator_enabled as u8,
        );
        for (id, value) in crate::backlight::settings_snapshot() {
            publish_user_state(id, value);
        }
        publish_user_state(
            crate::battery::LOW_BATTERY_WARNING_USER_ID,
            crate::battery::low_battery_warning_enabled() as u8,
        );
        publish_user_state(
            crate::battery::BATTERY_TYPE_USER_ID,
            crate::battery::battery_type() as u8,
        );
        publish_user_state(31, self.layer);
    }

    fn on_battery(&mut self, event: BatteryStatusEvent) {
        if let BatteryStatus::Available {
            level: Some(level), ..
        } = event.0
        {
            self.battery_percent = level;
            self.update_low_battery_request();
            self.refresh();
        }
    }

    fn on_sleep(&mut self, event: SleepStateEvent) {
        self.sleeping = event.0;
        self.refresh();
    }

    #[cfg(not(feature = "split"))]
    async fn run_common(&mut self) -> ! {
        let mut action = ActionEvent::subscriber();
        let mut connection = ConnectionStatusChangeEvent::subscriber();
        let mut layer = LayerChangeEvent::subscriber();
        let mut battery = BatteryStatusEvent::subscriber();
        let mut sleep = SleepStateEvent::subscriber();
        if crate::backlight::brightness_migration_pending() {
            crate::backlight::save_settings().await;
        }
        self.refresh();
        loop {
            let deadline = self.next_deadline();
            let timer = async move {
                match deadline {
                    Some(deadline) => Timer::at(deadline).await,
                    None => pending().await,
                }
            };
            let control =
                rmk::embassy_futures::select::select(action.next_event(), receive_custom_value());
            match select6(
                control,
                connection.next_event(),
                layer.next_event(),
                battery.next_event(),
                sleep.next_event(),
                timer,
            )
            .await
            {
                Either6::First(rmk::embassy_futures::select::Either::First(event)) => {
                    self.on_action(event).await
                }
                Either6::First(rmk::embassy_futures::select::Either::Second(request)) => {
                    self.on_custom_value(request).await
                }
                Either6::Second(event) => self.on_connection(event),
                Either6::Third(event) => self.on_layer(event),
                Either6::Fourth(event) => self.on_battery(event),
                Either6::Fifth(event) => self.on_sleep(event),
                Either6::Sixth(_) => {
                    let now = Instant::now();
                    self.finish_low_battery_transition(now);
                    if self
                        .pattern_deadline
                        .is_some_and(|deadline| deadline <= now)
                    {
                        self.apply_pattern_step();
                    }
                }
            }
        }
    }

    #[cfg(feature = "split")]
    async fn run_split(&mut self) -> ! {
        let mut action = ActionEvent::subscriber();
        let mut central = CentralConnectedEvent::subscriber();
        let mut user_state = UserStateEvent::subscriber();
        let mut connection = ConnectionStatusChangeEvent::subscriber();
        let mut layer = LayerChangeEvent::subscriber();
        let mut battery = BatteryStatusEvent::subscriber();
        let mut sleep = SleepStateEvent::subscriber();
        if self.role == Role::Central {
            self.publish_split_state();
            if crate::backlight::brightness_migration_pending() {
                crate::backlight::save_settings().await;
            }
        }
        self.refresh();
        loop {
            let deadline = self.next_deadline();
            let timer = async move {
                match deadline {
                    Some(deadline) => Timer::at(deadline).await,
                    None => pending().await,
                }
            };
            let application =
                rmk::embassy_futures::select::select(action.next_event(), receive_custom_value());
            let control = select3(application, central.next_event(), user_state.next_event());
            match select6(
                control,
                connection.next_event(),
                layer.next_event(),
                battery.next_event(),
                sleep.next_event(),
                timer,
            )
            .await
            {
                Either6::First(Either3::First(rmk::embassy_futures::select::Either::First(
                    event,
                ))) => self.on_action(event).await,
                Either6::First(Either3::First(rmk::embassy_futures::select::Either::Second(
                    request,
                ))) => self.on_custom_value(request).await,
                Either6::First(Either3::Second(event)) => {
                    if self.role == Role::Peripheral {
                        self.central_connected = event.connected;
                        self.refresh();
                    } else if event.connected {
                        self.publish_split_state();
                    }
                }
                Either6::First(Either3::Third(event)) => {
                    if self.role == Role::Peripheral {
                        if event.id == INDICATOR_TOGGLE_USER_ID {
                            self.connected_indicator_enabled = event.value != 0;
                            self.refresh();
                        } else if event.id == 31 {
                            crate::backlight::on_layer_change(event.value);
                        } else if event.id == crate::battery::LOW_BATTERY_WARNING_USER_ID {
                            let enabled = event.value != 0;
                            if crate::battery::low_battery_warning_enabled() != enabled {
                                crate::battery::set_low_battery_warning_enabled(enabled);
                                let _ = rmk::storage::write_user_setting(
                                    crate::battery::LOW_BATTERY_WARNING_USER_ID,
                                    enabled as u8,
                                )
                                .await;
                            }
                            if event.value == 0 {
                                self.low_battery = false;
                                self.low_battery_transition = None;
                            } else {
                                self.update_low_battery_request();
                            }
                            self.refresh();
                        } else if event.id == crate::battery::BATTERY_TYPE_USER_ID {
                            let battery_type =
                                if event.value == crate::battery::BatteryType::Alkaline as u8 {
                                    crate::battery::BatteryType::Alkaline
                                } else {
                                    crate::battery::BatteryType::Nimh
                                };
                            if crate::battery::battery_type() != battery_type {
                                crate::battery::set_battery_type(battery_type as u8);
                                let _ = rmk::storage::write_user_setting(
                                    crate::battery::BATTERY_TYPE_USER_ID,
                                    battery_type as u8,
                                )
                                .await;
                            }
                        } else {
                            crate::backlight::apply_user_state(event.id, event.value);
                        }
                    }
                }
                Either6::Second(event) => self.on_connection(event),
                Either6::Third(event) => self.on_layer(event),
                Either6::Fourth(event) => self.on_battery(event),
                Either6::Fifth(event) => self.on_sleep(event),
                Either6::Sixth(_) => {
                    let now = Instant::now();
                    self.finish_low_battery_transition(now);
                    if self
                        .pattern_deadline
                        .is_some_and(|deadline| deadline <= now)
                    {
                        self.apply_pattern_step();
                    }
                }
            }
        }
    }
}

impl<G, R> Runnable for StatusIndicator<G, R>
where
    G: OutputPin<Error = Infallible>,
    R: OutputPin<Error = Infallible>,
{
    async fn run(&mut self) -> ! {
        #[cfg(feature = "split")]
        self.run_split().await;
        #[cfg(not(feature = "split"))]
        self.run_common().await
    }
}
