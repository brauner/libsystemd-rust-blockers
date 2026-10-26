// reader.c in Rust, through a reference, a raw pointer and volatile reads.
#![no_std]

// The first fields of struct Header, src/libsystemd/sd-journal/journal-def.h.
#[repr(C)]
pub struct Header {
    pub signature: [u8; 8],
    pub compatible_flags: u32,
    pub incompatible_flags: u32,
    pub state: u8,
    pub reserved: [u8; 7],
    pub ids: [[u8; 16]; 4],
    pub header_size: u64,
    pub arena_size: u64,
    pub hash_tables: [u64; 4],
    pub tail_object_offset: u64,
    pub n_objects: u64,
    pub n_entries: u64,
}

#[repr(C)]
pub struct Reads {
    before: u64,
    after: u64,
}

unsafe extern "C" {
    fn wait_for_journald();
}

#[unsafe(no_mangle)]
pub extern "C" fn reads_ref(h: &Header) -> Reads {
    let before = h.n_entries;
    // SAFETY: no arguments, no preconditions.
    unsafe { wait_for_journald() };
    Reads { before, after: h.n_entries }
}

/// # Safety
/// `h` must point to a mapped Header.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn reads_ptr(h: *const Header) -> Reads {
    // SAFETY: the caller passes a mapped Header.
    let before = unsafe { (*h).n_entries };
    // SAFETY: no arguments, no preconditions.
    unsafe { wait_for_journald() };
    // SAFETY: as above.
    Reads { before, after: unsafe { (*h).n_entries } }
}

/// # Safety
/// `h` must point to a mapped Header.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn reads_volatile(h: *const Header) -> Reads {
    // SAFETY: the caller passes a mapped Header.
    let p = unsafe { &raw const (*h).n_entries };
    // SAFETY: as above.
    let before = unsafe { p.read_volatile() };
    // SAFETY: no arguments, no preconditions.
    unsafe { wait_for_journald() };
    // SAFETY: as above.
    Reads { before, after: unsafe { p.read_volatile() } }
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    loop {}
}
