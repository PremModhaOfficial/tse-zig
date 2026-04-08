# Event-Driven Architecture for Terminal Graph Renderer

Research document for Zig + Notcurses terminal graph renderer event system.

## 1. Recommended Architecture: Hybrid Event-Driven

### Decision: Event-Driven with Capped Frame Loop

For a terminal graph renderer with physics simulation, AI streaming, and file watching, **a hybrid approach is optimal**:

```
┌─────────────────────────────────────────────────────────────┐
│                    EVENT SOURCES                            │
├─────────────┬─────────────┬─────────────┬──────────────────┤
│  Terminal   │   Network   │    File     │     Timers       │
│   Input     │   (AI API)  │   Watcher   │   (Physics)      │
└──────┬──────┴──────┬──────┴──────┬──────┴────────┬─────────┘
       │             │             │               │
       ▼             ▼             ▼               ▼
┌─────────────────────────────────────────────────────────────┐
│              UNIFIED EVENT QUEUE (MPSC)                     │
│  [KeyPress] [MouseMove] [TokenChunk] [FileChange] [Tick]    │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    EVENT DISPATCHER                          │
│  • Prioritizes events (input > external > internal)         │
│  • Coalesces redundant events (multiple resizes → one)      │
│  • Fires hooks (pre-event, post-event)                      │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                  STATE UPDATE + DIRTY MARKING               │
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

### Why Hybrid Over Pure Event-Driven or Pure Frame Loop

| Approach | Pros | Cons | Best For |
|----------|------|------|----------|
| **Pure Event-Driven** | Zero CPU when idle, immediate response | Physics needs continuous ticks, can't batch renders efficiently | Static UIs, form apps |
| **Pure Frame Loop** | Predictable timing, smooth animation | Wastes CPU when idle, fixed latency | Games, continuous animation |
| **Hybrid (Recommended)** | Best of both: efficient when idle, smooth when active | More complex implementation | Physics + reactive UI |

### The Hybrid Pattern

```zig
const EventLoop = struct {
    // Event sources feed into this queue
    event_queue: EventQueue,
    
    // Physics needs regular ticks, but only when active
    physics_timer: ?Timer,
    
    // Render is capped to avoid wasted frames
    last_render_time: i64,
    min_frame_interval_ns: i64 = 16_666_666, // ~60fps cap
    
    // Dirty tracking
    needs_render: bool = false,
    
    pub fn run(self: *EventLoop) !void {
        while (self.running) {
            // 1. Collect all pending events (non-blocking drain)
            while (self.event_queue.tryPop()) |event| {
                self.handleEvent(event);
            }
            
            // 2. Physics tick if simulation is active
            if (self.physics_active) {
                self.physicsStep();
                self.needs_render = true;
            }
            
            // 3. Render if dirty AND frame interval elapsed
            const now = std.time.nanoTimestamp();
            if (self.needs_render and 
                now - self.last_render_time >= self.min_frame_interval_ns) 
            {
                self.render();
                self.last_render_time = now;
                self.needs_render = false;
            }
            
            // 4. Sleep until next event OR next frame deadline
            const sleep_until = self.calculateNextWakeup();
            self.event_queue.waitWithTimeout(sleep_until);
        }
    }
};
```

### How Terminal TUI Frameworks Handle This

**Ratatui (Rust)**:
- Event-driven with explicit `render()` calls
- User controls the loop; common pattern is polling with timeout
- No built-in dirty tracking - renders on every iteration

**Bubbletea (Go)** - Elm Architecture:
- Pure event-driven with message queue
- `Update(msg) -> (Model, Cmd)` returns new state
- `View(model) -> string` called after every Update
- Commands spawn async work that sends messages back
- Framework handles render batching internally

**Textual (Python)**:
- Reactive system with message bubbling
- Widgets mark themselves dirty via `refresh()`
- Central compositor batches renders
- Worker threads for async (AI streaming fits naturally)

**Notcurses Demos**:
- Typically use a main loop with `notcurses_get()` for input
- Explicit `notcurses_render()` calls
- Demo apps often frame-loop with sleep


## 2. Event Taxonomy for Terminal Graph Renderer

### Complete Event Type Hierarchy

```zig
pub const Event = union(enum) {
    // ═══════════════════════════════════════════════════════
    // INPUT EVENTS (from terminal)
    // ═══════════════════════════════════════════════════════
    input: InputEvent,
    
    // ═══════════════════════════════════════════════════════
    // EXTERNAL EVENTS (from outside the app)
    // ═══════════════════════════════════════════════════════
    external: ExternalEvent,
    
    // ═══════════════════════════════════════════════════════
    // INTERNAL EVENTS (from within the app)
    // ═══════════════════════════════════════════════════════
    internal: InternalEvent,
    
    // ═══════════════════════════════════════════════════════
    // SYSTEM EVENTS (from OS/runtime)
    // ═══════════════════════════════════════════════════════
    system: SystemEvent,
};

