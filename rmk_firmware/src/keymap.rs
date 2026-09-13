#[cfg(feature = "keymap-personal")]
compile_error!("The personal keymap is available only for x15 and split builds");

#[path = "keymaps/distribution/single.rs"]
mod selected;

pub use selected::*;
