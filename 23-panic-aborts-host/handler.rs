// A panic handler that returns, so that the extern "C" function could return -EINVAL.
#![no_std]

#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) {}
