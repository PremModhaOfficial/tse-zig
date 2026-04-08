# Build Complexity: Cross-Platform Notcurses Linking

**Status:** ✅ COMPLETE  
**Last Updated:** April 8, 2026

## Objective
Analyze the complexity of building and linking Notcurses in a Zig project across Linux, macOS, and Windows, and determine a unified `build.zig` strategy.

## 1. Linux (Target Baseline)
- **Status:** Native & Stable.
- **Complexity:** Low.
- **Strategy:** Use `pkg-config` in `build.zig` to find `notcurses`, `ncursesw`, and `libunistring`.
- **Linking:** Dynamic linking is straightforward via `exe.linkSystemLibrary("notcurses")`.

## 2. macOS (Homebrew Support)
- **Status:** Supported via Homebrew.
- **Complexity:** Medium.
- **Strategy:** Must explicitly add Homebrew search paths (`/opt/homebrew/include` and `/opt/homebrew/lib`) in `build.zig`.
- **Issue:** macOS's `ncurses` is often outdated; linking against Homebrew's `ncursesw` is required for proper Unicode/Notcurses support.

## 3. Windows (The Major Barrier)
- **Status:** High Complexity / Unofficial.
- **Complexity:** Very High.
- **Constraints:**
  - Notcurses does not officially support MSVC.
  - Recommended environment: **MSYS2/UCRT64**.
- **Strategy:** Use a "Fat DLL" approach. Build Notcurses as a shared library in MSYS2 and link it as a pre-built binary in Zig.
- **Terminal Requirements:** Requires **Windows ConPTY** (Windows 10/11) and modern host (Microsoft Terminal).

## 4. Multimedia Dependencies (FFmpeg vs. OpenImageIO)
Notcurses relies on external libraries for image/video blitting.
- **Linux/macOS:** FFmpeg is the standard.
- **Windows:** OpenImageIO is often more compatible with native builds.
- **Recommendation:** Provide a build option in `build.zig` to disable multimedia if not needed, simplifying the dependency graph for minimal prototypes.

## 5. Unified `build.zig` Strategy
To keep the build process manageable:
1. **Dynamic Detection:** Use `step.target.os.tag` to switch linking logic.
2. **Pkg-Config Integration:** Use `std.Build.PkgConfig` for Linux/macOS.
3. **Pre-built Windows Binaries:** For Windows, bundle the required DLLs in a `libs/` directory for zero-config developer setup.

## 6. Summary Recommendation
The project should prioritize **Linux** for the initial prototype. Cross-platform support for macOS is feasible with minimal effort, while Windows should be treated as a secondary target requiring a bundled MSYS2-built DLL.
