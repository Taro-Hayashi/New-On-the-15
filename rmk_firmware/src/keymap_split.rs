#[cfg(all(feature = "keymap-distribution", feature = "keymap-personal"))]
compile_error!("Select exactly one keymap profile");

#[cfg(feature = "keymap-distribution")]
#[path = "keymaps/distribution/split.rs"]
mod selected;

#[cfg(feature = "keymap-personal")]
#[path = "keymaps/personal/split.rs"]
mod selected;

pub use selected::*;
