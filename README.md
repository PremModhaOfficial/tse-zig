# nodepad (Terminal Spatial Engine - Zig Edition)

**A high-performance terminal rendering engine for spatial graphs.**

---

This is the Terminal Spatial Engine, an event-driven architecture with hooks for high-performance terminal graph rendering. This CLI tool is designed to visualize knowledge graphs with concurrent AI assistant interactions.

## Architecture & Features

- **Language:** Zig 0.14.0+
- **Rendering:** Notcurses for sub-pixel Braille blitting
- **Physics Engine:** Fruchterman-Reingold force-directed layout
- **Concurrency:** Hybrid event-driven + capped 60fps frame loop with MPSC queues
- **Memory Management:** Per-render arena allocator (`std.heap.ArenaAllocator`)
- **File Watching:** Native OS events (inotify/kqueue)

The engine uses an event queue (`src/event_queue.zig`) and a hook registry (`src/hooks.zig`) to handle high-performance updates cleanly and efficiently. A capped ~60FPS loop ensures it only renders when dirty, preserving battery and CPU resources.

## Quick Start

### Build & Run

**Prerequisites**:
- Zig `0.14.0` or newer
- `notcurses` installed on your system (e.g. `libnotcurses-dev` on Linux, `notcurses` via Homebrew on macOS)

```bash
# Build the engine
zig build

# Run it
zig build run

# Or just check if it compiles
zig build check
```

## Setup & Dependencies

| Platform | Dependency requirements |
|---|---|
| **Linux** | `pkg-config`, `libnotcurses-dev` |
| **macOS** | `pkg-config`, `notcurses` (via Homebrew) |
| **Windows** | Planned for Phase 3 (MSYS2 required) |

## Development

The architecture revolves around a main event loop (`src/main.zig`) handling an event batch from the `EventQueue`, translating inputs via the Notcurses API, and dispatching to registered hooks. Memory allocations per frame use an `ArenaAllocator` which resets efficiently (`.retain_capacity`).

- Event definitions: `src/event_queue.zig`
- Hook interface: `src/hooks.zig`
- Main loop and terminal UI: `src/main.zig`

---

## License

[MIT](LICENSE)
