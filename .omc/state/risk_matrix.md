# Implementation Risk Matrix: Terminal Spatial Engine (Zig Edition)

**Date:** April 8, 2026  
**Scope:** Architecture and technical risks identified during PRD validation  
**Status:** Research 1/7 complete; risks identified; PoC priorities defined

---

## Risk Assessment Summary

| # | Risk | Category | Severity | Status | Blockers | PoC Needed |
|---|------|----------|----------|--------|----------|-----------|
| R1 | Zig version skew | Build | High | 🟡 MITIGATED | Dundalek build.zig outdated | No |
| R2 | 60+ FPS unproven | Performance | **CRITICAL** | 🔴 UNVALIDATED | Baseline measurements missing | **YES** |
| R3 | Threading unvalidated | Concurrency | **CRITICAL** | 🔴 UNVALIDATED | MPSC patterns, error handling TBD | **YES** |
| R4 | Arena overhead unknown | Memory | High | 🔴 UNVALIDATED | Per-frame cost unmeasured | **YES** |
| R5 | macOS/Windows build | Build | Medium | 🟡 UNVALIDATED | Platform-specific linking TBD | **YES** |
| R6 | File watcher races | Sync | Medium | 🟡 UNVALIDATED | Concurrent edit scenarios TBD | No |
| R7 | Notcurses FFI macro complexity | FFI | Medium | 🟢 MITIGATED | 99 macros; wrapping strategy known | No |
| R8 | UBSAN workaround needed | Safety | Medium | 🟢 MITIGATED | `disable_sanitize_c` documented | No |

---

## Detailed Risk Analysis

### 🔴 CRITICAL RISKS (Blockers for Architecture Approval)

---

#### R2: 60+ FPS Performance Unproven

**What's the Risk?**
- PRD claims "60+ FPS" but provides **no baseline measurements**
- Terminal rendering latency (kernel + network) may be the hard bottleneck
- Physics engine iterations may consume entire frame budget
- If actual performance < 30 FPS, architecture is rejected

**Why It Matters:**
- FPS is a primary UX constraint; core feature depends on it
- Architectural decisions (physics algorithm, render strategy, node count per frame) all depend on performance budget

**Current Status:**
- Unvalidated; assumption only

**What's Needed for PoC:**
1. Measure terminal I/O latency (syscall overhead)
2. Benchmark Notcurses Braille rendering per 100-node graph
3. Profile Fruchterman-Reingold iterations (ms per node)
4. Measure full frame latency: physics → render → display
5. Test on reference hardware (Linux, modern terminal emulator)

**Mitigation Strategy:**
- PoC 1: Minimal Zig + Notcurses hello-world → baseline terminal latency
- PoC 2: Add 100-node static graph rendering → measure Braille blitter cost
- PoC 3: Add physics engine → profile iteration time
- Go/No-Go decision: If cumulative < 16.67 ms (60 FPS), approve architecture; else redesign

**Owner:** Performance Lead  
**Target Completion:** 2 weeks (PoC phase)

**Risk Score:**
- **Impact**: 9/10 (architecture blocker)
- **Likelihood**: 7/10 (terminal latency may exceed budget)
- **Severity**: Critical

---

#### R3: Zig Async/Threading Unvalidated for AI Streaming

**What's the Risk?**
- PRD mentions `std.Thread.spawn()` for concurrent AI networking
- MPSC queue pattern not specified; Zig stdlib coverage unknown
- Thread panic handling / error isolation undefined
- libcurl integration (blocking vs. non-blocking) unspecified
- If no production MPSC pattern exists, must implement custom → high complexity + maintenance

**Why It Matters:**
- CLI-02 (AI streaming) is P0 feature; concurrent threads are architectural dependency
- Thread-safe communication is non-negotiable for renderer stability
- Wrong threading model can cause deadlocks, data races, or dropped AI responses

**Current Status:**
- Unvalidated; Zig ecosystem patterns unknown

**What's Needed for PoC:**
1. Research Zig production threading examples (GitHub, Discord, forums)
2. Evaluate MPSC implementations: stdlib, third-party, custom
3. Design error isolation (panic in AI thread ≠ crash renderer)
4. Test libcurl integration (async DNS, long-lived connections, timeouts)
5. Benchmark: message latency (AI response → renderer update) < 100ms

**Mitigation Strategy:**
- PoC 1: Spawn thread that sends integers over channel → measure latency
- PoC 2: Add libcurl in thread → verify DNS async, connection pooling
- PoC 3: Simulate AI streaming (mock responses) → validate error handling
- Go/No-Go decision: If message latency < 100ms and error handling robust, approve; else redesign

**Owner:** Concurrency Lead  
**Target Completion:** 2 weeks (PoC phase)

