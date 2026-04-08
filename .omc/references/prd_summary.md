# PRD Summary: Terminal Spatial Engine (Zig Edition)

**Reference:** Original PRD provided by user (April 2026)  
**Purpose:** Extracted key requirements, claims, and design decisions for quick lookup during research

---

## Project Overview

**Name:** Terminal Spatial Engine (Zig Edition)

**Vision:** A high-performance library ecosystem for rendering floating-point spatial graphs in terminal grids at 60+ FPS, with concurrent AI chat streaming and real-time graph updates.

**Target Use Case:** `nodepad` CLI tool — visualize knowledge graphs with concurrent AI assistant interaction.

**Baseline Reference:** Earlier Go-based architecture (not provided; context only).

---

## Core Requirements

### P0 (Must Have)

| Requirement | Status | Notes |
|-------------|--------|-------|
| Render graphs in terminal using Notcurses Braille blitter | ✅ Planned | C library FFI via Zig; 64-star example repo exists |
| 60+ FPS sustained rendering | ⏳ Unvalidated | Performance baseline not measured; **CRITICAL** |
| Fruchterman-Reingold force-directed layout | ✅ Planned | Algorithm known; nodepad web uses D3.js version |
| Per-frame arena allocator (deinit/reinit every frame) | ⏳ Overhead unknown | Memory cost unmeasured; **HIGH RISK** |
| Native OS file events (inotify Linux, kqueue macOS) | ✅ Planned | Zig stdlib support; race conditions TBD |
| Concurrent AI streaming (CLI-02) | ⏳ Threading unvalidated | `std.Thread.spawn()` + MPSC queue pattern TBD; **CRITICAL** |

### P1 (Should Have)

| Requirement | Status | Notes |
|-------------|--------|-------|
| Multi-platform build (Linux, macOS, Windows) | ⏳ Partial | Linux proven; macOS/Windows unvalidated |
| Cross-platform Notcurses packaging | ⏳ Unvalidated | pkg-config (Linux), Homebrew (macOS), MSVC (Windows) |
| Graph persistence (JSON file format) | ✅ Design | File watcher handles updates |

### P2 (Nice to Have)

| Requirement | Status | Notes |
|-------------|--------|-------|
| Performance optimization (GPU acceleration, SIMD) | ✅ Future | Deferred to Phase 2 |
| Multimedia rendering (images, videos) | ⏳ Unvalidated | Notcurses FFmpeg integration complex |

---

## Architecture Design

### Key Design Decisions

1. **Language:** Zig (instead of Go)
   - **Rationale:** Performance + C-interop simplicity + compile-time codegen + ecosystem fit + learning/experimentation
   - **Status:** Accepted by user; language choice not re-evaluated
   
2. **C Terminal Library:** Notcurses
   - **Why:** Sub-pixel rendering (Braille), 60+ FPS capable, active development
   - **FFI Strategy:** Zig `@cImport` + thin wrapper module (`notcurses.zig`)
   - **Status:** FFI proven; macro complexity known

3. **Physics Engine:** Fruchterman-Reingold force-directed layout
   - **Why:** Responsive, deterministic, proven in nodepad web (D3.js version)
   - **Frame Budget:** ✅ Validated (ample time within 16.67ms)
   - **Implementation:** Per-node position updates in arena

4. **Memory Management:** Per-render arena allocator *(UPDATED)*
   - **Pattern:** Arena resets only on dirty render (not every frame)
   - **Optimization:** Use `arena.reset(.retain_capacity)` for O(1) resets
   - **Status:** ✅ Validated

5. **File Watching:** Native OS events
   - **Linux:** inotify (syscall-based, efficient)
   - **macOS:** kqueue (BSD event notification, efficient)
   - **Windows:** Deferred to Phase 3 (MSYS2 required)
   - **JSON Sync:** Atomic write-and-rename strategy; ✅ Validated

6. **Concurrency:** Event-driven + MPSC queue *(UPDATED)*
   - **Architecture:** Hybrid event-driven + capped 60fps frame loop
   - **Queue Pattern:** `std.atomic.Queue` (MPSC) or lock-free ring buffer
   - **Error Isolation:** Thread panic handling via supervisor pattern
   - **Status:** ✅ Validated

### Architectural Diagram *(UPDATED: Event-Driven)*

```
┌─────────────────────────────────────────────────────────────┐
│                    EVENT SOURCES                             │
├─────────────┬─────────────┬─────────────┬──────────────────┤
│  Terminal   │   Network   │    File     │     Timers       │
│   Input     │   (AI API)  │   Watcher   │   (Physics)      │
└──────┬──────┴──────┬──────┴──────┬──────┴────────┬─────────┘
       │             │             │               │
       ▼             ▼             ▼               ▼
┌─────────────────────────────────────────────────────────────┐
│              UNIFIED EVENT QUEUE (MPSC)                      │
│  [KeyPress] [MouseMove] [TokenChunk] [FileChange] [Tick]    │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    HOOK DISPATCHER                           │
│  • before phase (can cancel)                                 │
│  • on phase (handle event)                                   │
│  • after phase (cleanup, logging)                            │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              STATE UPDATE + DIRTY MARKING                    │
│  • Graph model update                                        │
│  • Physics integration step                                  │
│  • Mark affected nodes/regions as dirty                     │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│              RENDER SCHEDULER (Capped at 60fps)             │
│  • Skip render if nothing dirty                              │
│  • Batch all changes since last frame                        │
│  • Notcurses ncpile_render() + ncpile_rasterize()           │
└─────────────────────────────────────────────────────────────┘
```

