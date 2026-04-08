# Concurrency & Coroutines: Zig 0.13.0 - 0.15.0 Status

**Status:** ✅ COMPLETE  
**Last Updated:** April 8, 2026

## Objective
Evaluate the suitability of native coroutines (async/await) vs. alternative concurrency models for the Terminal Spatial Engine in the current Zig landscape.

## 1. The Async/Await Transition
Zig's concurrency model is currently in a state of historic redesign.

### Zig 0.13.0 (Stable/Legacy Mode)
- **Status:** Native `async`, `await`, `suspend`, and `resume` keywords are **disabled** in the self-hosted compiler.
- **Mechanism:** Developers rely on `std.Thread` and `std.Thread.Pool` for concurrency.
- **Performance:** OS threads provide true parallelism but have higher overhead (stack size, context switching) compared to coroutines.

### Zig 0.15.0+ (The "Colorless" Future)
- **Status:** Native keywords have been **removed**. Asynchrony is now handled via a pluggable **`std.Io`** interface.
- **Philosophy:** Functions take an `io: std.Io` parameter (similar to an `Allocator`). The implementation (blocking, io_uring, epoll) is injected at the top level.
- **Pattern:** Use `io.async(func, .{})` to return a `Future`, which must be explicitly `awaited` or `cancelled`.

## 2. Stackless vs. Stackful Coroutines
| Model | Mechanism | Impact on TUI |
|-------|-----------|---------------|
| **Stackless** | Compiler transforms function into a state machine. | Extremely memory efficient; ideal for thousands of widgets. |
| **Stackful (Fibers)**| Each coroutine has its own small stack. | Easier to use with existing synchronous C libraries (like Notcurses). |

## 3. Alternative Concurrency Patterns (0.13.0 Baseline)
Since native `async` is missing in the target 0.13.0 version:

### A. OS Threads + Thread Pools
- **Usage:** Standard `std.Thread.spawn()` or `std.Thread.Pool`.
- **Recommendation:** Best for the initial implementation. Use a pool of 4-8 workers for graph physics and AI streaming.

### B. High-Performance Event Loops (`libxev`)
- **Usage:** Third-party library implementing `io_uring`/`epoll`/`kqueue`.
- **Recommendation:** Use if I/O throughput (e.g., streaming thousands of graph updates per second) becomes the bottleneck.

### C. Manual State Machines
- **Usage:** Explicitly managing object states and transitions.
- **Recommendation:** Use for UI components that need to respond to input while background tasks are running.

## 4. Summary Recommendation for Terminal Engine
For the initial prototype (Zig 0.13.0), **do not use native async/await**. Instead:
1. **Primary Concurrency:** Use `std.Thread.Pool` for parallel physics and AI streaming.
2. **Synchronization:** Use `std.atomic.Queue` (MPSC) to pass data from worker threads back to the main UI thread.
3. **Future Proofing:** Design functions to be "colorless" (logic separate from execution) to ease the eventual migration to the `std.Io` model in Zig 0.16.0+.

Achieving 60 FPS is best served by a **Single-Consumer (UI) / Multi-Producer (Physics/AI)** architecture on standard threads.
