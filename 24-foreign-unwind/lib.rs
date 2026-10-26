// lib.c in Rust. Guard stands in for an owned type that frees itself in Drop.
#![cfg_attr(not(with_std), no_std)]

use core::ffi::{c_char, c_int};

unsafe extern "C" {
    fn puts(s: *const c_char) -> c_int;
    #[cfg(not(with_std))]
    fn abort() -> !;
}

struct Guard;

impl Drop for Guard {
    fn drop(&mut self) {
        // SAFETY: NUL-terminated literal.
        unsafe { puts(c"lib: drop ran".as_ptr()) };
    }
}

macro_rules! lib_call {
    ($abi:literal) => {
        #[unsafe(no_mangle)]
        pub unsafe extern $abi fn lib_call(cb: unsafe extern $abi fn()) {
            let _guard = Guard;
            // SAFETY: the caller passes a valid callback.
            unsafe { cb() };
            // SAFETY: NUL-terminated literal.
            unsafe { puts(c"lib: callback returned".as_ptr()) };
        }
    };
}

#[cfg(not(c_unwind))]
lib_call!("C");
#[cfg(c_unwind)]
lib_call!("C-unwind");

#[cfg(not(with_std))]
#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    // SAFETY: plain libc call.
    unsafe { abort() }
}

// What src/rust/systemd-shared/panic.rs:61-72 does (see 11-eh-personality).
#[cfg(not(any(with_std, no_personality)))]
#[unsafe(no_mangle)]
extern "C" fn rust_eh_personality() -> ! {
    // SAFETY: plain libc call.
    unsafe { abort() }
}
