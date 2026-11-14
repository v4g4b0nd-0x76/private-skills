// dhat-rs wiring. Copy the parts you need into your binary crate.
//
// Cargo.toml:
//   [dependencies]
//   dhat = { version = "0.3", optional = true }
//
//   [features]
//   dhat-heap = ["dep:dhat"]
//
//   [profile.release]
//   debug = 1
//
// Run:
//   cargo run --release --features dhat-heap
//
// Then open dhat-heap.json at https://nnethercote.github.io/dh_view/dh_view.html

// ---- binary crate: src/main.rs ----

#[cfg(feature = "dhat-heap")]
#[global_allocator]
static ALLOC: dhat::Alloc = dhat::Alloc;

fn main() {
    // Must be the first statement: the guard covers the rest of main.
    #[cfg(feature = "dhat-heap")]
    let _profiler = dhat::Profiler::new_heap();

    run();

    // The profiler writes the JSON on drop. If you call std::process::exit
    // anywhere, drop it explicitly first or no report is written:
    // #[cfg(feature = "dhat-heap")]
    // drop(_profiler);
}

fn run() {
    // ... program body ...
}

// ---- leak check variant ----
//
// Reading the summary printed to stderr:
//   Total       allocation traffic; the rate is what you reduce
//   At t-gmax   peak live bytes; the number to cap
//   At t-end    STILL LIVE AT EXIT — nonzero means a leak
//
// Leak hunting order:
//   1. Rc/Arc cycles -> break with Weak
//   2. mem::forget / Box::leak / ManuallyDrop on a path that never drops
//   3. unbounded caches and maps that only grow
//   4. detached threads or tasks holding state forever
//   5. a global registry that never evicts

// ---- heap usage test (separate integration test file!) ----
//
// Parallel tests share the global allocator, so dhat panics with more than one
// profiler running. Put each assertion in its own file under tests/ with a
// single #[test], and cargo test will run it in its own process.
//
// tests/hot_path_allocations.rs:
//
// #[global_allocator]
// static ALLOC: dhat::Alloc = dhat::Alloc;
//
// #[test]
// fn hot_path_does_not_allocate() {
//     let _p = dhat::Profiler::builder().testing().build();
//
//     let mut buf = Vec::with_capacity(64);
//     hot_path(&mut buf);          // the code under test
//     std::hint::black_box(&buf);  // stop the optimizer removing the work
//
//     let stats = dhat::HeapStats::get();
//     dhat::assert_eq!(stats.total_blocks, 0);
// }
//
// Assert the numbers you actually care about:
//   stats.total_blocks -> "exactly N allocations"
//   stats.max_bytes    -> "peak under N bytes"
//   stats.curr_blocks  -> "freed everything before returning"
