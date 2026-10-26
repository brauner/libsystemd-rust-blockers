# 27. Journal files change under the reader, which a Rust `&T` must not see

sd-journal maps journal files `MAP_SHARED` while journald appends
entries and updates header fields and objects in place. In Rust the
bytes behind a shared reference (`&T`, T without `UnsafeCell`) are
immutable, and rustc passes that on to LLVM as `noalias readonly` on
the argument. A function that reads `h.n_entries` through `&Header`,
calls an opaque function, and reads it again gets the old value twice
on rustc 1.99.1 `-O`. The second load is gone. The same function in C
reloads the field after the call, and so does Rust through a raw
pointer or `read_volatile()`.

This isn't impossible to do in Rust. But all of sd-journal's file
access would have to use raw pointers, and safe Rust gives no benefit
for that code.

## Why it matters

src/libsystemd/sd-journal/mmap-cache.c:323 maps journal files
`MAP_SHARED`. The writers are all in-place stores into that mapping,
in src/libsystemd/sd-journal/journal-file.c at main e9795a90b7 unless
noted:

- `state`: 281 (`STATE_ONLINE`, `journal_file_set_online()`) and
  src/shared/journal-file-util.c:198 (`STATE_ARCHIVED` or
  `STATE_OFFLINE`)
- `tail_object_offset` and `n_objects`: 1382-1383
  (`journal_file_append_object()`)
- `n_entries`: 2364, 2411 and 2450 (`*idx = htole64(hidx + 1)`), with
  `idx` pointing at `f->header->n_entries` (2496,
  `journal_file_link_entry()`)
- `tail_entry_realtime`, `tail_entry_monotonic`, `tail_entry_offset`:
  2508-2511
- `tail_entry_seqnum`: 1337, `arena_size`: 874
- objects too: entry array items (2321, 2363, 2393) and a data object's
  `entry_offset`, `entry_array_offset` and `n_entries` (2465-2471)

The readers re-read these fields to notice that the file grew.
`journal_file_read_tail_timestamp()`
(src/libsystemd/sd-journal/sd-journal.c:2695-2710) reads `state` and
then `tail_entry_offset` or `tail_object_offset` and compares it to the
offset seen last time. `journal_file_next_entry()` reads `n_entries` at
journal-file.c:3804 and again at 3819.

The C code already guards such reads. journal-file.c has 27
`READ_NOW()` reads, a `memcpy()` into a local followed by
`asm volatile("" : : : "memory")` (src/basic/macro.h:160-171), "to make
sure the compiler won't optimize away the destination variable".

Which structs are packed (src/libsystemd/sd-journal/journal-def.h):

- Not packed: `struct Header` (262-265), `DataObject`, `FieldObject`
  and `EntryObject`. Each has a `_packed_` twin only to assert that the
  natural layout has no padding.
- `_packed_`: `ObjectHeader` (71-78), `HashItem`, `HashTableObject`,
  `EntryArrayObject`, `TagObject` (139-165) and `FSSHeader` (270-282).
  `union Object` embeds `ObjectHeader` in every object.

## Reproducer

    ./27-shared-mmap-aliasing/run.sh

header.h and reader.rs declare the first fields of `struct Header`, so
that `n_entries` sits at offset 152 (0x98) as in a journal file. main.c
maps one memfd twice with `MAP_SHARED`, read-only for the reader and
writable for "journald". `wait_for_journald()` increments `n_entries`
through the writable mapping, standing in for journald appending an
entry while the reader is busy. reader.c and reader.rs read
`n_entries`, call `wait_for_journald()`, and read it again. C does that
through `const struct header *`, Rust through `&Header`,
`*const Header` and `read_volatile()`:

    $ ./journal | tee out
    C, const struct header *:  n_entries before 0, after 1
    Rust, &Header:             n_entries before 0, after 0
    Rust, *const Header:       n_entries before 0, after 1
    Rust, read_volatile():     n_entries before 0, after 1

In the LLVM IR the raw pointer version loads `n_entries` again after
the call. The `&Header` version doesn't:

    $ rustc +1.99.1 ... 27-shared-mmap-aliasing/reader.rs --emit=llvm-ir -o - | grep ...
    define { i64, i64 } @reads_ptr(ptr nofree noundef readonly captures(none) %h) unnamed_addr #1 !guid !5 {
      %before = load i64, ptr %0, align 8, !noundef !6
      tail call void @wait_for_journald() #2
      %_4 = load i64, ptr %0, align 8, !noundef !6
    define { i64, i64 } @reads_ref(ptr noalias nofree noundef readonly align 8 captures(none) dereferenceable(160) %h) unnamed_addr #1 !guid !7 {
      %before = load i64, ptr %0, align 8, !noundef !6
      tail call void @wait_for_journald() #2
    [...]