pub const InputEvent = union(enum) {
    // Keyboard
    key_press: KeyEvent,
    key_release: KeyEvent,     // Kitty keyboard protocol
    
    // Mouse
    mouse_move: MouseEvent,
    mouse_press: MouseEvent,
    mouse_release: MouseEvent,
    mouse_scroll: ScrollEvent,
    mouse_drag: MouseEvent,
    
    // Touch (future-proofing)
    touch_start: TouchEvent,
    touch_move: TouchEvent,
    touch_end: TouchEvent,
};

pub const KeyEvent = struct {
    key: Key,                  // Logical key (e.g., .up, .enter, .char)
    char: ?u21 = null,         // Unicode codepoint if printable
    modifiers: Modifiers,      // Ctrl, Alt, Shift, Super
    
    pub const Modifiers = packed struct {
        ctrl: bool = false,
        alt: bool = false,
        shift: bool = false,
        super: bool = false,
    };
};

pub const MouseEvent = struct {
    x: u16,                    // Cell column
    y: u16,                    // Cell row
    pixel_x: ?u16 = null,      // Sub-cell precision if available
    pixel_y: ?u16 = null,
    button: MouseButton,
    modifiers: KeyEvent.Modifiers,
};

pub const ExternalEvent = union(enum) {
    // AI/Network
    ai_token: AITokenEvent,
    ai_complete: AICompleteEvent,
    ai_error: AIErrorEvent,
    
    // File watching
    file_changed: FileChangeEvent,
    file_created: FileChangeEvent,
    file_deleted: FileChangeEvent,
    
    // IPC (if supporting external control)
    ipc_message: IPCMessage,
};

pub const AITokenEvent = struct {
    stream_id: u32,
    token: []const u8,
    is_complete: bool = false,
};

pub const FileChangeEvent = struct {
    path: []const u8,
    kind: enum { modified, created, deleted, renamed },
    timestamp: i64,
};

pub const InternalEvent = union(enum) {
    // Physics simulation
    physics_tick: void,
    physics_settled: void,        // Graph has stopped moving
    physics_started: void,        // Graph started animating
    
    // Animation
    animation_frame: AnimationFrame,
    animation_complete: u32,      // Animation ID
    
    // Graph state changes
    node_added: NodeId,
    node_removed: NodeId,
    edge_added: EdgeId,
    edge_removed: EdgeId,
    selection_changed: []const NodeId,
    
    // Navigation
    viewport_changed: Viewport,
    zoom_changed: f32,
    
    // UI state
    focus_changed: ?WidgetId,
    mode_changed: Mode,           // Normal, Insert, Command, etc.
};

pub const SystemEvent = union(enum) {
    // Terminal
    resize: ResizeEvent,
    focus_gained: void,
    focus_lost: void,
    
    // Signals
    signal: Signal,
    
    // Lifecycle
    quit_requested: void,
    suspend_requested: void,      // Ctrl+Z
    resume: void,                 // fg from shell
};

pub const ResizeEvent = struct {
    cols: u16,
    rows: u16,
    pixel_width: ?u16 = null,
    pixel_height: ?u16 = null,
};

pub const Signal = enum {
    sigint,      // Ctrl+C
    sigterm,     // Kill request
    sigwinch,    // Resize (handled via ResizeEvent usually)
    sigtstp,     // Ctrl+Z
    sigcont,     // Resume
    sighup,      // Terminal closed
};
```

### Event Priority Ordering

```zig
pub const EventPriority = enum(u8) {
    // Highest priority - must be handled immediately
    system = 0,      // Signals, quit requests
    
    // High priority - user expects immediate feedback
    input = 1,       // Keyboard, mouse
    
    // Normal priority - external updates
    external = 2,    // File changes, AI tokens
    
    // Lower priority - can be batched/coalesced
    internal = 3,    // Physics ticks, animations
    
    // Lowest - purely cosmetic
    cosmetic = 4,    // Cursor blink, subtle animations
};
```


## 3. Event Loop Patterns in Zig

### Option A: libxev (Recommended for Production)

[libxev](https://github.com/mitchellh/libxev) is the mature choice for Zig event loops:

```zig
const xev = @import("xev");

