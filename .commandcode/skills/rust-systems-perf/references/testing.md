# Verification: Coverage, UB, Races, Features

Load this when setting up gates, when a `bugs.sh` check fails, or when adding unsafe or concurrent code.

## Coverage

Use `cargo-llvm-cov`. It wraps `rustc -C instrument-coverage` and gives region and line coverage.

```bash
cargo install cargo-llvm-cov --locked
rustup component add llvm-tools-preview
cargo llvm-cov --workspace --all-features --summary-only
cargo llvm-cov --workspace --html --open
```

Gate in CI:

```bash
cargo llvm-cov --workspace --fail-under-lines 90 --fail-under-regions 85
```

Notes:
- Region coverage is the meaningful metric for branch-heavy systems code; line coverage hides partially-taken branches.
- Branch coverage and doctests are nightly-only and unstable.
- Exclude generated code with `--ignore-filename-regex`, not by deleting tests.
- A high number over trivial getters means nothing. Check that the error paths and the `unsafe` blocks are covered.

## Undefined behavior: Miri

```bash
rustup +nightly component add miri
cargo +nightly miri test
```

Miri interprets the code and catches out-of-bounds, use-after-free, uninitialized reads, invalid pointer arithmetic and provenance violations, plus data races in concurrent code. It is slow and cannot run most native-code dependencies — gate it to the crates that contain `unsafe`.

If Miri cannot run a dependency, isolate the unsafe logic behind a feature so the rest of the suite still runs.

## Data races: ThreadSanitizer

```bash
RUSTFLAGS="-Zsanitizer=thread" cargo +nightly test -Zbuild-std --target "$(rustc -vV | sed -n 's/^host: //p')"
```

TSan finds races that actually execute in the test run. It needs nightly, Linux or macOS, and does not work on Apple Silicon in all configurations — verify before relying on it.

## Interleavings: loom

`loom` systematically permutes thread interleavings under the C11 memory model. Use it for the small, critical data structures, not for the whole program.

Setup, `Cargo.toml`:

```toml
[target.'cfg(loom)'.dependencies]
loom = "0.7"

# Rust 1.80+ warns on unexpected cfg names. Declare it or the build is noisy:
[lints.rust]
unexpected_cfgs = { level = "warn", check-cfg = ['cfg(loom)'] }
```

Type switch module:

```rust
// src/sync.rs
#[cfg(loom)]
pub(crate) use loom::sync::atomic::{AtomicUsize, Ordering};
#[cfg(not(loom))]
pub(crate) use std::sync::atomic::{AtomicUsize, Ordering};
```

Test:

```rust
#[test]
fn no_lost_updates() {
    loom::model(|| {
        let counter = std::sync::Arc::new(AtomicUsize::new(0));
        let a = counter.clone();
        let b = counter.clone();
        let t1 = loom::thread::spawn(move || { a.fetch_add(1, Ordering::Relaxed); });
        let t2 = loom::thread::spawn(move || { b.fetch_add(1, Ordering::Relaxed); });
        t1.join().unwrap();
        t2.join().unwrap();
        assert_eq!(counter.load(Ordering::Relaxed), 2);
    });
}
```

Run:

```bash
RUSTFLAGS="--cfg loom" cargo test --release --test loom_counter
LOOM_MAX_PREEMPTIONS=3 RUSTFLAGS="--cfg loom" cargo test --release
```

**Guard every loom test file with `#![cfg(loom)]` at the top.** Without it, a plain `cargo test` or `cargo llvm-cov` compiles the file without `--cfg loom`, the dependency is missing, and the whole build fails. This is the single most common way loom breaks a project's normal test run.

Limits that matter:
- Only types replaced by `loom` are visible to the model. Direct `std::sync::Mutex` use is unmodeled.
- Exhaustive checking explodes with thread count; bound preemptions to 2–3.
- `Relaxed` reorderings inside a thread cannot be fully modeled, so a pass is not a proof.
- Add `loom::thread::yield_now()` in spin loops or loom will starve a thread and report a false hang.

## Leaks

- `valgrind --leak-check=full --error-exitcode=1` on Linux for precise stacks.
- `dhat` `At t-end` nonzero (see [profiling.md](profiling.md)).
- Heap-usage assertions for critical paths: "this function allocates zero times".

```rust
// tests/alloc_zero.rs — must be its own integration test file, single test
#[global_allocator]
static ALLOC: dhat::Alloc = dhat::Alloc;

#[test]
fn hot_path_does_not_allocate() {
    let _p = dhat::Profiler::builder().testing().build();
    let mut buf = Vec::with_capacity(64);
    hot_path(&mut buf);
    let stats = dhat::HeapStats::get();
    dhat::assert_eq!(stats.total_blocks, 0);
}
```

## CPU features

Code that runs on your machine and crashes on a customer's is usually a CPU-feature bug.

Rules:
- Never ship `-C target-cpu=native`. It emits instructions the baseline does not have.
- Use `is_x86_feature_detected!("avx2")` / `is_aarch64_feature_detected!("neon")` at runtime, and keep a scalar fallback compiled without `#[target_feature]`.
- `#[target_feature(enable = "avx2")]` functions are `unsafe` to call without runtime detection.
- Test the fallback path explicitly; it is the path that runs on the machines you do not own.
- `-C target-feature=+crt-static` changes behavior on some targets; unrelated to SIMD but a common source of "works here" surprises.

Useful check:

```bash
grep -rn 'target_feature\|target-cpu\|is_x86_feature_detected\|is_aarch64_feature_detected\|cfg(target_arch' src/
```

For each hit, confirm there is a runtime check and a non-feature fallback.

## CI ordering

Fast to slow, so failures surface cheaply:

1. `cargo fmt --check`
2. `cargo clippy --all-targets -- -D warnings`
3. `cargo test`
4. `cargo llvm-cov --fail-under-lines N`
5. `cargo +nightly miri test` (unsafe crates only)
6. loom tests
7. sanitizers
8. benchmarks (report only, never gate on wall-clock in CI)
