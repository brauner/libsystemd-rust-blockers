// Rust code for one static library (think libsystemd_static).
#![no_std]

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[unsafe(no_mangle)]
pub extern "C" fn rs_sd(v: u32) -> u32 {
    v.rotate_left(3)
}
