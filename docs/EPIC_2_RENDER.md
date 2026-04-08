# Epic 2: Rendering Pipeline & Notcurses Integration

**Objective:** Build a robust, flicker-free terminal rendering abstraction.

### Technical Requirements:
1.  **Notcurses Bridge:** Implement a `tse.render.Context` that wraps `notcurses_init` with custom signal handling for graceful shutdown.
2.  **Layered Rendering:** Support multi-plane rendering:
    - Plane 0: Background/Grid
    - Plane 1: Spatial Objects (Nodes/Graphs)
    - Plane 2: UI Overlays
3.  **Draw Commands:** Define a `CommandQueue` where the ECS pushes `DrawObject` requests (containing geometry, color, and glyph information).
4.  **Synchronization:** Implement a frame-buffer double-buffering scheme using Notcurses' `ncplane_erase` and `notcurses_render` to ensure frame consistency.

### Success Criteria:
- No visual tearing or flickering.
- Handling terminal resize events via `SIGWINCH` without crashing.
- Support for 24-bit TrueColor if the terminal capability allows.
