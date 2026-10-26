// The Rust part of a libsystemd.a built with -Dstatic-libsystemd=true.
#![no_std]

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[unsafe(no_mangle)]
pub extern "C" fn sd_demo_id(v: u32) -> u32 {
    v.rotate_left(3)
}
