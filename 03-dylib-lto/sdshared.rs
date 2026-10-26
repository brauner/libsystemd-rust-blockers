// What Rust programs would link if libsystemd had a Rust API.
#![no_std]

#[link(name = "c")]
unsafe extern "C" {}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}

// The prebuilt core references this, see 11-eh-personality.
#[unsafe(no_mangle)]
extern "C" fn rust_eh_personality() {}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Errno(pub i32);

pub fn first_word(s: &[u8]) -> Result<&[u8], Errno> {
    s.split(|&b| b == b' ').next().filter(|w| !w.is_empty()).ok_or(Errno(22))
}
