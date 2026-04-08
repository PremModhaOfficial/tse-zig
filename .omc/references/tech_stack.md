# Technology Stack: Terminal Spatial Engine (Zig Edition)

**Date:** April 8, 2026  
**Purpose:** Document technology choices, rationale, and alternatives considered

---

## Core Technology Stack

| Layer | Technology | Version | Rationale | Alternatives |
|-------|-----------|---------|-----------|--------------|
| **Language** | Zig | 0.13.0 (pinned) | Performance, C-interop, systems-level control | Go, Rust, C |
| **Terminal Rendering** | Notcurses | 3.x | 60+ FPS capable, Braille rendering, active maintenance | ncurses, Termbox, crossterm |
| **Event Loop** | libxev / epoll | Native | Cross-platform async I/O, zero-overhead | libuv, tokio (Rust) |
| **HTTP Client** | libcurl | 7.x | Proven, supports async, streaming responses | HTTP stdlib (if added to Zig), hyper |
| **File Watching** | inotify (Linux) / kqueue (macOS) | Native OS | Efficient, native, low overhead | watchman, fsnotify |
| **Build System** | build.zig | Zig native | Native Zig toolchain, no external dependencies | CMake, Meson |
| **Physics Engine** | Fruchterman-Reingold (custom Zig impl) | N/A | Proven in nodepad web; deterministic | Force-atlas 2, Spring-electric |

---

## Dependency Tree

```
Terminal Spatial Engine (Zig)
├── Zig 0.13.0 (Compiler)
│   ├── std.heap.ArenaAllocator
│   ├── std.Thread
│   ├── std.atomic.Queue (MPSC)
│   ├── std.fs (file I/O)
│   └── @cImport (C FFI)
│
├── Event Loop Layer
│   ├── libxev (production) OR
│   ├── raw epoll/kqueue (minimal)
│   ├── eventfd (thread wakeup)
│   └── Timer wheel (physics ticks)
│
├── Notcurses (C library)
│   ├── Braille blitter (NCBLITTER_BRAILLE)
│   ├── Color management
│   ├── Cell rendering
│   ├── Damage tracking (ncpile_render)
│   └── Dependencies: ncurses, libnotcurses-core
│
├── libcurl (C library)
│   ├── HTTP/2 support
│   ├── Streaming responses
│   └── TLS support (OpenSSL / BoringSSL)
│
└── OS-level (inotify / kqueue)
    └── File event notifications
```

---

## Architecture-Level Decisions

### 1. Why Zig (Instead of Go)?

**Decision:** Migrate from Go to Zig for Terminal Spatial Engine implementation.

**Rationale:**
- **Performance:** Zig offers lower-level control (arena allocators, manual memory management) → predictable latency for 60+ FPS
- **C-Interop:** Zig `@cImport` is simpler than Go `cgo` (no wrapper C code needed)
- **Compile-Time Metaprogramming:** Zig `comptime` enables graph DSL, type-safe physics kernels
- **Ecosystem Fit:** Smaller community but strong systems programming focus (similar to Rust)
- **Learning:** Emerging language; strategic bet on long-term adoption

**Alternatives Rejected:**
- **Go**: Slower GC (unpredictable pauses); `cgo` FFI overhead; slower binary startup
- **Rust**: Steeper learning curve; borrow checker friction; heavier build times
- **C**: Maintainability; Zig meta-programming enables safer abstractions over C

**Trade-Off:**
- Risk: Zig is pre-1.0; breaking changes every 2–3 months
- Mitigation: Version pinning (build.zig.zon); quarterly upgrade reviews

---

### 2. Why Notcurses (Instead of ncurses)?

**Decision:** Use Notcurses (C library) for terminal rendering instead of pure Zig or ncurses.