### Event Loop Pseudocode *(UPDATED: Event-Driven)*

```zig
pub fn run(self: *EventLoop) !void {
    while (self.running) {
        // 1. Collect all pending events (non-blocking drain)
        while (self.event_queue.tryPop()) |event| {
            self.dispatchToHooks(event);  // before → on → after
        }
        
        // 2. Physics tick if simulation is active
        if (self.physics_active) {
            self.physicsStep();
            self.dirty.markLayout();
        }
        
        // 3. Render if dirty AND frame interval elapsed
        const now = std.time.nanoTimestamp();
        if (self.dirty.needsRender() and 
            now - self.last_render >= 16_666_666)  // ~60fps cap
        {
            self.render();
            self.last_render = now;
            self.dirty.clear();
        }
        
        // 4. Sleep until next event OR next frame deadline
        const timeout = self.calculateNextWakeup();
        self.event_queue.waitWithTimeout(timeout);
    }
}
```

---

## Performance Claims

| Claim | Source | Validated | Risk |
|-------|--------|-----------|------|
| 60+ FPS rendering | PRD | ❌ No | **CRITICAL** |
| Braille sub-pixel quality | PRD | ✅ Yes (Notcurses feature exists) | Low |
| Responsive force-directed layout | PRD | ⏳ Assumed (D3.js works; Zig version unvalidated) | Medium |
| Per-frame memory reclamation | PRD | ❌ No overhead measurement | **HIGH** |

---

## Dependencies & Ecosystem

| Component | Role | Status | Risk |
|-----------|------|--------|------|
| **Notcurses (C library)** | Terminal rendering | ✅ FFI proven | Medium (macro complexity) |
| **libcurl (C library)** | AI HTTP streaming | ✅ Zig FFI capable | Low (stable library) |
| **Zig stdlib** | Threads, allocators, file I/O | ✅ APIs exist | Low (pre-1.0 breakage) |
| **inotify/kqueue** | OS file events | ✅ Platform-native | Low (OS-provided) |

---

## Feature Map (from PRD Implied Requirements)

### CLI-01: Terminal Rendering
- Render floating-point node positions on terminal grid
- Use Notcurses Braille blitter for sub-pixel precision
- Support zoom/pan interactions
- **Status:** Architecture drafted; FPS unvalidated

### CLI-02: Concurrent AI Streaming
- Spawn thread for long-lived AI HTTP connection (libcurl)
- Send graph updates to AI assistant; receive responses
- Queue AI responses to renderer thread
- Render AI output alongside graph
- **Status:** Threading patterns unvalidated; **CRITICAL**

### CLI-03: File Watching & Sync
- Watch JSON graph file for changes (inotify/kqueue)
- Reload graph on file modification
- Handle concurrent edits (renderer + external editor)
- **Status:** Race conditions unanalyzed; **MEDIUM RISK**

### CLI-04: Performance Optimization
- Achieve 60+ FPS on graphs with 100+ nodes
- Profile and optimize physics engine (Fruchterman-Reingold)
- Minimize allocator overhead (per-frame arena)
- **Status:** Baseline unestablished; **CRITICAL**

---

## Build & Deployment

### Build System: `build.zig`
- **Strategy:** Compile Notcurses from C source (dundalek approach)
- **Dependencies:** pkg-config (Linux), Homebrew (macOS), MSVC (Windows)
- **Zig Version:** Pin to 0.13.0 (decision pending)
- **Cross-Platform:** Linux MVP; macOS Phase 2; Windows Phase 3

### Release Phases

| Phase | Target | Scope | Timeline |
|-------|--------|-------|----------|
| MVP | Linux only | Core rendering + AI streaming | 4–6 weeks |
| Beta | Linux + macOS | Cross-platform build validation | +2–3 weeks |
| GA | Linux + macOS + Windows | Full platform support | +4–6 weeks |

---

## Known Unknowns (from PRD Analysis)

| Unknown | Impact | Research Status |
|---------|--------|-----------------|
| Terminal rendering latency | FPS bottleneck | ⏳ Research-2 pending |
| Zig async/threading patterns | CLI-02 blocker | ⏳ Research-3 pending |
| Per-frame allocator cost | FPS bottleneck | ⏳ Research-4 pending |
| macOS/Windows build difficulty | Release timeline | ⏳ Research-5 pending |
| File watcher race conditions | Data integrity | ⏳ Research-6 pending |

---

## Success Criteria

1. ✅ Zig + Notcurses FFI proves viable (Research-1 DONE)
2. ⏳ 60+ FPS rendering baseline established (Research-2 pending)
3. ⏳ MPSC threading validated for AI streaming (Research-3 pending)
4. ⏳ Arena allocator overhead acceptable < 2ms/frame (Research-4 pending)
5. ⏳ Cross-platform build stable on Linux + macOS (Research-5 pending)
6. ⏳ File sync correctness proven (Research-6 pending)

---

**Last Updated:** April 8, 2026  
**Next Review:** After Research-2 (Performance Baseline) completion
