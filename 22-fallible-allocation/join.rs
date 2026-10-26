// A libsystemd-style function with alloc, returns a length or a negative errno.
#![no_std]

extern crate alloc;

use alloc::alloc::{GlobalAlloc, Layout};
use alloc::format;
use alloc::string::String;
use alloc::vec::Vec;
use core::ffi::{c_char, c_int, c_void, CStr};
use core::fmt::Write;
use core::{mem, ptr};

const EINVAL: c_int = 22;
const ENOMEM: c_int = 12;

extern "C" {
    fn malloc(size: usize) -> *mut c_void;
    fn free(p: *mut c_void);
    fn abort() -> !;
    fn write(fd: c_int, buf: *const c_void, n: usize) -> isize;
}

// What libsystemd's C code allocates with.
struct Malloc;

unsafe impl GlobalAlloc for Malloc {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        // What malloc() guarantees at least.
        if layout.align() > 2 * mem::size_of::<usize>() {
            return ptr::null_mut();
        }
        unsafe { malloc(layout.size()).cast() }
    }

    unsafe fn dealloc(&self, p: *mut u8, _: Layout) {
        unsafe { free(p.cast()) }
    }
}

#[global_allocator]
static GLOBAL: Malloc = Malloc;

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
    let _ = writeln!(Stderr, "rust: {}", info.message());
    unsafe { abort() }
}

// The prebuilt core and alloc reference this, see 11-eh-personality.
#[no_mangle]
extern "C" fn rust_eh_personality() {
    unsafe { abort() }
}

// "word0 word1 ... word<n-1>", the way Rust is usually written.
#[no_mangle]
pub unsafe extern "C" fn rust_join(word: *const c_char, n: usize) -> c_int {
    let Ok(word) = unsafe { CStr::from_ptr(word) }.to_str() else {
        return -EINVAL;
    };
    let words: Vec<String> = (0..n).map(|i| format!("{word}{i}")).collect();
    words.join(" ").len() as c_int
}

// The same with try_reserve() before every write, the stable fallible API.
#[no_mangle]
pub unsafe extern "C" fn rust_join_try_reserve(word: *const c_char, n: usize) -> c_int {
    let Ok(word) = unsafe { CStr::from_ptr(word) }.to_str() else {
        return -EINVAL;
    };
    let mut s = String::new();
    for i in 0..n {
        // A separator, the word and up to 20 digits.
        if s.try_reserve(1 + word.len() + 20).is_err() {
            return -ENOMEM;
        }
        if i > 0 {
            s.push(' ');
        }
        let _ = write!(s, "{word}{i}");
    }
    s.len() as c_int
}
