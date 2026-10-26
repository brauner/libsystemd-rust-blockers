// tls.rs with the variable in shim.c.
#![no_std]

use core::ffi::c_void;

extern "C" {
    fn default_event_get() -> *mut c_void;
    fn default_event_set(e: *mut c_void);
}

#[no_mangle]
pub extern "C" fn rust_default_event_set(e: *mut c_void) {
    unsafe { default_event_set(e) };
}

#[no_mangle]
pub extern "C" fn rust_default_event_get() -> *mut c_void {
    unsafe { default_event_get() }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    loop {}
}
