// The fallible counterparts of Box::new() and Vec::push().
#![no_std]

extern crate alloc;

use alloc::boxed::Box;
use alloc::vec::Vec;

pub fn fallible(v: &mut Vec<u64>) {
    let _ = Box::try_new(1u64);
    let _ = v.push_within_capacity(1);
    let _ = v.try_push(1);
    let _ = v.try_reserve(1); // stable since 1.57
}
