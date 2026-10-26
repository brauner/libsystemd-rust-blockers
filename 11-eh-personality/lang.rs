// The documented way to provide it (library/core/src/lib.rs).
#![no_std]
#![feature(lang_items)]

#[lang = "eh_personality"]
extern "C" fn eh_personality() {}
