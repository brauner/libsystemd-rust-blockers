#![no_std]

#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    loop {}
}

// With our -C overflow-checks=yes the overflow path calls into core.
#[unsafe(no_mangle)]
pub extern "C" fn rs_add(a: u32, b: u32) -> u32 {
    a + b
}
