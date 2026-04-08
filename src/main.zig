//! Terminal Spatial Engine - Main Entry Point
//! Event-driven architecture with hooks for high-performance terminal graph rendering.

const std = @import("std");
const event_queue = @import("event_queue.zig");
const hooks = @import("hooks.zig");

const Event = event_queue.Event;
const EventQueue = event_queue.EventQueue;
const HookRegistry = hooks.HookRegistry;

// Notcurses FFI
const nc = @cImport({
    @cInclude("notcurses/notcurses.h");
});

// =============================================================================
// Constants
// =============================================================================

const FRAME_NS: i128 = 16_666_666; // ~60 FPS cap
const EVENT_BATCH_SIZE: usize = 64;

// =============================================================================
// Application State
// =============================================================================

const AppState = struct {
    running: bool = true,
    needs_render: bool = true,
    physics_active: bool = false,

    // Timing
    last_render_ns: i128 = 0,
    frame_count: u64 = 0,

    // Notcurses
    ncs: ?*nc.notcurses = null,
    stdplane: ?*nc.ncplane = null,

    // Event system
    event_queue: *EventQueue,
    hook_registry: *HookRegistry,

    // Arena for per-frame allocations
    frame_arena: std.heap.ArenaAllocator,
};

// =============================================================================
// Signal Handling
// =============================================================================

var global_event_queue: ?*EventQueue = null;

fn signalHandler(sig: c_int) callconv(.c) void {
    if (global_event_queue) |queue| {
        const signal_event = switch (sig) {
            std.posix.SIG.INT => Event{ .system = .{ .signal = .sigint } },
            std.posix.SIG.TERM => Event{ .system = .{ .signal = .sigterm } },
            std.posix.SIG.WINCH => Event{ .system = .{ .signal = .sigwinch } },
            else => Event{ .system = .quit_requested },
        };
        _ = queue.push(signal_event);
    }
}

fn setupSignalHandlers(queue: *EventQueue) !void {
    global_event_queue = queue;

    const handler = std.posix.Sigaction{
        .handler = .{ .handler = signalHandler },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };

    std.posix.sigaction(std.posix.SIG.INT, &handler, null);
    std.posix.sigaction(std.posix.SIG.TERM, &handler, null);
    std.posix.sigaction(std.posix.SIG.WINCH, &handler, null);
}

// =============================================================================
// Notcurses Initialization
// =============================================================================

fn initNotcurses() !struct { ncs: *nc.notcurses, stdplane: *nc.ncplane } {
    var opts = std.mem.zeroes(nc.notcurses_options);
    opts.flags = nc.NCOPTION_SUPPRESS_BANNERS;

    const ncs = nc.notcurses_init(&opts, null) orelse {
        return error.NotcursesInitFailed;
    };

    const stdplane = nc.notcurses_stdplane(ncs) orelse {
        _ = nc.notcurses_stop(ncs);
        return error.StdplaneInitFailed;
    };

    return .{ .ncs = ncs, .stdplane = stdplane };
}

fn deinitNotcurses(ncs: *nc.notcurses) void {
    _ = nc.notcurses_stop(ncs);
}

// =============================================================================
// Core Event Handlers
// =============================================================================

fn handleQuitRequest(_: *Event, ctx: ?*anyopaque) hooks.HookResult {
    if (ctx) |c| {
        const state: *AppState = @ptrCast(@alignCast(c));
        state.running = false;
    }
    return .stop;
}

fn handleSignal(event: *Event, ctx: ?*anyopaque) hooks.HookResult {
    if (ctx) |c| {
        const state: *AppState = @ptrCast(@alignCast(c));
        if (event.* == .system) {
            switch (event.system) {
                .signal => |sig| switch (sig) {
                    .sigint, .sigterm => {
                        state.running = false;
                        return .stop;
                    },
                    .sigwinch => {
                        state.needs_render = true;
                        return .continue_;
                    },
                    else => {},
                },
                else => {},
            }
        }
    }
    return .continue_;
}

fn handleKeyPress(event: *Event, ctx: ?*anyopaque) hooks.HookResult {
    if (ctx) |c| {
        const state: *AppState = @ptrCast(@alignCast(c));
        if (event.* == .input) {
            switch (event.input) {
                .key_press => |key| {
                    // Quit on 'q' or Escape
                    if (key.key == .escape or (key.key == .char and key.char == 'q')) {
                        state.running = false;
                        return .stop;
                    }
                    state.needs_render = true;
                },
                else => {},
            }
        }
    }
    return .continue_;
}

// =============================================================================
// Render
// =============================================================================

fn render(state: *AppState) void {
    if (state.ncs == null or state.stdplane == null) return;

    const stdplane = state.stdplane.?;

    // Clear plane
    _ = nc.ncplane_erase(stdplane);

    // Get dimensions
    var rows: c_uint = 0;
    var cols: c_uint = 0;
    nc.ncplane_dim_yx(stdplane, &rows, &cols);

    // Draw frame counter (debug)
    _ = nc.ncplane_putstr_yx(stdplane, 0, 0, "Terminal Spatial Engine");

    var buf: [64]u8 = undefined;
    const frame_str = std.fmt.bufPrintZ(&buf, "Frame: {d}", .{state.frame_count}) catch "Frame: ???";
    _ = nc.ncplane_putstr_yx(stdplane, 1, 0, frame_str.ptr);

    const size_str = std.fmt.bufPrintZ(&buf, "Size: {d}x{d}", .{ cols, rows }) catch "Size: ???";
    _ = nc.ncplane_putstr_yx(stdplane, 2, 0, size_str.ptr);

    _ = nc.ncplane_putstr_yx(stdplane, 4, 0, "Press 'q' or Escape to quit");

    // Render to terminal
    _ = nc.notcurses_render(state.ncs.?);

    state.frame_count += 1;
}

