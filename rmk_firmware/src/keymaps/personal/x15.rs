use rmk::types::action::KeyAction;
use rmk::types::modifier::ModifierCombination;
use rmk::{a, k, kbctrl, layer, lt, mt, user};

pub(crate) const ROW: usize = 3;
pub(crate) const COL: usize = 32;
pub(crate) const NUM_LAYER: usize = 5;

#[rustfmt::skip]
pub const fn get_default_keymap() -> [[[KeyAction; COL]; ROW]; NUM_LAYER] {
    [
        layer!([
            [lt!(1, Escape), k!(Kc1), k!(Kc2), k!(Kc3), k!(Kc4), k!(Kc5), k!(Kc6), a!(No), k!(LGui), k!(A), k!(S), k!(D), k!(F), k!(G), k!(Space), a!(No), k!(Kc7), k!(Kc8), k!(Kc9), k!(Kc0), k!(Minus), k!(Equal), k!(Grave), k!(Backspace), k!(Space), k!(H), k!(J), k!(K), k!(L), k!(Semicolon), k!(Quote), k!(Enter)],
            [k!(Tab), k!(Q), k!(W), k!(E), k!(R), k!(T), k!(LCtrl), a!(No), k!(LShift), k!(Z), k!(X), k!(C), k!(V), k!(B), lt!(2, Language2), a!(No), k!(LAlt), k!(Y), k!(U), k!(I), k!(O), k!(P), k!(LeftBracket), k!(RightBracket), lt!(2, Language1), k!(N), k!(M), k!(Comma), k!(Dot), k!(Slash), k!(Backslash), mt!(F7, ModifierCombination::LSHIFT)],
            [user!(0), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), user!(1), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No)]
        ]),
        layer!([
            [a!(Transparent), user!(0), user!(1), user!(2), user!(3), user!(4), a!(Transparent), a!(No), user!(13), user!(15), user!(17), user!(19), user!(21), user!(23), a!(Transparent), a!(No), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), user!(8)],
            [user!(12), user!(14), user!(16), user!(18), user!(20), user!(22), a!(Transparent), a!(No), user!(11), user!(24), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(No), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), user!(11), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent)],
            [user!(7), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), kbctrl!(Bootloader), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No)]
        ]),
        layer!([
            [a!(Transparent), k!(F1), k!(F2), k!(F3), k!(F4), k!(F5), k!(F6), a!(No), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(No), k!(F7), k!(F8), k!(F9), k!(F10), k!(F11), k!(F12), a!(Transparent), k!(Delete), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), k!(Up), a!(Transparent)],
            [a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(No), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(No), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), k!(Left), k!(Down), k!(Right)],
            [a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent)]
        ]),
        [[a!(Transparent); COL]; ROW],
        [[a!(Transparent); COL]; ROW],
    ]
}
