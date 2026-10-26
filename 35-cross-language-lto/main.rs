#![no_std]
#![no_main]

unsafe extern "C" {
    fn c_add1(x: u32) -> u32;
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    loop {}
}

// Like our Rust programs: no_std, no_main and linked by rustc.
#[unsafe(no_mangle)]
extern "C" fn main() -> core::ffi::c_int {
    if unsafe { c_add1(41) } == 42 { 0 } else { 1 }
}
