// hook.c in stable Rust, where the extern declaration is a strong reference.
#![no_std]

use core::ffi::{c_char, c_int};

unsafe extern "C" {
    fn optional_hook() -> bool;
    fn printf(fmt: *const c_char, ...) -> c_int;
}

#[unsafe(no_mangle)]
pub extern "C" fn report() {
    let hook: unsafe extern "C" fn() -> bool = optional_hook;
    if (hook as *const ()).is_null() {
        // SAFETY: NUL-terminated literal.
        unsafe { printf(c"Rust: optional_hook() not linked in\n".as_ptr()) };
    } else {
        // SAFETY: the hook takes no arguments.
        let r = unsafe { hook() };
        // SAFETY: the format matches the argument.
        unsafe { printf(c"Rust: optional_hook() linked in, returns %d\n".as_ptr(), c_int::from(r)) };
    }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    loop {}
}