pub const Reactor = struct {
    loop: xev.Loop,
    
    // File descriptors we're watching
    stdin_fd: std.posix.fd_t,
    file_watcher_fd: std.posix.fd_t,
    ai_socket_fd: std.posix.fd_t,
    
    // Completions for each watch
    stdin_completion: xev.Completion = undefined,
    file_completion: xev.Completion = undefined,
    socket_completion: xev.Completion = undefined,
    timer_completion: xev.Completion = undefined,
    
    pub fn init() !Reactor {
        var loop = try xev.Loop.init(.{});
        
        return .{
            .loop = loop,
            .stdin_fd = std.io.getStdIn().handle,
            // ... other fds
        };
    }
    
    pub fn run(self: *Reactor) !void {
        // Register stdin for reading (terminal input)
        var stdin_read = try xev.Read.init();
        stdin_read.run(&self.loop, &self.stdin_completion, 
            self.stdin_fd, &self.buffer, self, onStdinReady);
        
        // Register timer for physics (16ms = 60fps)
        var physics_timer = try xev.Timer.init();
        physics_timer.run(&self.loop, &self.timer_completion, 
            16, self, onPhysicsTick);
        
        // Run until done
        try self.loop.run(.until_done);
    }
    
    fn onStdinReady(
        self: *Reactor,
        loop: *xev.Loop,
        completion: *xev.Completion,
        result: xev.Read.ReadError!usize
    ) xev.CallbackAction {
        const bytes_read = result catch |err| {
            // Handle error
            return .disarm;
        };
        
        // Parse terminal input and dispatch events
        self.parseInput(self.buffer[0..bytes_read]);
        
        // Re-arm for next read
        return .rearm;
    }
    
    fn onPhysicsTick(
        self: *Reactor,
        loop: *xev.Loop,
        completion: *xev.Completion,
        result: xev.Timer.RunError!void
    ) xev.CallbackAction {
        self.dispatchEvent(.{ .internal = .physics_tick });
        
        // Continue ticking while physics is active
        if (self.physics_active) {
            return .rearm;
        }
        return .disarm;
    }
};
```

### Option B: Direct epoll/io_uring (Lower Level)

For maximum control and minimal dependencies:

```zig
const std = @import("std");
const linux = std.os.linux;

pub const RawEventLoop = struct {
    epoll_fd: i32,
    
    pub fn init() !RawEventLoop {
        const fd = try std.posix.epoll_create1(0);
        return .{ .epoll_fd = fd };
    }
    
    pub fn addFd(self: *RawEventLoop, fd: i32, data: *anyopaque) !void {
        var event = linux.epoll_event{
            .events = linux.EPOLL.IN | linux.EPOLL.ET,
            .data = .{ .ptr = @intFromPtr(data) },
        };
        try std.posix.epoll_ctl(self.epoll_fd, linux.EPOLL.CTL_ADD, fd, &event);
    }
    
    pub fn wait(self: *RawEventLoop, timeout_ms: i32) ![]linux.epoll_event {
        var events: [64]linux.epoll_event = undefined;
        const count = try std.posix.epoll_wait(self.epoll_fd, &events, timeout_ms);
        return events[0..count];
    }
    
    // Main loop integrating all sources
    pub fn run(self: *RawEventLoop, app: *App) !void {
        while (app.running) {
            // Calculate timeout based on next scheduled event
            const timeout = app.nextDeadline() orelse -1;
            
            const ready = try self.wait(timeout);
            
            for (ready) |event| {
                const source: *EventSource = @ptrFromInt(event.data.ptr);
                try source.handle(app);
            }
            
            // Process any timer events that fired
            app.processTimers();
            
            // Render if needed
            if (app.needsRender()) {
                try app.render();
            }
        }
    }
};
```

### Multiplexing Pattern: Terminal + File + Network

```zig
pub const MultiplexedLoop = struct {
    // Event sources
    terminal: TerminalInput,      // stdin + notcurses
    file_watcher: FileWatcher,    // inotify on Linux
    ai_client: AIStreamClient,    // TCP/WebSocket
    
    // Unified queue (thread-safe for AI responses)
    queue: MpscQueue(Event),
    
    pub fn run(self: *MultiplexedLoop) !void {
        // All sources share the same epoll
        const epoll_fd = try std.posix.epoll_create1(0);
        defer std.posix.close(epoll_fd);
        
        // Register sources
        try self.terminal.register(epoll_fd);
        try self.file_watcher.register(epoll_fd);
        try self.ai_client.register(epoll_fd);
        
        // Also register the queue's eventfd for cross-thread wakeup
        try self.queue.register(epoll_fd);
        
        while (self.running) {
            var events: [32]linux.epoll_event = undefined;
            const count = std.posix.epoll_wait(epoll_fd, &events, 
                self.calculateTimeout());
            
            for (events[0..count]) |ev| {
                switch (ev.data.fd) {
                    self.terminal.fd => self.handleTerminalInput(),
                    self.file_watcher.fd => self.handleFileEvent(),
                    self.ai_client.fd => self.handleAIData(),
                    self.queue.eventfd => self.drainQueue(),
                    else => {},
                }
            }
            
            self.tick();
        }
    }
};
```

### Avoiding Busy-Waiting

Key strategies:

1. **Use blocking syscalls with timeout**: `epoll_wait(timeout)` not `poll()` in a loop
2. **Timer coalescing**: Combine multiple timers into next-deadline calculation
3. **Event coalescing**: Don't wake for every physics tick if we're already rendering

```zig
fn calculateTimeout(self: *Loop) i32 {
    const now = std.time.milliTimestamp();
    
    var next_deadline: ?i64 = null;
    
    // Physics needs tick?
    if (self.physics_active) {
        const physics_deadline = self.last_physics_tick + 16;
        next_deadline = physics_deadline;
    }
    
    // Animation frame pending?
    if (self.has_animations) {
        const anim_deadline = self.last_render + 16;
        next_deadline = @min(next_deadline orelse anim_deadline, anim_deadline);
    }
    
    // No deadline = block indefinitely
    if (next_deadline) |deadline| {
        return @max(0, @as(i32, @intCast(deadline - now)));
    }
    return -1; // Block forever until event
}
```


## 4. Hook/Handler System Design

### Recommended: Subscription Model with Phases

```zig
pub const HookPhase = enum {
    before,    // Pre-processing, can cancel
    on,        // Main handling
    after,     // Post-processing, cleanup
};