// =============================================================================
// Event Loop
// =============================================================================

fn eventLoop(state: *AppState) !void {
    var event_batch: [EVENT_BATCH_SIZE]Event = undefined;

    while (state.running) {
        // 1. Drain all pending events (non-blocking)
        const drained = state.event_queue.drainInto(&event_batch);
        for (event_batch[0..drained]) |*event| {
            _ = state.hook_registry.dispatch(event);
        }

        // 2. Poll for Notcurses input (non-blocking)
        if (state.ncs) |ncs| {
            var ni: nc.ncinput = undefined;
            const key = nc.notcurses_get_nblock(ncs, &ni);
            if (key != 0 and key != @as(u32, @bitCast(@as(i32, -1)))) {
                const key_event = translateNotcursesInput(key, &ni);
                if (key_event) |ke| {
                    var event = Event{ .input = .{ .key_press = ke } };
                    _ = state.hook_registry.dispatch(&event);
                }
            }
        }

        // 3. Physics tick (if active) - placeholder
        if (state.physics_active) {
            var physics_event = Event{ .internal = .physics_tick };
            _ = state.hook_registry.dispatch(&physics_event);
            state.needs_render = true;
        }

        // 4. Render if dirty and frame interval elapsed
        const now = std.time.nanoTimestamp();
        if (state.needs_render and (now - state.last_render_ns >= FRAME_NS)) {
            // Reset frame arena
            _ = state.frame_arena.reset(.retain_capacity);

            render(state);
            state.last_render_ns = now;
            state.needs_render = false;
        }

        // 5. Sleep until next event or frame deadline
        const next_frame = state.last_render_ns + FRAME_NS;
        const sleep_ns = @max(0, next_frame - now);
        if (sleep_ns > 0) {
            const timeout = state.event_queue.waitWithTimeout(sleep_ns);
            if (timeout) |event| {
                _ = state.hook_registry.dispatch(@constCast(&event));
            }
        }
    }
}

fn translateNotcursesInput(key: u32, ni: *nc.ncinput) ?event_queue.KeyEvent {
    var ke = event_queue.KeyEvent{
        .key = .unknown,
        .char = null,
        .modifiers = .{
            .ctrl = (ni.modifiers & nc.NCKEY_MOD_CTRL) != 0,
            .alt = (ni.modifiers & nc.NCKEY_MOD_ALT) != 0,
            .shift = (ni.modifiers & nc.NCKEY_MOD_SHIFT) != 0,
            .super = (ni.modifiers & nc.NCKEY_MOD_SUPER) != 0,
        },
    };

    // Map special keys
    if (key == nc.NCKEY_ESC) {
        ke.key = .escape;
    } else if (key == nc.NCKEY_ENTER) {
        ke.key = .enter;
    } else if (key == nc.NCKEY_TAB) {
        ke.key = .tab;
    } else if (key == nc.NCKEY_BACKSPACE) {
        ke.key = .backspace;
    } else if (key == nc.NCKEY_DEL) {
        ke.key = .delete;
    } else if (key == nc.NCKEY_UP) {
        ke.key = .up;
    } else if (key == nc.NCKEY_DOWN) {
        ke.key = .down;
    } else if (key == nc.NCKEY_LEFT) {
        ke.key = .left;
    } else if (key == nc.NCKEY_RIGHT) {
        ke.key = .right;
    } else if (key == nc.NCKEY_HOME) {
        ke.key = .home;
    } else if (key == nc.NCKEY_END) {
        ke.key = .end;
    } else if (key == nc.NCKEY_PGUP) {
        ke.key = .page_up;
    } else if (key == nc.NCKEY_PGDOWN) {
        ke.key = .page_down;
    } else if (key < 0x110000) {
        // Unicode character
        ke.key = .char;
        ke.char = @intCast(key);
    } else {
        return null; // Unknown key
    }

    return ke;
}

// =============================================================================
// Main
// =============================================================================

pub fn main() !void {
    // Initialize allocators
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize event queue
    var queue = try EventQueue.init(allocator);
    defer queue.deinit();

    // Initialize hook registry
    var registry = HookRegistry.init(allocator);
    defer registry.deinit();

    // Initialize frame arena
    var frame_arena = std.heap.ArenaAllocator.init(allocator);
    defer frame_arena.deinit();

    // Initialize app state
    var state = AppState{
        .event_queue = &queue,
        .hook_registry = &registry,
        .frame_arena = frame_arena,
    };

    // Setup signal handlers
    try setupSignalHandlers(&queue);

    // Register core hooks
    _ = try hooks.hook(&registry)
        .forPhase(.on)
        .forSystem(.quit_requested)
        .register(handleQuitRequest, &state);

    _ = try hooks.hook(&registry)
        .forPhase(.on)
        .forSystem(.signal)
        .withPriority(-10) // High priority
        .register(handleSignal, &state);

    _ = try hooks.hook(&registry)
        .forPhase(.on)
        .forInput(.key_press)
        .register(handleKeyPress, &state);

    // Initialize Notcurses
    const nc_init = try initNotcurses();
    state.ncs = nc_init.ncs;
    state.stdplane = nc_init.stdplane;
    defer deinitNotcurses(nc_init.ncs);

    // Run event loop
    try eventLoop(&state);

    std.debug.print("Graceful shutdown complete.\n", .{});
}

// =============================================================================
// Tests
// =============================================================================

test "event_queue import" {
    _ = event_queue;
}

test "hooks import" {
    _ = hooks;
}
