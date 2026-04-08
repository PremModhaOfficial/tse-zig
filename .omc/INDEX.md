# Terminal Spatial Engine (Zig Edition) — Research & Validation Index

**Project Goal:** Validate and expand the PRD for a high-performance terminal rendering engine for spatial graphs.  
**Date Started:** April 8, 2026  
**Current Phase:** Technical Due Diligence & Gap Analysis  
**Status:** ✅ ALL RESEARCH COMPLETED

---

## Directory Structure

```
.omc/
├── INDEX.md                          # This file
├── FINDINGS.md                       # Executive summary of all findings
├── DECISION_LOG.md                   # Key decisions made during research
├── research/
│   ├── ZIG_NOTCURSES_INTEGRATION.md  # Zig + Notcurses FFI maturity study
│   ├── EVENT_DRIVEN_ARCHITECTURE.md  # Architecture pivot: Hybrid design
│   ├── PERFORMANCE_BASELINE.md       # 60+ FPS feasibility analysis
│   ├── ASYNC_THREADING.md            # Zig threading/MPSC patterns
│   ├── ARENA_ALLOCATOR.md            # Per-frame allocator overhead
│   ├── BUILD_COMPLEXITY.md           # Cross-platform build.zig analysis
│   ├── FILE_WATCHER_RACES.md         # Concurrent edit race conditions
│   └── CONCURRENCY_COROUTINES.md     # Async/Await vs. Threads analysis
├── state/
│   ├── session_notes.md              # Ongoing session notes
│   └── risk_matrix.md                # Implementation risks & blockers
└── references/
    ├── prd_summary.md                # PRD key requirements & claims
    └── tech_stack.md                 # Technology stack decisions
```

---

## Quick Navigation

### 📋 Starting Point
- **[FINDINGS.md](./FINDINGS.md)** — One-page executive summary of all validation work
- **[DECISION_LOG.md](./DECISION_LOG.md)** — Key decisions & trade-offs identified

### 🔬 Detailed Research Reports
- **[ZIG_NOTCURSES_INTEGRATION.md](./research/ZIG_NOTCURSES_INTEGRATION.md)** ✅ COMPLETE
  - Maturity of Zig + C FFI for Notcurses
  - Build patterns, known issues, cross-platform feasibility

- **[EVENT_DRIVEN_ARCHITECTURE.md](./research/EVENT_DRIVEN_ARCHITECTURE.md)** ✅ COMPLETE
  - Hybrid event-driven + capped frame loop
  - Hook system and render optimization strategies

- **[PERFORMANCE_BASELINE.md](./research/PERFORMANCE_BASELINE.md)** ✅ COMPLETE
  - 60+ FPS feasibility on large graphs
  - Terminal latency measurements

- **[ASYNC_THREADING.md](./research/ASYNC_THREADING.md)** ✅ COMPLETE
  - MPSC queue patterns in Zig
  - Thread safety for concurrent AI streaming

- **[ARENA_ALLOCATOR.md](./research/ARENA_ALLOCATOR.md)** ✅ COMPLETE
  - Per-frame deinit/reinit overhead quantification
  - Optimized `reset(.retain_capacity)` strategy

- **[BUILD_COMPLEXITY.md](./research/BUILD_COMPLEXITY.md)** ✅ COMPLETE
  - Cross-platform Notcurses linking (Linux, macOS, Windows)
  - Pkg-config and Homebrew integration

- **[FILE_WATCHER_RACES.md](./research/FILE_WATCHER_RACES.md)** ✅ COMPLETE
  - Concurrent JSON edit failure modes
  - Atomic Write-and-Rename synchronization

- **[CONCURRENCY_COROUTINES.md](./research/CONCURRENCY_COROUTINES.md)** ✅ COMPLETE
  - Async/Await status in Zig 0.13.0 vs 0.15.0
  - Transition to pluggable `std.Io` interface

### 📊 Risk Analysis
- **[risk_matrix.md](./state/risk_matrix.md)** — Implementation blockers, unknowns, PoC priorities

---

## Key Findings So Far

| Topic | Status | Finding |
|-------|--------|---------|
| Zig + Notcurses FFI | ✅ Complete | Proven & stable; requires Zig version pinning |
| 60+ FPS Performance | ✅ Complete | Highly feasible on Linux with Foot/Kitty |
| Async/Threading | ✅ Complete | Use MPSC (std.atomic.Queue) or lock-free ring buffers |
| Arena Allocator | ✅ Complete | Use reset(.retain_capacity) for per-frame O(1) performance |
| Cross-platform Build | ✅ Complete | Linux/macOS feasible; Windows requires MSYS2 |
| File Watcher Races | ✅ Complete | Use parent directory watch + atomic rename strategy |
| Concurrency Patterns| ✅ Complete | Use std.Thread.Pool (0.13.0); avoid native async |

---

## Next Steps

1. ✅ **DONE**: Technical due diligence & gap analysis
2. 🔄 **IN PROGRESS**: Initialize `build.zig` with platform linking
3. ⏳ **QUEUE**: Scaffold Core Engine with Arena pool
4. ⏳ **QUEUE**: Implement AI streaming MPSC backbone