pub const HookResult = enum {
    continue_,      // Process next hook
    stop,           // Stop processing this event (handled)
    cancel,         // Cancel the event entirely (only in .before phase)
};

pub const HookRegistry = struct {
    // Type-erased handler storage
    handlers: std.ArrayList(Handler),
    
    const Handler = struct {
        phase: HookPhase,
        priority: i32,            // Lower = earlier
        event_filter: EventFilter, // Which events to receive
        callback: *const fn(*Event, *anyopaque) HookResult,
        context: *anyopaque,
    };
    
    pub fn register(
        self: *HookRegistry,
        comptime phase: HookPhase,
        filter: EventFilter,
        callback: anytype,
        context: anytype,
    ) !HookHandle {
        try self.handlers.append(.{
            .phase = phase,
            .priority = 0,
            .event_filter = filter,
            .callback = @ptrCast(callback),
            .context = @ptrCast(context),
        });
        
        // Keep sorted by phase then priority
        std.sort.sort(Handler, self.handlers.items, {}, lessThan);
        
        return .{ .index = self.handlers.items.len - 1 };
    }
    
    pub fn dispatch(self: *HookRegistry, event: *Event) bool {
        // Before phase - can cancel
        for (self.handlers.items) |handler| {
            if (handler.phase != .before) break;
            if (!handler.event_filter.matches(event)) continue;
            
            switch (handler.callback(event, handler.context)) {
                .cancel => return false, // Event cancelled
                .stop => break,
                .continue_ => {},
            }
        }
        
        // On phase - main handling
        for (self.handlers.items) |handler| {
            if (handler.phase != .on) continue;
            if (!handler.event_filter.matches(event)) continue;
            
            switch (handler.callback(event, handler.context)) {
                .stop => break,
                else => {},
            }
        }
        
        // After phase - cleanup
        for (self.handlers.items) |handler| {
            if (handler.phase != .after) continue;
            if (!handler.event_filter.matches(event)) continue;
            
            _ = handler.callback(event, handler.context);
        }
        
        return true;
    }
};
```

### Middleware Chain Pattern (Alternative)

Inspired by Express.js/Koa:

```zig
pub const Middleware = struct {
    handler: *const fn(*Context, NextFn) anyerror!void,
    
    pub const NextFn = *const fn() anyerror!void;
};

pub const Context = struct {
    event: *Event,
    state: *AppState,
    
    // Middleware can store data for downstream
    locals: std.StringHashMap(*anyopaque),
    
    // Control flow
    handled: bool = false,
    cancelled: bool = false,
    
    pub fn markHandled(self: *Context) void {
        self.handled = true;
    }
};

pub const MiddlewareStack = struct {
    middlewares: std.ArrayList(Middleware),
    
    pub fn use(self: *MiddlewareStack, handler: Middleware) !void {
        try self.middlewares.append(handler);
    }
    
    pub fn dispatch(self: *MiddlewareStack, ctx: *Context) !void {
        var index: usize = 0;
        
        const runNext = struct {
            fn run(stack: *MiddlewareStack, c: *Context, idx: *usize) !void {
                if (idx.* >= stack.middlewares.items.len) return;
                if (c.cancelled) return;
                
                const middleware = stack.middlewares.items[idx.*];
                idx.* += 1;
                
                try middleware.handler(c, struct {
                    fn next() !void {
                        try run(stack, c, idx);
                    }
                }.next);
            }
        }.run;
        
        try runNext(self, ctx, &index);
    }
};

