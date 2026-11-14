// loom concurrency test template.
//
// loom only observes the types it replaces. Any direct use of std::sync::Mutex,
// std::thread, or std::sync::atomic inside the tested code is INVISIBLE to it.
// Keep a small sync module that switches types under cfg(loom), and use it
// everywhere in the code under test.
//
// Cargo.toml:
//   [target.'cfg(loom)'.dependencies]
//   loom = "0.7"
//
//   # Rust 1.80+ warns on unexpected cfg names; declare it:
//   [lints.rust]
//   unexpected_cfgs = { level = "warn", check-cfg = ['cfg(loom)'] }
//
// Run:
//   RUSTFLAGS="--cfg loom" cargo test --release --test loom_counter
//   LOOM_MAX_PREEMPTIONS=3 RUSTFLAGS="--cfg loom" cargo test --release
//
// Preemptions bound the state space: exhaustive checking explodes with threads.

// ---- src/sync.rs: the type switch ----

#[cfg(loom)]
pub(crate) use loom::sync::atomic::{AtomicUsize, Ordering};
#[cfg(not(loom))]
pub(crate) use std::sync::atomic::{AtomicUsize, Ordering};

#[cfg(loom)]
pub(crate) use loom::sync::{Arc, Mutex};
#[cfg(not(loom))]
pub(crate) use std::sync::{Arc, Mutex};

#[cfg(loom)]
pub(crate) use loom::thread;
#[cfg(not(loom))]
pub(crate) use std::thread;

// ---- tests/loom_counter.rs ----
//
// CRITICAL: guard the whole file with #![cfg(loom)]. Without it, a plain
// `cargo test` or `cargo llvm-cov` tries to compile these files WITHOUT
// --cfg loom, the loom dependency is absent, and the entire build fails.
// This is the most common way loom breaks a project's normal test run.

#![cfg(loom)]

// use mycrate::sync::{Arc, AtomicUsize, Ordering, thread};

#[test]
fn counter_never_loses_an_update() {
    loom::model(|| {
        let counter = Arc::new(AtomicUsize::new(0));

        let a = Arc::clone(&counter);
        let t1 = thread::spawn(move || {
            a.fetch_add(1, Ordering::Relaxed);
        });

        let b = Arc::clone(&counter);
        let t2 = thread::spawn(move || {
            b.fetch_add(1, Ordering::Relaxed);
        });

        t1.join().unwrap();
        t2.join().unwrap();

        assert_eq!(counter.load(Ordering::Relaxed), 2);
    });
}

#[test]
fn publishes_then_signals() {
    // Demonstrates the release/acquire pair loom will check.
    loom::model(|| {
        let data = Arc::new(Mutex::new(0u32));
        let ready = Arc::new(AtomicUsize::new(0));

        let d = Arc::clone(&data);
        let r = Arc::clone(&ready);
        let producer = thread::spawn(move || {
            *d.lock().unwrap() = 42;
            r.store(1, Ordering::Release); // publish
        });

        let d2 = Arc::clone(&data);
        let r2 = Arc::clone(&ready);
        let consumer = thread::spawn(move || {
            while r2.load(Ordering::Acquire) == 0 {
                thread::yield_now(); // required, or loom starves this thread
            }
            *d2.lock().unwrap()
        });

        producer.join().unwrap();
        let seen = consumer.join().unwrap();
        assert_eq!(seen, 42);
    });
}

// ---- debugging a loom failure ----
//
// loom saves the exact failing interleaving, then replays it:
//
//   LOOM_CHECKPOINT_FILE=loom.json LOOM_CHECKPOINT_INTERVAL=10000 \
//     RUSTFLAGS="--cfg loom" cargo test --release --test loom_counter
//
//   LOOM_CHECKPOINT_INTERVAL=1 LOOM_CHECKPOINT_FILE=loom.json \
//     LOOM_LOG=trace LOOM_LOCATION=1 \
//     RUSTFLAGS="--cfg loom" cargo test --release --test loom_counter
//
// Caveat: loom cannot model all Relaxed reorderings within a thread, so a
// passing run is evidence, not proof.
