// tls.rs with the variable and its access in assembly, x86_64 initial-exec only.
#![no_std]

use core::arch::{asm, global_asm};
use core::ffi::c_void;

global_asm!(
    ".section .tbss,\"awT\",@nobits",
    ".balign 8",
    "default_event:",
    ".zero 8",
    ".text",
);

fn default_event() -> *mut *mut c_void {
    let p: *mut *mut c_void;
    // Offset of the variable in the static TLS block, plus the thread pointer.
    unsafe {
        asm!(
            "mov {p}, qword ptr [rip + default_event@GOTTPOFF]",
            "add {p}, qword ptr fs:0",
            p = out(reg) p,
            options(nostack, readonly, preserves_flags),
        )
    };
    p
}

#[no_mangle]
pub extern "C" fn rust_default_event_set(e: *mut c_void) {
    unsafe { *default_event() = e };
}

#[no_mangle]
pub extern "C" fn rust_default_event_get() -> *mut c_void {
    unsafe { *default_event() }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    loop {}
}