// Usage example:
fn loggingMiddleware(ctx: *Context, next: MiddlewareStack.NextFn) !void {
    const start = std.time.milliTimestamp();
    log.debug("Event: {}", .{ctx.event});
    
    try next(); // Call next middleware
    
    const elapsed = std.time.milliTimestamp() - start;
    log.debug("Handled in {}ms", .{elapsed});
}

fn inputMiddleware(ctx: *Context, next: MiddlewareStack.NextFn) !void {
    switch (ctx.event.*) {
        .input => |input| {
            // Handle input, possibly mark as handled
            ctx.markHandled();
        },
        else => try next(), // Pass to next middleware
    }
}
```

### Specific Hooks for Render Pipeline

```zig
pub const RenderHooks = struct {
    // Called before any rendering starts
    before_render: HookList(*RenderContext),
    
    // Called after render buffer is built but before rasterization
    after_render: HookList(*RenderContext),
    
    // Called after rasterization to terminal
    after_rasterize: HookList(*RenderStats),
    
    // Called when a node is about to be drawn
    before_node_render: HookList(*NodeRenderContext),
    
    // Called after node is drawn
    after_node_render: HookList(*NodeRenderContext),
};

pub const RenderContext = struct {
    pile: *nc.Pile,
    viewport: Viewport,
    dirty_regions: []Region,
    frame_number: u64,
};

