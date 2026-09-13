use std::fs::File;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::{env, fs};

use const_gen::*;
use xz2::read::XzEncoder;

fn main() {
    generate_vial_config("vial.json", "config_generated.rs");
    generate_vial_config("vial_split.json", "config_split_generated.rs");
    generate_vial_config("vial_x15.json", "config_x15_generated.rs");

    let out = &PathBuf::from(env::var_os("OUT_DIR").unwrap());
    File::create(out.join("memory.x"))
        .unwrap()
        .write_all(include_bytes!("memory.x"))
        .unwrap();

    println!("cargo:rustc-link-search={}", out.display());
    println!("cargo:rerun-if-changed=memory.x");
    println!("cargo:rustc-link-arg=--nmagic");
    println!("cargo:rustc-link-arg=-Tlink.x");
    println!("cargo:rustc-link-arg=-Tdefmt.x");
}

fn generate_vial_config(json_file: &str, out_name: &str) {
    println!("cargo:rerun-if-changed={json_file}");

    let out_file = Path::new(&env::var_os("OUT_DIR").unwrap()).join(out_name);
    let mut content = String::new();
    File::open(json_file)
        .unwrap()
        .read_to_string(&mut content)
        .expect("Cannot read vial.json");

    let vial_cfg = json::stringify(json::parse(&content).unwrap());
    let mut keyboard_def_compressed: Vec<u8> = Vec::new();
    XzEncoder::new(vial_cfg.as_bytes(), 6)
        .read_to_end(&mut keyboard_def_compressed)
        .unwrap();

    let keyboard_id: Vec<u8> = vec![0x4F, 0x54, 0x31, 0x35, 0x56, 0x34, 0x58, 0x37];
    let const_declarations = [
        const_declaration!(pub VIAL_KEYBOARD_DEF = keyboard_def_compressed),
        const_declaration!(pub VIAL_KEYBOARD_ID = keyboard_id),
    ]
    .map(|s| "#[allow(clippy::redundant_static_lifetimes)]\n".to_owned() + s.as_str())
    .join("\n");

    fs::write(out_file, const_declarations).unwrap();
}
