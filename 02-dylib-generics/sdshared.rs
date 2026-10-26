// A Rust-ABI shared library with a generic API.
#![no_std]

#[link(name = "c")]
unsafe extern "C" {}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    loop {}
}

// The prebuilt core references this, see 11-eh-personality.
#[unsafe(no_mangle)]
extern "C" fn rust_eh_personality() {}

/// Sort and deduplicate in place, return the number of unique elements.
pub fn sort_unique<T: Ord + Copy>(v: &mut [T]) -> usize {
    v.sort_unstable();
    let mut n = 0;
    for i in 0..v.len() {
        if n == 0 || v[i] != v[n - 1] {
            v[n] = v[i];
            n += 1;
        }
    }
    n
}

/// The library itself uses the u32 instantiation.
pub fn unique_u32(v: &mut [u32]) -> usize {
    sort_unique(v)
}
