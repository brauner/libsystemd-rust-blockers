// Functions like sd_bus_message_append(), sd_journal_printv() and sd_journal_print().
#![no_std]

use core::ffi::{c_char, c_double, c_int, VaList};

extern "C" {
    fn snprintf(buf: *mut c_char, n: usize, fmt: *const c_char, ...) -> c_int;
    fn vsnprintf(buf: *mut c_char, n: usize, fmt: *const c_char, ap: VaList<'_>) -> c_int;
}

// Like sd_bus_message_append(), one argument per type character.
#[no_mangle]
pub unsafe extern "C" fn rust_append(buf: *mut c_char, size: usize, types: *const c_char, mut ap: ...) -> c_int {
    let mut off = 0;
    let mut t = types;
    while unsafe { *t } != 0 {
        let (p, n) = unsafe { (buf.add(off), size - off) };
        let sep = if off == 0 { c"".as_ptr() } else { c" ".as_ptr() };
        let r = match unsafe { *t } as u8 {
            // 'y' is a uint8_t, which the caller promotes to int. 'b' is an int in sd-bus.
            b'y' | b'b' | b'i' => unsafe { snprintf(p, n, c"%s%d".as_ptr(), sep, ap.next_arg::<c_int>()) },
            b't' => unsafe { snprintf(p, n, c"%s%llu".as_ptr(), sep, ap.next_arg::<u64>()) },
            b'd' => unsafe { snprintf(p, n, c"%s%g".as_ptr(), sep, ap.next_arg::<c_double>()) },
            b's' => unsafe { snprintf(p, n, c"%s%s".as_ptr(), sep, ap.next_arg::<*const c_char>()) },
            _ => return -22,
        };
        if r < 0 || r as usize >= n {
            return -105;
        }
        off += r as usize;
        t = unsafe { t.add(1) };
    }
    off as c_int
}

// The first vsnprintf() gets a copy, like va_copy() in journal-send.c:173.
#[no_mangle]
pub unsafe extern "C" fn rust_printv(a: *mut c_char, b: *mut c_char, size: usize, fmt: *const c_char, ap: VaList<'_>) -> c_int {
    unsafe {
        vsnprintf(a, size, fmt, ap.clone());
        vsnprintf(b, size, fmt, ap)
    }
}

#[no_mangle]
pub unsafe extern "C" fn rust_print(buf: *mut c_char, size: usize, fmt: *const c_char, ap: ...) -> c_int {
    unsafe { vsnprintf(buf, size, fmt, ap) }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    loop {}
}
