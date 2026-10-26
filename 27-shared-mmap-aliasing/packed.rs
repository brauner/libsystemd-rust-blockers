// struct ObjectHeader, src/libsystemd/sd-journal/journal-def.h:71-78, is _packed_.
#![no_std]

#[repr(C, packed)]
pub struct ObjectHeader {
    pub type_: u8,
    pub flags: u8,
    pub reserved: [u8; 6],
    #[cfg(not(atomic))]
    pub size: u64,
    #[cfg(atomic)]
    pub size: core::sync::atomic::AtomicU64,
}

// C takes the address of such fields freely, e.g. READ_NOW(o->object.size).
#[cfg(not(any(ok, atomic)))]
pub fn size(o: &ObjectHeader) -> &u64 {
    &o.size
}

// Instead, copy the field out or read it through a raw pointer.
#[cfg(ok)]
pub fn size(o: &ObjectHeader) -> u64 {
    o.size
}

/// # Safety
/// `o` must point to a mapped object.
#[cfg(ok)]
pub unsafe fn size_now(o: *const ObjectHeader) -> u64 {
    // SAFETY: the caller passes a mapped object.
    unsafe { (&raw const (*o).size).read_unaligned() }
}

// An atomic load needs a reference to the field as well.
#[cfg(atomic)]
pub fn size(o: &ObjectHeader) -> u64 {
    o.size.load(core::sync::atomic::Ordering::Relaxed)
}
