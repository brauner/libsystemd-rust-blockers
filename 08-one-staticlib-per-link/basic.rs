// Rust code for one static library (think libbasic).
#![no_std]

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[unsafe(no_mangle)]
pub extern "C" fn rs_basic(v: u32) -> u32 {
    v.rotate_left(3)
}
