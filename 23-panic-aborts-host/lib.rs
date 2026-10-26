// libsystemd-style entry points, none of which panics explicitly.
#![no_std]

use core::ffi::{c_int, c_void};
use core::fmt::Write;
use core::slice;

extern "C" {
    fn abort() -> !;
    fn write(fd: c_int, buf: *const c_void, n: usize) -> isize;
}

#[no_mangle]
pub unsafe extern "C" fn rust_get_byte(buf: *const u8, n: usize, i: usize) -> c_int {
    let buf = unsafe { slice::from_raw_parts(buf, n) };
    buf[i].into()
}

#[no_mangle]
pub unsafe extern "C" fn rust_set_id(id: *mut u8, src: *const u8, n: usize) -> c_int {
    let (id, src) = unsafe { (slice::from_raw_parts_mut(id, 16), slice::from_raw_parts(src, n)) };
    id.copy_from_slice(src);
    0
}

#[no_mangle]
pub unsafe extern "C" fn rust_find(buf: *const u8, n: usize, c: u8) -> c_int {
    let buf = unsafe { slice::from_raw_parts(buf, n) };
    buf.iter().position(|&b| b == c).unwrap() as c_int
}

// Like usec_add().
#[no_mangle]
pub extern "C" fn rust_usec_add(t: u64, timeout: u64) -> u64 {
    t + timeout
}

struct Stderr;

impl Write for Stderr {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        unsafe { write(2, s.as_ptr().cast(), s.len()) };
        Ok(())
    }
}

// Log and abort, like src/rust/systemd-shared/panic.rs.
#[panic_handler]
fn panic(info: &core::panic::PanicInfo<'_>) -> ! {
    if let Some(l) = info.location() {
        let _ = write!(Stderr, "rust: panicked at {}:{}: ", l.file(), l.line());
    }
    let _ = writeln!(Stderr, "{}", info.message());
    unsafe { abort() }
}

// The prebuilt core references this, see 11-eh-personality.
#[no_mangle]
extern "C" fn rust_eh_personality() {
    unsafe { abort() }
}
