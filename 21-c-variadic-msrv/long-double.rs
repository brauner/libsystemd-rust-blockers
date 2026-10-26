// What sd_journal_send() does for a "%Lf" (src/basic/stdio-util.h:66).
#![no_std]

use core::ffi::VaList;

pub unsafe fn skip_long_double(ap: &mut VaList<'_>) {
    let _ = unsafe { ap.next_arg::<f128>() };
}
