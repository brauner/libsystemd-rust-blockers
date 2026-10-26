#[unsafe(no_mangle)]
pub extern "C" fn rs_sum(n: u64) -> u64 {
    (0..n).collect::<Vec<u64>>().iter().sum()
}