In the machine code `reads_ref` loads `n_entries` once, before the
call. `reads_c`, the C version, loads it again after the call:

    $ objdump -d --no-show-raw-insn -M intel --disassemble=reads_ref libreader.a | grep -A7 '<reads_ref>:'
    0000000000000000 <reads_ref>:
       0:	push   rbx
       1:	mov    rbx,QWORD PTR [rdi+0x98]
       8:	call   QWORD PTR [rip+0x0]        # e <reads_ref+0xe>
       e:	mov    rax,rbx
      11:	mov    rdx,rbx
      14:	pop    rbx
      15:	ret
    [...]
    $ objdump -d --no-show-raw-insn -M intel --disassemble=reads_c reader.o | grep -A12 '<reads_c>:'
    0000000000000000 <reads_c>:
    [...]
       9:	mov    rbx,QWORD PTR [rdi+0x98]
      10:	call   15 <reads_c+0x15>
      15:	mov    rdx,QWORD PTR [rbp+0x98]
    [...]

packed.rs translates the packed `ObjectHeader` to `#[repr(C, packed)]`
and takes a reference to a field. C takes the address of such fields
freely, e.g. `READ_NOW(o->object.size)` (journal-file.c:970) hands it
to `memcpy()`. In Rust that's E0793. Copying the field out, or reading
it through a raw pointer with `read_unaligned()`, builds (`--cfg ok`).
An atomic field doesn't help (`--cfg atomic`):

    $ rustc +1.99.1 ... 27-shared-mmap-aliasing/packed.rs -o x.rlib
    error[E0793]: reference to field of packed struct is unaligned
      --> 27-shared-mmap-aliasing/packed.rs:18:5
       |
    18 |     &o.size
    [...]
       = help: copy the field contents to a local variable, or replace the reference with a raw pointer and use `read_unaligned`/`write_unaligned` (loads and stores via `*p` must be properly aligned even when using raw pointers)
    [...]
    $ rustc +1.99.1 ... 27-shared-mmap-aliasing/packed.rs -o x.rlib --cfg ok
    [exit status 0]

    $ rustc +1.99.1 ... 27-shared-mmap-aliasing/packed.rs -o x.rlib --cfg atomic
    error[E0793]: reference to field of packed struct is unaligned
      --> 27-shared-mmap-aliasing/packed.rs:38:5
       |
    38 |     o.size.load(core::sync::atomic::Ordering::Relaxed)

## Upstream

This is how the language is designed, not a missing feature.

- The Rust reference (rust-lang/reference 2dafab96d919, pinned by
  846e51f66b1), behavior-considered-undefined.md,
  `r[undefined.immutable]`: "Mutating immutable bytes" is undefined
  behavior, and "the bytes pointed to by a shared reference, including
  transitively through other references (both shared and mutable) and
  `Box`es, are immutable". interior-mutability.md,
  `r[interior-mut.unsafe-cell]`: "`std::cell::UnsafeCell<T>` type is
  the only allowed way to disable this requirement."
- compiler/rustc_ty_utils/src/abi.rs:355-370 and 406-408: "`&T` where
  `T` contains no `UnsafeCell<U>` is immutable, and can be marked as
  both `readonly` and `noalias`". That is what lets LLVM drop the
  second load.
- library/core/src/ptr/mod.rs:2058-2084 documents `read_volatile()` for
  I/O memory. For memory inside an allocation, "just like in C, whether
  an operation is volatile has no bearing whatsoever on questions
  involving concurrent accesses from multiple threads". The accesses
  that the documentation backs for a field another party writes
  concurrently are atomics, e.g. `AtomicU64::from_ptr()` (stable since
  1.75).
- E0793 has been a hard error since Rust 1.69 (dfc4a7b2d02 "make
  unaligned_reference a hard error") for any reference to a field of a
  `#[repr(packed)]` struct, including the `&self` of an atomic load.

## Workarounds

Use raw pointers into the mapping, with `read_volatile()` where C has
`READ_NOW()`, or atomic loads through `AtomicU64::from_ptr()`. The
compiler checks none of it, and it has to cover all of sd-journal's
file access, since any `&Header` or `&Object` into the mapping brings
the problem back.

Copy the header out through a raw pointer before using it, and copy it
again where the C code re-reads. That costs a copy per access and still
needs raw pointers for the objects.

The packed types don't have to stay packed in Rust.
`journal_file_move_to_object()` rejects offsets that aren't 8-byte
aligned (journal-file.c:1197), and the layouts have no padding. So
`#[repr(C)]` with size and offset assertions works like `struct Header`
does in C. A 1:1 `#[repr(C, packed)]` translation hits E0793 on every
reference to a field.
