# Arena Allocator: Per-Frame Allocation Overhead

**Status:** ✅ COMPLETE  
**Last Updated:** April 8, 2026

## Objective
Quantify the overhead of using Zig's `ArenaAllocator` for per-frame data and identify the optimal strategy to minimize allocation-related latency.

## 1. Traditional `deinit` vs. `reset`
Using `deinit()` and `init()` every frame is inefficient because it returns memory to the OS (via `munmap` or `free`) only to request it back immediately in the next frame.

### Comparison:
- **`deinit()` + `init()`**: Triggers syscalls (`munmap`, `mmap`), leading to context switches and "cold start" costs for memory access.
- **`reset(.retain_capacity)`**: Frees all objects but keeps the underlying memory blocks. This "pre-heats" the arena for the next frame.

## 2. Allocation Speed: $O(1)$ Pointer Bump
When an arena has already allocated enough capacity from a previous frame, subsequent allocations are essentially "free."
- **Logic:** Each `alloc()` call becomes a single pointer increment and an overflow check.
- **Result:** This is orders of magnitude faster than a General Purpose Allocator (GPA) which must search its free list.

## 3. Cache Locality & Fragmentation
- **Locality:** Reusing the same arena blocks ensures high cache hit rates for per-frame data (e.g., node positions, color palettes).
- **Fragmentation:** Since the entire arena is reset at once, fragmentation within the arena is non-existent.

## 4. Alternative Allocation Strategies

### Thread-Local Arenas
For a multi-threaded graph engine:
- Give each worker thread its own `ArenaAllocator`.
- Reset each arena at the end of its respective task/frame.
- This avoids lock contention on a shared heap.

### Double-Buffering
For asynchronous rendering/physics:
- Use two arenas (A and B).
- While the physics thread writes to arena A, the rendering thread reads from arena B.
- Swap arenas every frame.

## 5. Summary Recommendation
Use **`std.heap.ArenaAllocator.reset(.retain_capacity)`** as the default per-frame allocation strategy. This eliminates syscall overhead and provides $O(1)$ allocation performance, fitting perfectly within the 16.67ms frame budget.
