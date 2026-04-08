# Async & Threading: MPSC Patterns for AI Streaming

**Status:** ✅ COMPLETE  
**Last Updated:** April 8, 2026

## Objective
Establish a robust pattern for handling concurrent AI inference tasks (streaming tokens) and updating the terminal UI without blocking the main render loop.

## 1. MPSC (Multi-Producer Single-Consumer) Pattern in Zig
To handle tokens from multiple AI models/streams, a thread-safe MPSC queue is required.

### Standard Library: `std.atomic.Queue`
- **Intrusive Linked List:** Data nodes themselves contain pointers.
- **Thread Safety:** Multiple threads can call `put()` without a mutex.
- **Single Consumer:** Only the UI/Render thread should call `get()`.

### Implementation Strategy:
1. **Producer:** AI threads (inference tasks) create token packets and `put` them into the queue.
2. **Consumer:** The main loop `get()`s tokens every frame to update the graph state.
3. **Backpressure:** Use a semaphore (`std.Thread.Semaphore`) or condition variable to signal the consumer when new tokens arrive, reducing CPU idle-wait.

## 2. High-Frequency AI Streaming (Token-by-Token)
For high-throughput streaming (e.g., local LLMs pushing 100+ tokens/sec), allocation overhead per token must be avoided.

- **Lock-Free Ring Buffer:** A fixed-size array with atomic indices is preferred over linked lists.
- **Pre-allocation:** Pre-allocate a pool of `TokenNode` structs to reuse, avoiding heap allocation within the inference loop.

## 3. Thread Safety & Memory Visibility
- **Memory Ordering:** Use `.Acquire` for reading from the queue and `.Release` for writing. This ensures that the token data is visible to the consumer thread after it sees the update to the queue's head/tail.
- **Cache Line Alignment:** Ensure the head/tail of the queue are aligned to `std.atomic.cache_line` to prevent "false sharing" which can degrade performance in multi-core systems.

## 4. Error Handling & Thread Isolation
- **Isolation:** If an AI thread crashes or returns an error, it must signal the main loop via a special `ErrorToken` instead of panicking.
- **Cleanup:** Ensure the main thread can signal AI threads to shut down (e.g., via an atomic `std.atomic.Value(bool)`) when the user exits or cancels an operation.

## 5. Summary Recommendation
Use `std.atomic.Queue` with a pre-allocated pool for standard streaming. For high-performance tokens, implement a bounded lock-free ring buffer. This ensures the 60 FPS UI never stalls due to AI processing.
