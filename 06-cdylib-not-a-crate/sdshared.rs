// The library from 04, built as a cdylib only.
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

pub fn first_word(s: &[u8]) -> Option<&[u8]> {
    s.split(|&b| b == b' ').next().filter(|w| !w.is_empty())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn sd_first_word_len(p: *const u8, n: usize) -> isize {
    let s = unsafe { core::slice::from_raw_parts(p, n) };
    first_word(s).map_or(-22, |w| w.len() as isize)
}
