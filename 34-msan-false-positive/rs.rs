#![no_std]

use core::fmt::Write;

#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    loop {}
}

// The prebuilt core refers to it, see 11-eh-personality.
#[unsafe(no_mangle)]
extern "C" fn rust_eh_personality() {}

// The crate writes the 16 hex digits itself, one store each.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rs_hex64(x: u64, buf: *mut u8) {
    let buf = unsafe { core::slice::from_raw_parts_mut(buf, 16) };
    for (i, b) in buf.iter_mut().enumerate() {
        *b = b"0123456789abcdef"[(x >> (60 - 4 * i)) as usize & 0xf];
    }
}

struct Buf<'a>(&'a mut [u8], usize);

impl Write for Buf<'_> {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        let end = self.1 + s.len();
        self.0.get_mut(self.1..end).ok_or(core::fmt::Error)?.copy_from_slice(s.as_bytes());
        self.1 = end;
        Ok(())
    }
}

// core::fmt writes the decimal digits.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rs_fmt_u64(x: u64, buf: *mut u8, n: usize) -> bool {
    let mut w = Buf(unsafe { core::slice::from_raw_parts_mut(buf, n) }, 0);
    write!(w, "{x}\0").is_ok()
}
