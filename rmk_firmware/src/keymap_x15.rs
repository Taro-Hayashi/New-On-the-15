#[cfg(all(feature = "keymap-distribution", feature = "keymap-personal"))]
compile_error!("Select exactly one keymap profile");

#[cfg(feature = "keymap-distribution")]
#[path = "keymaps/distribution/x15.rs"]
mod selected;

#[cfg(feature = "keymap-personal")]
#[path = "keymaps/personal/x15.rs"]
mod selected;

pub use selected::*;
