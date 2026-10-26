#![no_std]
#![allow(non_upper_case_globals)]

// What bindgen made of h.h: isempty() is isempty__extern() in wrap.c.
include!("h.rs");

#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    loop {}
}

// The same as c_count_empty() in count.c.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rs_count_empty(v: *const *const core::ffi::c_char, n: usize) -> usize {
    let v = unsafe { core::slice::from_raw_parts(v, n) };
    v.iter().filter(|&&s| unsafe { isempty(s) }).count()
}
