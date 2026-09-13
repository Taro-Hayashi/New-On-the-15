use rmk::types::action::KeyAction;
use rmk::{a, k, kbctrl, layer, lt, user};

pub(crate) const ROW: usize = 3;
pub(crate) const COL: usize = 16;
pub(crate) const NUM_LAYER: usize = 5;

#[rustfmt::skip]
pub const fn get_default_keymap() -> [[[KeyAction; COL]; ROW]; NUM_LAYER] {
    [
        layer!([
            [lt!(1, Escape), k!(Kc1), k!(Kc2), k!(Kc3), k!(Kc4), k!(Kc5), k!(Minus), k!(Equal), k!(LCtrl), k!(A), k!(S), k!(D), k!(F), k!(G), k!(Language2), k!(Language1)],
            [k!(Tab), k!(Q), k!(W), k!(E), k!(R), k!(T), k!(LGui), k!(LAlt), k!(LShift), k!(Z), k!(X), k!(C), k!(V), k!(B), lt!(2, Space), lt!(2, Space)],
            [user!(0), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), user!(1), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No)]
        ]),
        layer!([
            [a!(Transparent), user!(0), user!(1), user!(2), user!(3), user!(4), a!(Transparent), a!(Transparent), user!(13), user!(15), user!(17), user!(19), user!(21), user!(23), user!(8), user!(8)],
            [user!(12), user!(14), user!(16), user!(18), user!(20), user!(22), a!(Transparent), a!(Transparent), user!(11), user!(24), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent)],
            [user!(7), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), kbctrl!(Bootloader), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No)]
        ]),
        layer!([
            [a!(Transparent), k!(F1), k!(F2), k!(F3), k!(F4), k!(F5), k!(F11), k!(F12), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent)],
            [a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent)],
            [a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent)]
        ]),
        [[a!(Transparent); COL]; ROW],
        [[a!(Transparent); COL]; ROW],
    ]
}
