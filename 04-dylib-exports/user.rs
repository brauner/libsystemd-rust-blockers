#![no_std]
#![no_main]

#[link(name = "c")]
unsafe extern "C" {}

#[unsafe(no_mangle)]
pub extern "C" fn main() -> i32 {
    let a = sdshared::first_word(b"hello world").map_or(0, |w| w.len());
    let b = other::last_word(b"hello world").map_or(0, |w| w.len());
    (a * 10 + b) as i32
}
