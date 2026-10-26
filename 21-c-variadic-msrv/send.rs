// The loop of sd_journal_send() in Rust, stepping over a long double three ways.
#![no_std]

use core::ffi::{c_char, c_int, VaList};

extern "C" {
    fn vsnprintf(buf: *mut c_char, n: usize, fmt: *const c_char, ap: VaList<'_>) -> c_int;
    fn skip_long_double(ap: *mut VaList<'_>); // in send.c
}

// Wrong on purpose, no VaArgSafe type is a long double.
unsafe fn skip_as_f64(ap: &mut VaList<'_>) {
    unsafe { ap.next_arg::<f64>() };
}

// Also wrong, 16 bytes like a long double on x86_64.
unsafe fn skip_as_u64x2(ap: &mut VaList<'_>) {
    unsafe { (ap.next_arg::<u64>(), ap.next_arg::<u64>()) };
}

unsafe fn skip_in_c(ap: &mut VaList<'_>) {
    unsafe { skip_long_double(ap) };
}

unsafe fn send(buf: *mut c_char, size: usize, mut format: *const c_char, mut ap: VaList<'_>, skip: unsafe fn(&mut VaList<'_>)) -> c_int {
    let mut off = 0;
    while !format.is_null() {
        if off > 0 {
            unsafe { *buf.add(off - 1) = b' ' as c_char };
        }
        let r = unsafe { vsnprintf(buf.add(off), size - off, format, ap.clone()) };
        if r < 0 || r as usize >= size - off {
            return -105;
        }
        off += r as usize + 1;
        unsafe { skip(&mut ap) };
        format = unsafe { ap.next_arg::<*const c_char>() };
    }
    off as c_int - 1
}

#[no_mangle]
pub unsafe extern "C" fn rust_send_f64(buf: *mut c_char, size: usize, format: *const c_char, ap: ...) -> c_int {
    unsafe { send(buf, size, format, ap, skip_as_f64) }
}

#[no_mangle]
pub unsafe extern "C" fn rust_send_u64x2(buf: *mut c_char, size: usize, format: *const c_char, ap: ...) -> c_int {
    unsafe { send(buf, size, format, ap, skip_as_u64x2) }
}

#[no_mangle]
pub unsafe extern "C" fn rust_send_c_helper(buf: *mut c_char, size: usize, format: *const c_char, ap: ...) -> c_int {
    unsafe { send(buf, size, format, ap, skip_in_c) }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    loop {}
}