**Rationale:**
- **Performance:** Notcurses claims 60+ FPS; ncurses is inherently slower (polling-based)
- **Feature:** Braille sub-pixel rendering (NCBLITTER_BRAILLE) for graph precision
- **Maturity:** Actively maintained; used in production (https://github.com/dankamongmen/notcurses)
- **Modern Terminal Support:** Supports 24-bit color, mouse events, Unicode
- **Damage Tracking:** Built-in via `ncpile_render()` + `ncpile_rasterize()` separation

**Alternatives Rejected:**
- **ncurses**: Older, slower, no Braille support; would need custom rendering layer
- **Termbox**: Lightweight but limited feature set; lower terminal emulator compatibility
- **crossterm (Rust):** Zig equivalent doesn't exist; would need to port

**Trade-Off:**
- Dependency: Heavy C library (20+ source files, ~40KB binary)
- Mitigation: Compile from source (reproducible); disable multimedia (reduce size)

**Known Issues:**
- UBSAN disabled in build.zig (Notcurses has undefined behavior)
- Macro complexity (99 macros; manual wrapping needed)
- Platform-specific terminal emulator bugs not our concern

---

### 2.5 Why Event-Driven Architecture (Instead of Frame Loop)?

**Decision:** Pivot from pure 60 FPS frame loop to **hybrid event-driven + capped frame loop**.

**Rationale:**
- **Efficiency:** Zero CPU when idle (epoll blocks); frame loop wastes cycles on static scenes
- **Responsiveness:** Input handled immediately, not at next frame boundary (0-16ms delay eliminated)
- **Natural Fit:** AI streaming, file watching, and physics all map cleanly to events
- **Extensibility:** Hook system enables plugins, debug overlays, middleware

**Architecture:**
```
Event Sources → MPSC Queue → Hook Dispatcher → Dirty Tracking → Render (60fps cap)
```

**Event Types:**
| Category | Events | Priority |
|----------|--------|----------|
| **System** | resize, signals, quit | Highest |
| **Input** | keyboard, mouse, touch | High |
| **External** | AI tokens, file change | Normal |
| **Internal** | physics_tick, node_added | Low |

**Hook System:**
- **Phases:** `before` (can cancel) → `on` (handle) → `after` (cleanup)
- **Registration:** Handlers subscribe to specific event types with priority
- **Middleware:** Alternative pattern for cross-cutting concerns

**Implementation Choices:**
- **libxev:** Production-grade event loop (io_uring/epoll/kqueue abstraction)
- **Raw epoll:** Minimal dependencies, direct syscalls
- **Timer wheel:** Efficient timer management (256 slots × 16ms)
- **eventfd:** Thread wakeup for cross-thread event posting

**Performance Gains:**
| Metric | Frame Loop | Event-Driven |
|--------|-----------|--------------|
| Idle CPU | ~2-5% | ~0% |
| Input latency | 0-16.67ms | <1ms |
| Arena resets/sec | 60 (constant) | On-demand |

**Trade-offs:**
- Complexity: More moving parts than simple loop
- Debugging: Async flows harder to trace
- Mitigation: Event logging, deterministic replay for debugging

**Full Research:** `.omc/research/EVENT_DRIVEN_ARCHITECTURE.md` (1,291 lines)

---

### 3. Why libcurl (Instead of Native Zig HTTP)?

**Decision:** Use libcurl (C library) for HTTP/AI streaming instead of Zig stdlib or third-party HTTP crate.

**Rationale:**
- **Maturity:** Proven, widely deployed; handles edge cases (redirects, auth, retries)
- **Streaming:** Native support for chunked transfer encoding (AI response streaming)
- **Async:** Non-blocking I/O via curl_multi interface or threading
- **TLS:** Automatic TLS verification, certificate management

**Alternatives Rejected:**
- **Zig stdlib http module:** Immature; doesn't exist or incomplete
- **Custom socket code:** High complexity; reinventing wheel
- **Third-party Zig HTTP:** Ecosystem too young; no async-streaming crates

**Trade-Off:**
- Dependency: Large C library (~500KB)
- Mitigation: Use only core libcurl (no extras); consider custrom HTTP layer for Phase 2

---

### 4. Why Per-Frame Arena Allocator?

**Decision:** Use `std.heap.ArenaAllocator` with per-frame deinit/reinit (destroy all allocations each frame).

**Rationale:**
- **Simplicity:** No need to track individual node allocations; bulk deallocation is O(1)
- **Memory Safety:** Arena lifetime = frame lifetime; no use-after-free possible
- **Performance Assumption:** Bulk deallocation faster than individual frees

**Alternatives Considered:**
- **Pre-allocated buffers:** Simpler but requires tuning max node count
- **Arena pool:** Reuse arenas across frames; more complex lifecycle management
- **Standard allocator (GPA):** Higher fragmentation; slower on high-volume allocations

**Unknowns:**
- Per-frame cost not measured; **CRITICAL** (Research-4 pending)
- Memory fragmentation over time unknown
- Alternative strategies may outperform

**Trade-Off:**
- Assumption: Per-frame deinit is fast enough (< 2ms on reference hardware)
- Risk: If assumption wrong, architecture needs redesign

---

### 5. Why inotify/kqueue (Instead of Polling)?

**Decision:** Use native OS file events (inotify on Linux, kqueue on macOS) for file watching.

**Rationale:**
- **Efficiency:** Event-driven; no polling overhead
- **Responsiveness:** Changes detected immediately (< 100ms latency)
- **Native:** OS-provided; no extra dependencies

**Alternatives Rejected:**
- **Polling (stat + mtime):** CPU overhead; latency > 500ms
- **watchman (Facebook):** Overkill for single-file watching; extra dependency
- **fsnotify (Rust crate):** Zig equivalent doesn't exist

**Implementation Details:**
- **Linux:** `inotify_add_watch()` on JSON file; blocking select/poll loop
- **macOS:** `kqueue()` for directory changes; convert to file updates
- **Windows:** Deferred to Phase 3 (or use `ReadDirectoryChangesW`)

**Unknowns:**
- Race conditions between renderer read + file modification (Research-6 pending)
- "Last Write Wins" semantics not formally specified

---

### 6. Why Fruchterman-Reingold (Instead of Force-Atlas 2)?

**Decision:** Use Fruchterman-Reingold force-directed layout for graph positioning.

**Rationale:**
- **Simplicity:** Classic algorithm; well-understood; deterministic
- **Performance:** O(n²) per iteration; acceptable for < 1000 nodes
- **Responsiveness:** Quick convergence; responsive user interactions
- **Proven:** D3.js (nodepad web) uses variant; behavior known

**Alternatives Rejected:**
- **Force-Atlas 2:** More complex; less responsive; designed for static visualization
- **Kamada-Kawai:** Higher O(n³) complexity; slower per-iteration
- **Hierarchical (Sugiyama):** Not suitable for general graphs; requires DAG

**Optimization Opportunities:**
- SIMD for force calculations (Phase 2)
- Quadtree spatial partitioning (reduce O(n²) to O(n log n)) (Phase 2)
- GPU acceleration for large graphs (Phase 2)

**Unknown:**
- Per-iteration budget unmeasured (Research-2 pending)

---

## Build Toolchain

### Zig Build System (`build.zig`)

```zig
// Key pattern: compile Notcurses from C source
const notcurses = b.addStaticLibrary(.{
    .name = "notcurses",
    .target = target,
    .optimize = optimize,
});
notcurses.linkLibC();
notcurses.linkSystemLibrary("ncurses");
notcurses.addCSourceFiles(...);

// Compile Zig app
const exe = b.addExecutable(.{
    .name = "tse",
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
});
exe.linkLibrary(notcurses);  // Link compiled notcurses
exe.linkLibC();  // Link C stdlib
```

### Dependencies (Per-Platform)

| Platform | Build Command | Dependencies |
|----------|---------------|--------------|
| **Linux** | `zig build` | pkg-config, gcc, make (for Notcurses build) |
| **macOS** | `zig build` | Xcode, Homebrew (pkg-config, ncurses) |
| **Windows** | `zig build -Dtarget=x86_64-windows-msvc` | MSVC, WinSDK |

---

## Version Pinning Strategy

**Decision (Decision-4):** Pin Zig to 0.13.0; quarterly upgrade reviews.

**Rationale:**
- Zig is pre-1.0; breaking changes expected
- Pinning prevents build failures; projects remain reproducible
- Quarterly reviews balance stability + bug fixes

**Implementation:**
- `build.zig.zon`: Specify `zig = "0.13.0"`
- CI: Test against 0.13.0 only; 0.14+ as experimental
- Upgrade Timeline:
  - Month 1–3: Stability on 0.13.0
  - Month 4: Evaluate Zig 0.14 (if released)
  - Month 7: Decide: upgrade or stay on 0.13.0
  - Repeat quarterly

---

## Performance Targets

| Metric | Target | Status |
|--------|--------|--------|
| Frame Rate | 60 FPS (16.67ms per frame) | ⏳ Unvalidated |
| Physics Iteration Time | < 8ms/frame (100 nodes) | ⏳ Unvalidated |
| Rendering Time | < 6ms/frame (Notcurses) | ⏳ Unvalidated |
| Allocator Per-Frame Cost | < 2ms | ⏳ Unvalidated |
| AI Response Latency | < 100ms (end-to-end) | ⏳ Unvalidated |

---

## Testing & Verification

| Component | Test Strategy | Status |
|-----------|---------------|--------|
| Notcurses FFI | Dundalek example build + run | ✅ Done (Research-1) |
| 60+ FPS Performance | Benchmark script + profiler | ⏳ PoC-1 pending |
| Threading | Unit tests + concurrency stress test | ⏳ PoC-2 pending |
| Arena Allocator | Benchmark allocation/deallocation | ⏳ PoC-3 pending |
| Cross-Platform Build | CI on Linux + macOS + Windows | ⏳ PoC-4 pending |
| File Watching | Concurrent edit test harness | ⏳ Analysis-5 pending |

---

## Maintenance & Evolution

| Phase | Focus | Dependencies |
|-------|-------|--------------|
| **Phase 1 (MVP)** | Core rendering + AI streaming | Zig 0.13.0, Notcurses 3.x, libcurl 7.x |
| **Phase 2 (Beta)** | Cross-platform build, performance tuning | Zig 0.13.0, consider ecosystem crates |
| **Phase 3 (GA)** | Windows support, multimedia (Phase 2 TBD) | Zig 0.14+ (upgrade decision), optional: GPU libraries |

---

## Known Limitations

| Limitation | Workaround | Future |
|-----------|-----------|--------|
| Zig pre-1.0 | Version pinning | Upgrade when 1.0 released |
| Notcurses UBSAN | Disable sanitizer in build.zig | Monitor upstream fixes |
| Single-threaded physics | Thread-pool (Phase 2) | SIMD / GPU (Phase 3) |
| No native Zig HTTP | Use libcurl FFI | Custom async layer (Phase 2) |
| Terminal emulator variability | Fallback rendering modes | Terminal detection (Phase 2) |

---

**Last Updated:** April 8, 2026  
**Next Review:** Post-Architecture Approval (Gate 1)
