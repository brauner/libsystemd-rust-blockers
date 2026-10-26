#![no_std]
#![no_main]

#[link(name = "c")]
unsafe extern "C" {}

#[unsafe(no_mangle)]
pub extern "C" fn main() -> i32 {
    match sdshared::first_word(b"hello world") {
        Some(w) => w.len() as i32,
        None => -22,
    }
}