**Risk Score:**
- **Impact**: 8/10 (CLI-02 blocker)
- **Likelihood**: 6/10 (Zig ecosystem likely has patterns, but unconfirmed)
- **Severity**: Critical

---

### 🟡 HIGH RISKS (Architecture Impact)

---

#### R1: Zig Version Skew (Build Fragility)

**What's the Risk?**
- Dundalek example works on Zig 0.11–0.13; incompatibilities known for Zig 0.15+
- Zig is pre-1.0; breaking changes every 2–3 months
- Unpinned versions → build failures in CI, dependencies diverge over time
- Old build.zig becomes unmaintainable as Zig evolves

**Why It Matters:**
- Long-term maintainability; project must survive Zig version upgrades
- Contributors need stable build experience

**Current Status:**
- Mitigated by version pinning decision (Decision 4)

**Mitigation (Implemented):**
- ✅ Pin Zig to 0.13.0 for MVP
- ✅ Document in `build.zig.zon`
- ✅ Quarterly Zig release reviews (opt-in upgrades after testing)

**Owner:** Build System Lead  
**Status:** Recommendation accepted; pending implementation

**Risk Score:**
- **Impact**: 6/10 (delays project if broken)
- **Likelihood**: 8/10 (Zig evolves rapidly; breaking changes expected)
- **Severity**: High → Medium (mitigated by pinning)

---

#### R4: Arena Allocator Per-Frame Overhead

**What's the Risk?**
- PRD design: deinit/reinit arena every frame
- Cost of repeated allocation unknown; may violate 16.67ms frame budget
- Memory fragmentation may accumulate; GC patterns unclear
- Alternative strategies (arena pool, pre-allocated buffers) not explored

**Why It Matters:**
- Allocator performance directly impacts FPS
- If per-frame deinit/reinit costs > 2ms, frames drop below 60 FPS

**Current Status:**
- Unvalidated; theoretical design only

**What's Needed for PoC:**
1. Benchmark: Cost of allocating + deallocating 1000 node positions per frame
2. Measure fragmentation (heap size growth over 10,000 frames)
3. Compare: current arena strategy vs. pre-allocated buffer vs. arena pool
4. Profile: identify bottleneck (malloc/free syscalls vs. memory walks vs. other)

**Mitigation Strategy:**
- PoC 1: Create Arena, allocate 10KB, deinit, repeat 1000x → measure time
- PoC 2: Render loop with physics + allocations → profile under load
- Go/No-Go decision: If per-frame cost < 2ms, approve; else redesign (arena pool, pre-alloc)

**Owner:** Memory Lead  
**Target Completion:** 1 week (PoC phase)

**Risk Score:**
- **Impact**: 7/10 (FPS constraint)
- **Likelihood**: 6/10 (allocator overhead often underestimated)
- **Severity**: High

---

#### R7: Notcurses FFI Macro Complexity

**What's the Risk?**
- Notcurses exposes 99 macros; Zig `@cImport` translates simple ones, complex ones fail
- Some macros encode business logic; manual wrapping required
- Missed macros → API incompleteness; developer confusion

**Why It Matters:**
- FFI correctness is foundational; incomplete API blocks feature development

**Current Status:**
- Mitigated; Dundalek example demonstrates viable approach

**Mitigation (Implemented):**
- ✅ Wrapper module strategy: `notcurses.zig` re-exports C symbols + Zig-friendly defaults
- ✅ Document macro translation patterns
- ✅ Test coverage for common macros (color, blitter, alignment)

**Owner:** FFI Lead  
**Status:** Mitigation strategy known; pending implementation

**Risk Score:**
- **Impact**: 5/10 (API incomplete ≠ non-functional)
- **Likelihood**: 7/10 (macro complexity is common in C libraries)
- **Severity**: High → Medium (mitigation documented)

---

#### R8: UBSAN Workaround Required

**What's the Risk?**
- Notcurses has undefined behavior; compiler sanitizers catch it
- Dundalek example disables UBSAN (`disable_sanitize_c = true`)
- Hiding UB is a code smell; may mask real bugs

**Why It Matters:**
- Code quality/safety; UB can cause crashes, data corruption under load

**Current Status:**
- Mitigated; workaround documented

**Mitigation (Implemented):**
- ✅ Document why UBSAN must be disabled (Notcurses library limitation, not our code)
- ✅ Add comment in `build.zig` explaining the trade-off
- ✅ Consider Notcurses fork if UB becomes unmanageable

**Owner:** Build System Lead  
**Status:** Mitigation accepted; pending documentation

