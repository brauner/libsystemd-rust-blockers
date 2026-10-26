// A no_std helper in a C library, sums a buffer from the C side.
#![no_std]

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[cfg(stub)]
#[unsafe(no_mangle)]
extern "C" fn rust_eh_personality() {}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rs_sum(p: *const u8, n: usize) -> u64 {
    let s = unsafe { core::slice::from_raw_parts(p, n) };
    s.iter().map(|&b| b as u64).sum()
}
