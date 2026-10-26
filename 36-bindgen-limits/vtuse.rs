#![no_std]
#![allow(non_camel_case_types, dead_code)]

include!("vt.rs");

// SD_BUS_VTABLE_END from sd-bus-vtable.h as a Rust constant.
pub const END: sd_bus_vtable = sd_bus_vtable {
    _bitfield_align_1: [],
    _bitfield_1: sd_bus_vtable::new_bitfield_1(b'>', 0),
    x: sd_bus_vtable__bindgen_ty_1 {
        end: sd_bus_vtable__bindgen_ty_1__bindgen_ty_2 { _reserved: 0 },
    },
};
