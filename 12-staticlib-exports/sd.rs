// A bit of Rust in libsystemd_static that formats an id into a C buffer.
#![no_std]

use core::fmt::Write;

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}

// The prebuilt core references this, see 11-eh-personality.
#[unsafe(no_mangle)]
extern "C" fn rust_eh_personality() {}

struct Buf<'a>(&'a mut [u8], usize);

impl Write for Buf<'_> {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        let d = self.0.get_mut(self.1..self.1 + s.len()).ok_or(core::fmt::Error)?;
        d.copy_from_slice(s.as_bytes());
        self.1 += s.len();
        Ok(())
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rs_format_id(id: u64, p: *mut u8, n: usize) -> isize {
    let mut b = Buf(unsafe { core::slice::from_raw_parts_mut(p, n) }, 0);
    match write!(b, "{id:016x}") {
        Ok(()) => b.1 as isize,
        Err(_) => -7,
    }
}
