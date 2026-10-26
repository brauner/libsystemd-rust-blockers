#![no_std]
#![no_main]

use core::hint::black_box;

#[link(name = "c")]
unsafe extern "C" {}

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct Uid(u32);

#[unsafe(no_mangle)]
pub extern "C" fn main() -> i32 {
    // black_box() hides the length too, so the full sort gets instantiated.
    let mut a = [3u32, 1, 3, 2, 1];
    let mut b = a.map(Uid);
    let (a, b): (&mut [u32], &mut [Uid]) = black_box((&mut a, &mut b));
    #[cfg(plain)]
    let n = sdshared::unique_u32(a);
    #[cfg(generic)]
    let n = sdshared::sort_unique(a);
    #[cfg(own_type)]
    let n = sdshared::sort_unique(b);
    n as i32
}