**Risk Score:**
- **Impact**: 4/10 (UB usually dormant)
- **Likelihood**: 3/10 (Notcurses is stable; UB hasn't caused reported crashes)
- **Severity**: High → Low (mitigated; accepted trade-off)

---

### 🟡 MEDIUM RISKS (Implementation Details)

---

#### R5: macOS/Windows Build Complexity

**What's the Risk?**
- Dundalek example works on Linux; macOS/Windows untested
- Notcurses packaging differs per platform (pkg-config, Homebrew, MSVC)
- Cross-platform `build.zig` is notoriously fragile
- Developer time spent on platform-specific workarounds

**Why It Matters:**
- Affects release timeline (MVP: Linux only; Phase 2: macOS; Phase 3: Windows)
- CI/CD complexity; maintenance burden

**Current Status:**
- Unvalidated; Phase 1 strategy: Linux only

**Mitigation Strategy (Decision 6):**
- Phase 1 (MVP): Linux only; no Windows support
- Phase 2 (Beta): macOS support validation; adjust `build.zig` for Homebrew
- Phase 3 (GA): Windows support (if demand justifies)

**Owner:** Build System Lead  
**Target Completion:** 1 week per platform (Phase 2/3)

**Risk Score:**
- **Impact**: 5/10 (delays cross-platform release)
- **Likelihood**: 7/10 (cross-platform builds are notoriously difficult)
- **Severity**: Medium

---

#### R6: File Watcher Race Conditions

**What's the Risk?**
- PRD mentions native OS file events (inotify, kqueue)
- Concurrent JSON edits during rendering not formally specified
- "Last Write Wins" sync strategy not detailed
- Race conditions possible: file modified during read, or renderer updates stale graph

**Why It Matters:**
- Data integrity; corrupted JSON can crash renderer
- Sync correctness; multiple editors conflict resolution unspecified

**Current Status:**
- Unvalidated; implementation strategy TBD

**What's Needed (Not PoC):**
1. Map failure scenarios (concurrent file modification + renderer read)
2. Formalize "Last Write Wins" semantics (file version tracking, timestamp-based)
3. Document inotify vs. kqueue differences (watching directories vs. files)
4. Design retry/recovery logic (corrupted JSON read handling)

**Mitigation Strategy:**
- Analysis (no PoC needed): Document failure scenarios + recovery strategy
- Implementation: Use file versioning (JSON version field) to detect conflicts
- Testing: Concurrency tests (modify file while renderer reads) → validate correctness

**Owner:** Sync Lead  
**Target Completion:** 1 week (analysis phase)

**Risk Score:**
- **Impact**: 4/10 (race condition is data loss/corruption risk)
- **Likelihood**: 4/10 (file watcher is mature; most OSes handle races correctly)
- **Severity**: Medium

---

## PoC Prioritization Matrix

| # | PoC | Priority | Effort | Blockers Resolved | Start Date |
|---|-----|----------|--------|-------------------|-----------|
| PoC-P1 | Performance baseline (60+ FPS) | P0 | 2 weeks | R2 | Week 1 |
| PoC-P2 | MPSC queues + threading | P0 | 2 weeks | R3 | Week 1 (parallel) |
| PoC-P3 | Arena allocator overhead | P0 | 1 week | R4 | Week 2 |
| PoC-P4 | macOS/Windows build | P1 | 1 week each | R5 | Phase 2 |
| Analysis-P5 | File watcher races | P2 | 1 week | R6 | Week 3 |

---

## Decision Gates

### Gate 1: Architecture Approval (After PoC-P1, PoC-P2, PoC-P3)
**Criteria:**
- ✅ 60+ FPS proven (R2 resolved)
- ✅ MPSC threading validated (R3 resolved)
- ✅ Arena overhead acceptable < 2ms/frame (R4 resolved)
- ✅ No blocking issues discovered

**Decision:** Approve or redesign architecture

### Gate 2: Cross-Platform Release (After PoC-P4)
**Criteria:**
- ✅ macOS build validated
- ✅ Windows build validated (if Phase 3)
- ✅ Platform-specific workarounds documented

**Decision:** Approve Phase 2/3 release

### Gate 3: Production Readiness (After all PoCs + analysis)
**Criteria:**
- ✅ All risks mitigated or accepted
- ✅ No unresolved blockers
- ✅ Testing strategy approved

**Decision:** Approve production deployment

---

## Accepted Risks (No Mitigation)

| Risk | Rationale |
|------|-----------|
| UBSAN disabled | Notcurses library limitation; UB is dormant and well-documented |
| Zig pre-1.0 | Accepted trade-off for performance + C-interop; version pinning mitigates |
| Windows Phase 3 | Lower priority; MVP focuses on Linux + macOS developer use case |

---

## Pending Decisions

| Decision | Prerequisite | Owner |
|----------|--------------|-------|
| Approve architecture | PoC-P1, P2, P3 results | Arch Lead |
| Proceed with Phase 2 | PoC-P4 results | Build Lead |
| Accept UBSAN workaround | Code review | Build Lead |

---

**Last Updated:** April 8, 2026  
**Next Review:** After PoC-P1, P2, P3 completion (Target: 3 weeks)