// Example: Debug overlay hook
fn debugOverlayHook(ctx: *RenderContext) HookResult {
    // Draw FPS counter, memory stats, etc. on top layer
    const overlay = ctx.pile.create_plane(.{
        .rows = 3,
        .cols = 40,
        .y = 0,
        .x = 0,
    });
    
    overlay.printf("FPS: {d:.1} | Nodes: {}", .{
        ctx.stats.fps,
        ctx.graph.node_count,
    });
    
    return .continue_;
}
```


## 5. Render Optimization Strategy

### Notcurses' Built-in Optimization

From the `notcurses_render(3)` man page, Notcurses already provides:

1. **Damage tracking**: `ncpile_render()` + `ncpile_rasterize()` are separate
2. **Optimized escape sequences**: Generates minimal terminal output
3. **Concurrent rendering**: Multiple piles can render concurrently
4. **Cell-level composition**: Z-ordered plane compositing

### Additional Dirty Tracking Strategy

```zig
pub const DirtyTracker = struct {
    // Bit flags for what changed
    flags: DirtyFlags = .{},
    
    // Specific dirty regions (for partial updates)
    dirty_regions: std.ArrayList(Region),
    
    // Per-node dirty state
    node_dirty: std.AutoHashMap(NodeId, DirtyFlags),
    
    pub const DirtyFlags = packed struct {
        // Layout changed (positions, sizes)
        layout: bool = false,
        
        // Content changed (labels, values)
        content: bool = false,
        
        // Style changed (colors, borders)
        style: bool = false,
        
        // Viewport changed (scroll, zoom)
        viewport: bool = false,
        
        // Full repaint needed
        full: bool = false,
        
        pub fn any(self: DirtyFlags) bool {
            return @as(u8, @bitCast(self)) != 0;
        }
        
        pub fn merge(self: *DirtyFlags, other: DirtyFlags) void {
            self.* = @bitCast(@as(u8, @bitCast(self.*)) | @as(u8, @bitCast(other)));
        }
    };
    
    pub fn markNodeDirty(self: *DirtyTracker, id: NodeId, what: DirtyFlags) void {
        const entry = self.node_dirty.getOrPut(id) catch return;
        if (entry.found_existing) {
            entry.value_ptr.merge(what);
        } else {
            entry.value_ptr.* = what;
        }
        self.flags.merge(what);
    }
    
    pub fn clear(self: *DirtyTracker) void {
        self.flags = .{};
        self.node_dirty.clearRetainingCapacity();
        self.dirty_regions.clearRetainingCapacity();
    }
    
    pub fn needsRender(self: *DirtyTracker) bool {
        return self.flags.any();
    }
};
```

### Layered Rendering for Efficiency

```zig
pub const LayeredRenderer = struct {
    notcurses: *nc.Context,
    
    // Separate planes for different update frequencies
    background_plane: *nc.Plane,    // Rarely changes (grid, background)
    graph_plane: *nc.Plane,         // Changes with physics
    ui_plane: *nc.Plane,            // Overlays, panels
    cursor_plane: *nc.Plane,        // Changes every frame
    
    pub fn render(self: *LayeredRenderer, dirty: *DirtyTracker) !void {
        // Only update planes that changed
        if (dirty.flags.full) {
            try self.renderBackground();
            try self.renderGraph();
            try self.renderUI();
        } else {
            if (dirty.flags.layout or dirty.flags.content) {
                try self.renderGraph();
            }
            if (dirty.flags.style) {
                try self.renderUI();
            }
        }
        
        // Cursor always updates (cheap)
        try self.renderCursor();
        
        // Let Notcurses composite and output
        _ = nc.ncpile_render(self.background_plane);
        _ = nc.ncpile_rasterize(self.background_plane);
        
        dirty.clear();
    }
    
    fn renderGraph(self: *LayeredRenderer) !void {
        // Clear only the graph plane
        self.graph_plane.erase();
        
        // Only render visible nodes
        for (self.viewport.visibleNodes()) |node| {
            self.renderNode(node);
        }
        
        // Render visible edges
        for (self.viewport.visibleEdges()) |edge| {
            self.renderEdge(edge);
        }
    }
};
```

### Frame Skipping for Consistency

```zig
pub const FrameScheduler = struct {
    target_fps: u32 = 60,
    frame_budget_ns: i128,
    last_frame_time: i128 = 0,
    
    // Track if we're falling behind
    frames_behind: u32 = 0,
    
    pub fn init(target_fps: u32) FrameScheduler {
        return .{
            .target_fps = target_fps,
            .frame_budget_ns = @divFloor(1_000_000_000, target_fps),
        };
    }
    
    pub fn shouldRender(self: *FrameScheduler) bool {
        const now = std.time.nanoTimestamp();
        const elapsed = now - self.last_frame_time;
        
        if (elapsed >= self.frame_budget_ns) {
            // Calculate how many frames we missed
            self.frames_behind = @intCast(@divFloor(elapsed, self.frame_budget_ns) - 1);
            self.last_frame_time = now;
            return true;
        }
        return false;
    }
    
    pub fn timeUntilNextFrame(self: *FrameScheduler) i64 {
        const now = std.time.nanoTimestamp();
        const elapsed = now - self.last_frame_time;
        const remaining = self.frame_budget_ns - elapsed;
        return @max(0, @as(i64, @intCast(@divFloor(remaining, 1_000_000))));
    }
};
```

### Event Coalescing

```zig
pub const EventCoalescer = struct {
    // Track pending events that can be merged
    pending_resize: ?ResizeEvent = null,
    pending_mouse_move: ?MouseEvent = null,
    physics_ticks_pending: u32 = 0,
    
    pub fn push(self: *EventCoalescer, event: Event) void {
        switch (event) {
            // Resize events: only latest matters
            .system => |sys| switch (sys) {
                .resize => |r| self.pending_resize = r,
                else => self.immediate_queue.push(event),
            },
            
            // Mouse moves: only latest position matters
            .input => |inp| switch (inp) {
                .mouse_move => |m| self.pending_mouse_move = m,
                else => self.immediate_queue.push(event),
            },
            
            // Physics ticks: count but don't queue each one
            .internal => |int| switch (int) {
                .physics_tick => self.physics_ticks_pending += 1,
                else => self.immediate_queue.push(event),
            },
            
            else => self.immediate_queue.push(event),
        }
    }
    
    pub fn drain(self: *EventCoalescer) EventIterator {
        // Yield coalesced events then immediate queue
        return .{
            .coalescer = self,
            .phase = .coalesced,
        };
    }
};
```


## 6. Zig Implementation Patterns

### Standard Library Tools

```zig
// Event queue - use std.fifo for single-threaded, or thread-safe queue
const std = @import("std");

// Single-threaded FIFO
const EventFifo = std.fifo.LinearFifo(Event, .Dynamic);

// Thread-safe for cross-thread event posting (AI responses)
const ThreadSafeQueue = struct {
    mutex: std.Thread.Mutex = .{},
    items: std.ArrayList(Event),
    eventfd: std.os.fd_t,  // For waking epoll
    
    pub fn push(self: *ThreadSafeQueue, event: Event) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try self.items.append(event);
        
        // Wake up the event loop
        _ = try std.os.write(self.eventfd, &[_]u8{1, 0, 0, 0, 0, 0, 0, 0});
    }
    
    pub fn drain(self: *ThreadSafeQueue, out: *std.ArrayList(Event)) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        out.appendSlice(self.items.items) catch {};
        self.items.clearRetainingCapacity();
    }
};

// Timers using std.time
const Timer = struct {
    deadline: i128,
    callback: *const fn(*Timer) void,
    
    pub fn schedule(delay_ms: u64) Timer {
        return .{
            .deadline = std.time.nanoTimestamp() + delay_ms * 1_000_000,
            .callback = undefined,
        };
    }
    
    pub fn expired(self: *Timer) bool {
        return std.time.nanoTimestamp() >= self.deadline;
    }
};

