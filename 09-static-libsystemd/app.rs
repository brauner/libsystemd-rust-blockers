// An ordinary Rust program (std) that links libsystemd statically.
unsafe extern "C" {
    fn sd_demo_id(v: u32) -> u32;
}

fn main() {
    println!("{}", unsafe { sd_demo_id(1) });
}
