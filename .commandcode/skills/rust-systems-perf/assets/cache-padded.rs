// Cache-line-aware padding without a dependency.
//
// Why 128 and not 64:
//  - x86-64 and aarch64 prefetchers pull pairs of 64-byte lines, so two values
//    64 bytes apart can still conflict.
//  - Apple Silicon reports a 128-byte line.
//  - crossbeam's CachePadded uses 128 on x86-64/aarch64/powerpc64 for this reason.
//
// Prefer crossbeam_utils::CachePadded when you already depend on it; it handles
// per-architecture widths and guarantees the inner value shares its address.

/// Padding width for independently written shared values.
/// Override per target when you know better than the default guess.
#[cfg(target_arch = "s390x")]
pub const CACHE_LINE: usize = 256;
#[cfg(any(target_arch = "x86_64", target_arch = "aarch64", target_arch = "powerpc64"))]
pub const CACHE_LINE: usize = 128;
#[cfg(any(target_arch = "arm", target_arch = "mips", target_arch = "mips64"))]
pub const CACHE_LINE: usize = 32;
#[cfg(not(any(
    target_arch = "x86_64",
    target_arch = "aarch64",
    target_arch = "powerpc64",
    target_arch = "arm",
    target_arch = "mips",
    target_arch = "mips64",
    target_arch = "s390x"
)))]
pub const CACHE_LINE: usize = 64;

/// A value padded and aligned to a full cache line.
///
/// Use between values that are written by different threads. Do not pad values
/// that are always read together — padding costs bandwidth.
#[repr(align(128))]
#[derive(Debug, Default)]
pub struct Padded<T>(pub T);

impl<T> Padded<T> {
    pub const fn new(value: T) -> Self {
        Self(value)
    }

    pub fn get(&self) -> &T {
        &self.0
    }
}

impl<T> std::ops::Deref for Padded<T> {
    type Target = T;
    fn deref(&self) -> &T {
        &self.0
    }
}

impl<T> std::ops::DerefMut for Padded<T> {
    fn deref_mut(&mut self) -> &mut T {
        &mut self.0
    }
}

// ---- Per-shard counters: no contention on the hot path ----
use std::sync::atomic::{AtomicU64, Ordering};

pub struct ShardedCounter {
    shards: Vec<Padded<AtomicU64>>,
}

impl ShardedCounter {
    pub fn new(shards: usize) -> Self {
        Self {
            shards: (0..shards.max(1)).map(|_| Padded::new(AtomicU64::new(0))).collect(),
        }
    }

    /// Each caller passes its own shard index (e.g. a thread id % shards.len()).
    /// Relaxed is sufficient: we only need atomicity, not ordering.
    pub fn add(&self, shard: usize, delta: u64) {
        let idx = shard % self.shards.len();
        self.shards[idx].fetch_add(delta, Ordering::Relaxed);
    }

    /// Single-threaded read of the aggregate, done at the end of the workload.
    pub fn total(&self) -> u64 {
        self.shards.iter().map(|s| s.load(Ordering::Relaxed)).sum()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn padding_prevents_shared_lines() {
        let a = Padded::new(0u64);
        let b = Padded::new(0u64);
        let pa = &a as *const _ as usize;
        let pb = &b as *const _ as usize;
        let gap = pa.abs_diff(pb);
        assert!(gap >= 128, "two padded values must not share a 128-byte line, gap={gap}");
        assert_eq!(pa % 128, 0, "padded value must be line-aligned");
    }

    #[test]
    fn sharded_counter_sums() {
        let c = ShardedCounter::new(4);
        for i in 0..100u64 {
            c.add(i as usize % 4, 1);
        }
        assert_eq!(c.total(), 100);
    }

    #[test]
    fn counter_shards_do_not_share_lines() {
        let c = ShardedCounter::new(2);
        let p0 = &c.shards[0] as *const _ as usize;
        let p1 = &c.shards[1] as *const _ as usize;
        assert!(p0.abs_diff(p1) >= 128);
    }
}
