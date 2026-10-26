// hook.c with the unstable linkage attribute.
#![no_std]

use core::ffi::{c_char, c_int};

unsafe extern "C" {
    #[linkage = "extern_weak"]
    static optional_hook: Option<unsafe extern "C" fn() -> bool>;
    fn printf(fmt: *const c_char, ...) -> c_int;
}

#[unsafe(no_mangle)]
pub extern "C" fn report() {
    // SAFETY: reads the address of the weak symbol.
    match unsafe { optional_hook } {
        // SAFETY: NUL-terminated literal.
        None => unsafe { printf(c"Rust: optional_hook() not linked in\n".as_ptr()) },
        // SAFETY: the hook takes no arguments, the format matches the argument.
        Some(hook) => unsafe {
            printf(c"Rust: optional_hook() linked in, returns %d\n".as_ptr(), c_int::from(hook()))
        },
    };
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    loop {}
}
