use rmk::types::action::KeyAction;
use rmk::{a, k, kbctrl, layer, lt};

pub(crate) const ROW: usize = 3;
pub(crate) const COL: usize = 16;
pub(crate) const NUM_LAYER: usize = 2;

#[rustfmt::skip]
pub const fn get_default_keymap() -> [[[KeyAction; COL]; ROW]; NUM_LAYER] {
    [
        layer!([
            [lt!(1, A), k!(B), k!(C), k!(D), k!(E), k!(F), k!(G), k!(H), k!(I), k!(J), k!(K), k!(L), k!(M), k!(N), k!(O), k!(P)],
            [k!(Q), k!(R), k!(S), k!(T), k!(U), k!(V), k!(W), k!(X), k!(Y), k!(Z), k!(A), k!(B), k!(C), k!(D), k!(E), k!(F)],
            [k!(G), k!(H), k!(I), k!(J), k!(K), k!(L), k!(M), k!(N), k!(O), k!(P), k!(Q), k!(R), k!(S), k!(T), k!(U), k!(V)]
        ]),
        layer!([
            [a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent)],
            [a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent)],
            [a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), kbctrl!(Bootloader), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent)]
        ]),
    ]
}
