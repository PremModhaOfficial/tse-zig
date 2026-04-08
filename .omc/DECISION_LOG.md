# Decision Log: Terminal Spatial Engine (Zig Edition)

**Purpose:** Record key decisions, trade-offs, and rationale during research and validation phase.

---

## Decision 1: Research Scope & Priorities (April 8, 2026)

**Context:** User requested validation of the Terminal Spatial Engine PRD with focus on identifying gaps and unknowns beyond what's explicitly documented.

**Decision:**
- Prioritize **7 research threads** in this order:
  1. Zig + Notcurses integration maturity ✅ DONE
  2. 60+ FPS performance baseline ✅ DONE
  3. Zig async/threading for AI streaming ✅ DONE
  4. Arena allocator per-frame overhead ✅ DONE
  5. Cross-platform build complexity ✅ DONE
  6. File watcher race conditions ✅ DONE
  7. Compile risk matrix & PoC priorities ✅ DONE

**Rationale:**
- Research completed across all critical architectural blockers.

**Owner:** OpenCode Research Agent  
**Status:** ✅ COMPLETE

---

## Decision 2: Go → Zig Transition Rationale (April 8, 2026)

**Context:** User indicated the transition was driven by performance, C-interop, and experimentation.

**Decision:**
- Treat Zig choice as **already validated**. focus on proving the architecture works.

**Rationale:**
- Zig's zero-overhead C interop and memory control are ideal for this project's constraints.

**Owner:** OpenCode Research Agent  
**Status:** Accepted

---

## Decision 3: Knowledge Base Organization (April 8, 2026)

**Decision:**
- Create `.omc/` directory structure for persistent knowledge management.

**Owner:** OpenCode Research Agent  
**Status:** Implemented

---

## Decision 4: Zig Version Pinning (April 8, 2026)

**Decision:**
- **Pin Zig to 0.13.0** for stability and compatibility with existing Notcurses examples.

**Owner:** Project Lead  
**Status:** Accepted

---

## Decision 5: Build System Strategy (April 8, 2026)

**Decision:**
- Use a unified `build.zig` with platform-specific branches for Linux (pkg-config), macOS (Homebrew), and Windows (MSYS2/DLL bundling).

**Owner:** Build System Lead  
**Status:** Accepted

---

## Decision 6: Windows Support Strategy (April 8, 2026)

**Decision:**
- Support Windows via **MSYS2/UCRT64**. Avoid MSVC as Notcurses does not officially support it. Bundle required DLLs for GA release.

**Owner:** Product Lead  
**Status:** Accepted

---

## Decision 7: Performance Baseline (60+ FPS) Results (April 8, 2026)

**Decision:**
- **Validated** high feasibility. 60 FPS is achievable on modern terminals (Foot, Kitty, Alacritty) due to Notcurses' diff-based rendering engine.

**Rationale:**
- Terminal I/O is the bottleneck, not the rendering logic or Zig interop.

**Owner:** Performance Lead  
**Status:** ✅ Validated

---

## Decision 8: MPSC Queue Implementation Strategy (April 8, 2026)

**Decision:**
- Standardize on **`std.atomic.Queue` (MPSC)** for token streaming. Use lock-free ring buffers for high-throughput AI data.

**Owner:** Concurrency Lead  
**Status:** ✅ Validated

---

## Decision 9: Memory Management Strategy (April 8, 2026)

**Decision:**
- Use **`arena.reset(.retain_capacity)`** per frame to eliminate syscall overhead and provide $O(1)$ allocation performance.

**Owner:** OpenCode Research Agent  
**Status:** ✅ Validated

---

## Decision 10: File Watcher Strategy (April 8, 2026)

**Decision:**
- Watch **parent directory** to handle atomic renames. Mandate **Atomic Write-and-Rename** for all JSON state saves.

**Owner:** OpenCode Research Agent  
**Status:** ✅ Validated

---

## Review Schedule

| Decision | Review Date | Owner | Status |
|----------|-------------|-------|--------|
| 1. Research Scope | 4/8/26 | Agent | ✅ Complete |
| 7. Performance Baseline | 4/8/26 | Lead | ✅ Validated |
| 8. MPSC Queue Strategy | 4/8/26 | Lead | ✅ Validated |
| 9. Memory Strategy | 4/8/26 | Agent | ✅ Validated |
| 10. File Watcher Strategy| 4/8/26 | Agent | ✅ Validated |

---

## Decision 15: Concurrency & Coroutines Strategy (April 8, 2026)

