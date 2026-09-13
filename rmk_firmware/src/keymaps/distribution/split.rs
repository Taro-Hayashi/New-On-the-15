use rmk::types::action::KeyAction;
use rmk::{a, k, kbctrl, layer, lt, user};

pub(crate) const ROW: usize = 6;
pub(crate) const COL: usize = 16;
pub(crate) const NUM_LAYER: usize = 5;
pub(crate) const HALF_ROW: usize = 3;
pub(crate) const PERIPHERAL_ROW_OFFSET: usize = 3;
pub(crate) const PERIPHERAL_COL_OFFSET: usize = 0;

#[rustfmt::skip]
pub const fn get_default_keymap() -> [[[KeyAction; COL]; ROW]; NUM_LAYER] {
    [
        layer!([
            [lt!(1, Escape), k!(Kc1), k!(Kc2), k!(Kc3), k!(Kc4), k!(Kc5), k!(Minus), k!(Equal), k!(LCtrl), k!(A), k!(S), k!(D), k!(F), k!(G), k!(Language2), k!(Language1)],
            [k!(Tab), k!(Q), k!(W), k!(E), k!(R), k!(T), k!(LGui), k!(LAlt), k!(LShift), k!(Z), k!(X), k!(C), k!(V), k!(B), lt!(2, Space), lt!(2, Space)],
            [user!(0), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), user!(1), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No)],
            [lt!(1, Grave), k!(Kc6), k!(Kc7), k!(Kc8), k!(Kc9), k!(Kc0), k!(Grave), k!(Backspace), k!(Language1), k!(H), k!(J), k!(K), k!(L), k!(Semicolon), k!(Quote), k!(Enter)],
            [k!(LAlt), k!(Y), k!(U), k!(I), k!(O), k!(P), k!(LeftBracket), k!(RightBracket), lt!(2, Space), k!(N), k!(M), k!(Comma), k!(Dot), k!(Slash), k!(Backslash), k!(RShift)],
            [user!(0), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), user!(1), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No)]
        ]),
        layer!([
            [a!(Transparent), user!(0), user!(1), user!(2), user!(3), user!(4), a!(Transparent), a!(Transparent), user!(13), user!(15), user!(17), user!(19), user!(21), user!(23), user!(8), a!(Transparent)],
            [user!(12), user!(14), user!(16), user!(18), user!(20), user!(22), a!(Transparent), a!(Transparent), user!(11), user!(24), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent)],
            [user!(7), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), kbctrl!(Bootloader), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No)],
            [a!(Transparent), user!(0), user!(1), user!(2), user!(3), user!(4), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), user!(8), user!(8)],
            [a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), user!(11), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent)],
            [user!(7), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), user!(10), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No)]
        ]),
        layer!([
            [a!(Transparent), k!(F1), k!(F2), k!(F3), k!(F4), k!(F5), k!(F11), k!(F12), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent)],
            [a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent)],
            [a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent)],
            [a!(Transparent), k!(F6), k!(F7), k!(F8), k!(F9), k!(F10), a!(Transparent), k!(Delete), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), k!(Up), a!(Transparent)],
            [a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), k!(Left), k!(Down), k!(Right)],
            [a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent)]
        ]),
        [[a!(Transparent); COL]; ROW],
        [[a!(Transparent); COL]; ROW],
    ]
}
