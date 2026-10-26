// One more entry for main.c's section, from Rust.
#![no_std]

use core::ffi::c_char;

#[repr(C)]
pub struct Entry {
    pub name: *const c_char,
}

// SAFETY: the entry is never written to.
unsafe impl Sync for Entry {}

#[used]
#[unsafe(link_section = "my_set")]
static RUST_ENTRY: Entry = Entry { name: c"rust".as_ptr() };

#[unsafe(no_mangle)]
pub extern "C" fn rust_init() {}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    loop {}
}