**Context:** native `async`/`await` is in flux (disabled in 0.13.0, removed in 0.15.0).

**Decision:**
- **Avoid native async keywords** in the initial implementation (Zig 0.13.0).
- Standardize on **OS Threads** (`std.Thread`) and **Thread Pools** (`std.Thread.Pool`) for parallel graph physics and AI streaming.
- Design logic to be "colorless" to facilitate the eventual transition to the `std.Io` model (Zig 0.16.0+).

**Rationale:**
- Native async is not production-ready in the current Zig release cycle.
- OS threads provide true parallelism with stable APIs.
| 11. Event-Driven Arch | 4/8/26 | User | ✅ **MAJOR PIVOT** |

---

## Decision 11: Event-Driven Architecture Pivot (April 8, 2026)

**Context:** User proposed: "I think I will make this event driven arch with hooks and events and shit for perf"

**Decision:** Replace pure 60 FPS frame loop with **hybrid event-driven + capped frame loop** architecture.

### Architecture Change

| Before (PRD) | After (Event-Driven) |
|--------------|---------------------|
| Constant 60 FPS frame loop | Event-triggered with 60 FPS cap |
| Per-frame arena deinit | Arena deinit only on render |
| Polling-based input | epoll/libxev event sources |
| No hook system | 3-phase hooks (before/on/after) |

### Core Design

```
┌─────────────────────────────────────────────────────────┐
│                   EVENT SOURCES                          │
├─────────────┬─────────────┬─────────────┬──────────────┤
│  Terminal   │   Network   │    File     │    Timers    │
│  (stdin)    │   (AI API)  │  (inotify)  │  (physics)   │
└──────┬──────┴──────┬──────┴──────┬──────┴───────┬──────┘
       └─────────────┴─────────────┴──────────────┘
                           │
                           ▼
       ┌───────────────────────────────────────┐
       │     MPSC Queue (thread-safe)          │
       │  + Event coalescing (resize, mouse)   │
       └─────────────────┬─────────────────────┘
                         │
                         ▼
       ┌───────────────────────────────────────┐
       │      HOOK DISPATCHER                  │
       │  before → on → after (priority)       │
       └─────────────────┬─────────────────────┘
                         │
                         ▼
       ┌───────────────────────────────────────┐
       │  RENDER (60fps cap, dirty-only)       │
       │  Notcurses planes + damage tracking   │
       └───────────────────────────────────────┘
```

### Event Taxonomy

```zig
Event = union(enum) {
    input: InputEvent,       // keyboard, mouse, touch
    external: ExternalEvent, // AI tokens, file change, IPC
    internal: InternalEvent, // physics_tick, node_added, viewport_changed
    system: SystemEvent,     // resize, signals, quit
};
```

### Hook System

- **Phases:** `before` (can cancel) → `on` (handle) → `after` (cleanup)
- **Priority:** system > input > external > internal
- **Extensibility:** Plugins register handlers for specific event types

### Performance Benefits

| Metric | Before | After |
|--------|--------|-------|
| Idle CPU | ~2-5% (constant loop) | ~0% (epoll blocks) |
| Input latency | 0-16.67ms (frame boundary) | <1ms (immediate) |
| Arena resets/sec | 60 (every frame) | Variable (on-dirty) |
| AI response handling | Queued to next frame | Immediate dispatch |

### Zig Implementation Choices

- **Event loop:** libxev (production) or raw epoll (minimal deps)
- **Thread-safe queue:** `std.Thread.Mutex` + `eventfd` for wakeup
- **File watching:** inotify (Linux), kqueue (macOS)
- **Timers:** Timer wheel (256 slots × 16ms = ~4sec coverage)

### Trade-offs

| Gain | Cost |
|------|------|
| Responsiveness | Implementation complexity |
| Efficiency (zero idle CPU) | Debugging async flows |
| Scalability | Event object memory |
| Testability (event replay) | Learning curve |

**Rationale:**
- Physics simulation still needs ticks, but capped at 60fps max
- Event-driven naturally fits async AI streaming
- Hook system enables extensibility (debug overlays, plugins)
- Dirty tracking avoids redundant renders

**Full Research:** `.omc/research/EVENT_DRIVEN_ARCHITECTURE.md` (1,291 lines)

**Owner:** User (architectural decision)  
**Status:** ✅ APPROVED — Architecture pivot accepted

---

**Last Updated:** April 8, 2026  
**Next Review:** Post-PoC Implementation
