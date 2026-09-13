use rmk::types::action::KeyAction;
use rmk::{a, k, kbctrl, layer, lt};

pub(crate) const ROW: usize = 3;
pub(crate) const COL: usize = 32;
pub(crate) const NUM_LAYER: usize = 2;

#[rustfmt::skip]
pub const fn get_default_keymap() -> [[[KeyAction; COL]; ROW]; NUM_LAYER] {
    [
        layer!([
            [lt!(1, A), k!(B), k!(C), k!(D), k!(E), k!(F), k!(G), a!(No), k!(E), k!(F), k!(G), k!(H), k!(I), k!(J), k!(K), a!(No),
             k!(H), k!(I), k!(J), k!(K), k!(L), k!(M), k!(N), k!(O), k!(L), k!(M), k!(N), k!(O), k!(P), k!(Q), k!(R), k!(S)],
            [k!(P), k!(Q), k!(R), k!(S), k!(T), k!(U), k!(V), a!(No), k!(T), k!(U), k!(V), k!(W), k!(X), k!(Y), k!(Z), a!(No),
             k!(W), k!(X), k!(Y), k!(Z), k!(A), k!(B), k!(C), k!(D), k!(A), k!(B), k!(C), k!(D), k!(E), k!(F), k!(G), k!(H)],
            [k!(J), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No),
             a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), k!(I), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No)]
        ]),
        layer!([
            [a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(No), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(No),
             a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent)],
            [a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(No), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(No),
             a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent), a!(Transparent)],
            [a!(Transparent), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No),
             a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), kbctrl!(Bootloader), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No), a!(No)]
        ]),
    ]
}
