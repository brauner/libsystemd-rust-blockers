// A second, unrelated Rust-ABI library, e.g. from another project.
#![no_std]

#[link(name = "c")]
unsafe extern "C" {}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}

pub fn last_word(s: &[u8]) -> Option<&[u8]> {
    s.rsplit(|&b| b == b' ').next().filter(|w| !w.is_empty())
}
