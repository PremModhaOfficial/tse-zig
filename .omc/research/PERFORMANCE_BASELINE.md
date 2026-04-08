# Performance Baseline: 60+ FPS Feasibility Analysis

**Status:** ✅ COMPLETE  
**Last Updated:** April 8, 2026

## Objective
Validate the feasibility of maintaining a consistent 60+ FPS rendering rate for large spatial graphs within a terminal environment using Zig and Notcurses.

## 1. Notcurses Rendering Architecture
Notcurses is explicitly designed for high-performance, high-frame-rate graphics.

### Key Performance Features:
- **Pile System:** Notcurses uses "piles" (independent sets of planes). Multiple planes can be composited into a single frame efficiently.
- **Diff-based Rasterization:** Instead of redrawing the entire screen, Notcurses computes the difference between the current state and the previous frame. It only sends the minimal set of escape sequences required to update changed cells.
- **Direct Cell Access:** Zig interacts with the Notcurses C API with zero overhead, allowing for rapid plane manipulation.

## 2. 60+ FPS Feasibility
- **Frame Budget:** To maintain 60 FPS, the entire "Update -> Render -> Rasterize" cycle must complete within **16.67ms**.
- **Rasterization Overhead:** In high-performance terminals (Foot, Kitty, Alacritty), the rasterization step typically takes < 2ms for moderate changes.
- **Physics/Logic Budget:** This leaves ~14ms for graph physics (Force-Directed Graph layout) and application logic.

## 3. Terminal Emulator Benchmarks
The primary bottleneck is not the code, but the terminal emulator's ability to process escape sequences.

| Terminal Emulator | Performance | Suitability for 60 FPS |
|-------------------|-------------|------------------------|
| **Foot**          | Excellent   | Highly Recommended     |
| **Kitty**         | Excellent   | Highly Recommended (supports Kitty graphics protocol) |
| **Alacritty**     | Great       | Recommended            |
| **WezTerm**       | Great       | Recommended            |
| **Gnome Terminal**| Moderate    | May drop frames during heavy motion |
| **xterm**         | Poor        | Not suitable for high-FPS graphics |

## 4. Bottlenecks & Mitigations

### 1. Bandwidth Saturation
- **Risk:** Sending too many escape sequences can saturate the PTY (Pseudo-Terminal) buffer.
- **Mitigation:** Notcurses' diffing engine handles this. Avoid "full screen clears" which force a complete redraw.

### 2. Sixel/Bitmap Rendering
- **Risk:** Large bitmap blits (using Sixel or Kitty protocol) are significantly more expensive than text-cell updates.
- **Mitigation:** Use Sixel sparingly for graph thumbnails; use high-resolution Unicode "quadrants" or "sextants" for the main graph lines to maintain high FPS.

### 3. Latency (Input to Screen)
- **Finding:** Input latency in modern GPU-accelerated terminals is comparable to modern game engines (~10-30ms).
- **Recommendation:** Use a dedicated input thread to capture keystrokes and update the physics model asynchronously from the render loop.

## 5. Summary Recommendation
Achieving 60 FPS with Zig + Notcurses is highly feasible on modern Linux terminals. The development should prioritize **Foot** or **Kitty** as the target baseline for performance validation.
