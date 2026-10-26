// Without the crate, Rust programs declare the C ABI by hand or with bindgen.
#![no_std]
#![no_main]

#[link(name = "c")]
unsafe extern "C" {}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}

// The prebuilt core references this, see 11-eh-personality.
#[unsafe(no_mangle)]
extern "C" fn rust_eh_personality() {}

#[link(name = "sdshared")]
unsafe extern "C" {
    fn sd_first_word_len(p: *const u8, n: usize) -> isize;
}

#[unsafe(no_mangle)]
pub extern "C" fn main() -> i32 {
    let s = b"hello world";
    unsafe { sd_first_word_len(s.as_ptr(), s.len()) as i32 }
}
