// The per-thread default event loop of sd-event.c:191 in Rust.
#![no_std]

use core::ffi::c_void;
use core::ptr;

#[thread_local]
static mut DEFAULT_EVENT: *mut c_void = ptr::null_mut();

#[no_mangle]
pub extern "C" fn rust_default_event_set(e: *mut c_void) {
    unsafe { DEFAULT_EVENT = e };
}

#[no_mangle]
pub extern "C" fn rust_default_event_get() -> *mut c_void {
    unsafe { DEFAULT_EVENT }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    loop {}
}