// Timer wheel for many timers
const TimerWheel = struct {
    // 256 slots, 16ms resolution = ~4 second wheel
    slots: [256]std.ArrayList(*Timer),
    current_slot: u8 = 0,
    last_tick: i128,
    
    pub fn advance(self: *TimerWheel) []const *Timer {
        const now = std.time.nanoTimestamp();
        const elapsed_ms = @divFloor(now - self.last_tick, 1_000_000);
        const slots_to_advance = @min(elapsed_ms / 16, 256);
        
        var expired = std.ArrayList(*Timer).init(allocator);
        
        for (0..slots_to_advance) |_| {
            for (self.slots[self.current_slot].items) |timer| {
                if (timer.expired()) {
                    expired.append(timer) catch {};
                }
            }
            self.current_slot +%= 1;
        }
        
        self.last_tick = now;
        return expired.items;
    }
};
```

### Integrating with Notcurses

```zig
const nc = @cImport({
    @cInclude("notcurses/notcurses.h");
});

pub const NotcursesEventLoop = struct {
    nctx: *nc.notcurses,
    event_queue: EventQueue,
    running: bool = true,
    
    pub fn init() !NotcursesEventLoop {
        var opts = nc.notcurses_options{
            .flags = nc.NCOPTION_SUPPRESS_BANNERS,
        };
        
        const nctx = nc.notcurses_init(&opts, null) orelse 
            return error.NotcursesInitFailed;
        
        // Enable mouse
        _ = nc.notcurses_mice_enable(nctx, nc.NCMICE_ALL_EVENTS);
        
        return .{
            .nctx = nctx,
            .event_queue = EventQueue.init(),
        };
    }
    
    pub fn pollInput(self: *NotcursesEventLoop, timeout_ms: i32) ?Event {
        var ni: nc.ncinput = undefined;
        
        // notcurses_get returns input with timeout
        const ch = nc.notcurses_get(self.nctx, 
            if (timeout_ms < 0) null else &.{ .tv_sec = 0, .tv_nsec = timeout_ms * 1_000_000 },
            &ni);
        
        if (ch == 0) return null;  // Timeout
        if (ch == @as(u32, @bitCast(@as(i32, -1)))) return null;  // Error
        
        // Convert to our event type
        return self.convertInput(ch, &ni);
    }
    
    fn convertInput(self: *NotcursesEventLoop, ch: u32, ni: *nc.ncinput) Event {
        // Check for mouse events
        if (ni.evtype != nc.NCTYPE_UNKNOWN) {
            return .{ .input = .{
                .mouse_move = .{
                    .x = @intCast(ni.x),
                    .y = @intCast(ni.y),
                    .button = convertButton(ni.id),
                    .modifiers = convertModifiers(ni),
                },
            }};
        }
        
        // Keyboard event
        return .{ .input = .{
            .key_press = .{
                .key = convertKey(ch),
                .char = if (ch < 0x110000) @intCast(ch) else null,
                .modifiers = convertModifiers(ni),
            },
        }};
    }
    
    pub fn run(self: *NotcursesEventLoop, app: *App) !void {
        while (self.running) {
            // 1. Poll for input with frame-budget timeout
            const timeout = app.frameScheduler.timeUntilNextFrame();
            if (self.pollInput(@intCast(timeout))) |event| {
                app.handleEvent(event);
            }
            
            // 2. Process any queued events (from other threads)
            while (self.event_queue.tryPop()) |event| {
                app.handleEvent(event);
            }
            
            // 3. Physics tick if needed
            if (app.physics_active) {
                app.physicsStep();
            }
            
            // 4. Render if dirty and frame budget allows
            if (app.dirty.needsRender() and app.frameScheduler.shouldRender()) {
                try app.render(self.nctx);
            }
        }
    }
};
```

### File Watching with inotify

```zig
const linux = std.os.linux;

