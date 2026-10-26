// Two exports, versioned the way src/libsystemd/libsystemd.sym does it.
#![no_std]

#[link(name = "c")]
unsafe extern "C" {}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[unsafe(no_mangle)]
pub extern "C" fn sd_demo_open() -> i32 {
    1
}

#[unsafe(no_mangle)]
pub extern "C" fn sd_demo_close() -> i32 {
    2
}
