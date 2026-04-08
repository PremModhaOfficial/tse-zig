# Epic 3: Asynchronous Event Loop & Concurrency

**Objective:** Develop the engine's core orchestration layer to ensure non-blocking input and processing.

### Technical Requirements:
1.  **Thread Safety:** Design a `tse.concurrent.MessageQueue` using lock-free atomic primitives for passing events between input threads and the engine main loop.
2.  **Event Orchestration:** Create a primary `EngineLoop` thread that:
    - Polls the `MessageQueue`.
    - Updates the ECS state.
    - Triggers the RenderEngine sync.
3.  **Graceful Shutdown:** Implement atomic shutdown flags that cleanly stop input and worker threads before releasing the Notcurses context.
4.  **Timer Precision:** Utilize `std.time.Instant` for frame-delta calculation, ensuring consistent movement speed regardless of CPU clock frequency.

### Success Criteria:
- Low-latency input handling (sub-5ms from keystroke to message arrival).
- 100% thread-safe data access between the event loop and rendering layers.
- Stable framerate control (e.g., locking to 60 FPS).