pub const FileWatcher = struct {
    inotify_fd: i32,
    watches: std.AutoHashMap(i32, []const u8),
    
    pub fn init() !FileWatcher {
        const fd = try std.posix.inotify_init1(linux.IN.NONBLOCK);
        return .{
            .inotify_fd = fd,
            .watches = std.AutoHashMap(i32, []const u8).init(allocator),
        };
    }
    
    pub fn watchFile(self: *FileWatcher, path: []const u8) !void {
        const wd = try std.posix.inotify_add_watch(
            self.inotify_fd,
            path,
            linux.IN.MODIFY | linux.IN.CREATE | linux.IN.DELETE,
        );
        try self.watches.put(wd, path);
    }
    
    pub fn readEvents(self: *FileWatcher) ![]FileChangeEvent {
        var buf: [4096]u8 = undefined;
        const bytes = std.posix.read(self.inotify_fd, &buf) catch |err| {
            if (err == error.WouldBlock) return &[_]FileChangeEvent{};
            return err;
        };
        
        var events = std.ArrayList(FileChangeEvent).init(allocator);
        var offset: usize = 0;
        
        while (offset < bytes) {
            const event: *linux.inotify_event = @ptrCast(@alignCast(&buf[offset]));
            
            if (self.watches.get(event.wd)) |path| {
                try events.append(.{
                    .path = path,
                    .kind = convertMask(event.mask),
                    .timestamp = std.time.timestamp(),
                });
            }
            
            offset += @sizeOf(linux.inotify_event) + event.len;
        }
        
        return events.items;
    }
};
```


## 7. Trade-offs Analysis

### What We Gain

| Benefit | Description |
|---------|-------------|
| **Responsiveness** | Input handled immediately, not waiting for next frame |
| **Efficiency** | Zero CPU when idle (no spinning frame loop) |
| **Scalability** | Handle thousands of concurrent events (AI streams, file watches) |
| **Predictability** | Capped frame rate prevents overloading terminal |
| **Testability** | Events can be recorded/replayed for debugging |
| **Extensibility** | Hook system allows plugins without modifying core |

### What We Lose

| Cost | Description | Mitigation |
|------|-------------|------------|
| **Complexity** | More moving parts than simple loop | Good abstractions, clear ownership |
| **Debugging** | Async flow harder to trace | Event logging, deterministic replay |
| **Latency variance** | Event queue adds variable latency | Priority queue, bypass for input |
| **Memory** | Event objects need allocation | Arena allocator, event pooling |
| **Learning curve** | Team needs to understand patterns | Clear docs, consistent conventions |

### Comparison with Alternatives

**vs. Simple Frame Loop (game-style)**:
```zig
// Simple but wasteful
while (running) {
    processInput();
    updatePhysics();
    render();
    sleep(16);  // Always consumes CPU
}
```
- Simpler but inefficient for mostly-static UIs
- No natural place for async events

**vs. Pure Callback Spaghetti**:
```zig
// Callback hell
stdin.onData(fn(data) {
    parser.onKey(fn(key) {
        handler.onAction(fn(action) {
            // Deep nesting, hard to follow
        });
    });
});
```
- Our event queue linearizes flow
- Easier to reason about order

**vs. Pure Elm/Redux**:
```zig
// Pure but restrictive  
fn update(state: State, msg: Msg) State {
    // No side effects allowed here
}
```
- We allow side effects in handlers for practicality
- Keep purity where it matters (state transitions)


## 8. Implementation Checklist

```
Phase 1: Core Event System
├── [ ] Event union type with all categories
├── [ ] Event queue (single-threaded FIFO)
├── [ ] Thread-safe queue for async events
├── [ ] Basic dispatch loop
└── [ ] Input event parsing (keyboard, mouse)

Phase 2: Event Sources
├── [ ] Notcurses input integration
├── [ ] inotify file watcher
├── [ ] Timer wheel for physics/animation
├── [ ] Network socket for AI streaming
└── [ ] Signal handlers

Phase 3: Hook System
├── [ ] Hook registry with phases
├── [ ] Priority ordering
├── [ ] Event filtering
├── [ ] Built-in hooks (logging, debug)
└── [ ] Plugin API

Phase 4: Render Optimization
├── [ ] Dirty flag tracking
├── [ ] Region-based dirty tracking
├── [ ] Frame scheduler (60fps cap)
├── [ ] Event coalescing
├── [ ] Layered rendering
└── [ ] Notcurses pile management

Phase 5: Integration
├── [ ] Physics simulation integration
├── [ ] AI streaming integration
├── [ ] File watching integration
└── [ ] Full event loop assembly
```


## References

1. **Ratatui Event Handling**: https://ratatui.rs/concepts/event-handling/
2. **Bubbletea (Elm Architecture)**: https://github.com/charmbracelet/bubbletea
3. **Textual Events**: https://textual.textualize.io/guide/events/
4. **libxev (Zig Event Loop)**: https://github.com/mitchellh/libxev
5. **Notcurses Render API**: https://notcurses.com/notcurses_render.3.html
6. **Notcurses Repository**: https://github.com/dankamongmen/notcurses
7. **io_uring Introduction**: https://unixism.net/loti/what_is_io_uring.html
8. **TigerBeetle io_uring Abstraction**: https://tigerbeetle.com/blog/a-friendly-abstraction-over-iouring-and-kqueue/
