//! Thread-safe MPSC event queue for the Terminal Spatial Engine.
//! Supports event coalescing, priority ordering, and blocking/non-blocking operations.

const std = @import("std");

// =============================================================================
// Type Aliases
// =============================================================================

pub const NodeId = u32;
pub const EdgeId = u32;
pub const WidgetId = u32;
pub const AnimationId = u32;

// =============================================================================
// Event Priority
// =============================================================================

pub const EventPriority = enum(u8) {
    system = 0, // Highest - signals, quit
    input = 1, // User input
    external = 2, // AI, file changes
    internal = 3, // Physics, animations
    cosmetic = 4, // Cursor blink, subtle effects
};

// =============================================================================
// Input Events
// =============================================================================

pub const Key = enum {
    // Special keys
    escape,
    enter,
    tab,
    backspace,
    delete,
    insert,
    home,
    end,
    page_up,
    page_down,
    up,
    down,
    left,
    right,
    // Function keys
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    // Character (use char field)
    char,
    // Unknown
    unknown,
};

pub const Modifiers = packed struct {
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
    super: bool = false,
};

pub const KeyEvent = struct {
    key: Key,
    char: ?u21 = null, // Unicode codepoint if printable
    modifiers: Modifiers = .{},
};

pub const MouseButton = enum {
    none,
    left,
    middle,
    right,
    scroll_up,
    scroll_down,
};

pub const MouseEvent = struct {
    x: u16,
    y: u16,
    pixel_x: ?u16 = null,
    pixel_y: ?u16 = null,
    button: MouseButton = .none,
    modifiers: Modifiers = .{},
};

pub const ScrollEvent = struct {
    x: u16,
    y: u16,
    delta_x: i16 = 0,
    delta_y: i16 = 0,
    modifiers: Modifiers = .{},
};

pub const TouchEvent = struct {
    id: u32,
    x: u16,
    y: u16,
    pressure: ?f32 = null,
};

pub const InputEvent = union(enum) {
    key_press: KeyEvent,
    key_release: KeyEvent,
    mouse_move: MouseEvent,
    mouse_press: MouseEvent,
    mouse_release: MouseEvent,
    mouse_scroll: ScrollEvent,
    mouse_drag: MouseEvent,
    touch_start: TouchEvent,
    touch_move: TouchEvent,
    touch_end: TouchEvent,
};

// =============================================================================
// External Events
// =============================================================================

pub const AITokenEvent = struct {
    stream_id: u32,
    token: []const u8,
    is_complete: bool = false,
};

pub const AICompleteEvent = struct {
    stream_id: u32,
    total_tokens: u32,
    latency_ms: u32,
};

pub const AIErrorEvent = struct {
    stream_id: u32,
    error_code: u32,
    message: []const u8,
};

pub const FileChangeKind = enum {
    modified,
    created,
    deleted,
    renamed,
};

pub const FileChangeEvent = struct {
    path: []const u8,
    kind: FileChangeKind,
    timestamp: i64,
};

pub const IPCMessage = struct {
    source: []const u8,
    payload: []const u8,
};

pub const ExternalEvent = union(enum) {
    ai_token: AITokenEvent,
    ai_complete: AICompleteEvent,
    ai_error: AIErrorEvent,
    file_changed: FileChangeEvent,
    file_created: FileChangeEvent,
    file_deleted: FileChangeEvent,
    ipc_message: IPCMessage,
};

// =============================================================================
// Internal Events
// =============================================================================

pub const AnimationFrame = struct {
    id: AnimationId,
    progress: f32, // 0.0 to 1.0
    elapsed_ms: u32,
};

pub const Viewport = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    zoom: f32 = 1.0,
};

pub const Mode = enum {
    normal,
    insert,
    command,
    visual,
    search,
};

pub const InternalEvent = union(enum) {
    physics_tick: void,
    physics_settled: void,
    physics_started: void,
    animation_frame: AnimationFrame,
    animation_complete: AnimationId,
    node_added: NodeId,
    node_removed: NodeId,
    edge_added: EdgeId,
    edge_removed: EdgeId,
    selection_changed: []const NodeId,
    viewport_changed: Viewport,
    zoom_changed: f32,
    focus_changed: ?WidgetId,
    mode_changed: Mode,
};

// =============================================================================
// System Events
// =============================================================================

pub const ResizeEvent = struct {
    cols: u16,
    rows: u16,
    pixel_width: ?u16 = null,
    pixel_height: ?u16 = null,
};

pub const Signal = enum {
    sigint,
    sigterm,
    sigwinch,
    sigtstp,
    sigcont,
    sighup,
};

pub const SystemEvent = union(enum) {
    resize: ResizeEvent,
    focus_gained: void,
    focus_lost: void,
    signal: Signal,
    quit_requested: void,
    suspend_requested: void,
    resumed: void, // 'resume' is a reserved keyword in Zig
};

// =============================================================================
// Top-Level Event Union
// =============================================================================

pub const Event = union(enum) {
    input: InputEvent,
    external: ExternalEvent,
    internal: InternalEvent,
    system: SystemEvent,

    pub fn priority(self: Event) EventPriority {
        return switch (self) {
            .system => .system,
            .input => .input,
            .external => .external,
            .internal => .internal,
        };
    }

    /// Check if this event can coalesce with another
    pub fn canCoalesce(self: Event, other: Event) bool {
        return switch (self) {
            .system => |s| switch (s) {
                .resize => other == .system and other.system == .resize,
                else => false,
            },
            .input => |i| switch (i) {
                .mouse_move => other == .input and other.input == .mouse_move,
                else => false,
            },
            else => false,
        };
    }
};

// =============================================================================
// Event Queue (Thread-Safe MPSC)
// =============================================================================

pub const EventQueue = struct {
    const Self = @This();
    const DEFAULT_CAPACITY: usize = 1024;

    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    buffer: []Event,
    head: usize,
    tail: usize,
    count: usize,
    allocator: std.mem.Allocator,
    coalesce_enabled: bool,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return initWithCapacity(allocator, DEFAULT_CAPACITY);
    }

    pub fn initWithCapacity(allocator: std.mem.Allocator, capacity: usize) !Self {
        const buffer = try allocator.alloc(Event, capacity);
        return Self{
            .mutex = .{},
            .condition = .{},
            .buffer = buffer,
            .head = 0,
            .tail = 0,
            .count = 0,
            .allocator = allocator,
            .coalesce_enabled = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buffer);
    }

    /// Push an event to the queue (thread-safe, from any thread)
    pub fn push(self: *Self, event: Event) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Coalesce if enabled and possible
        if (self.coalesce_enabled and self.count > 0) {
            const last_idx = if (self.tail == 0) self.buffer.len - 1 else self.tail - 1;
            if (self.buffer[last_idx].canCoalesce(event)) {
                // Replace last event with new one (coalesce)
                self.buffer[last_idx] = event;
                self.condition.signal();
                return true;
            }
        }

        // Check if full
        if (self.count >= self.buffer.len) {
            return false; // Queue full, drop event
        }

        self.buffer[self.tail] = event;
        self.tail = (self.tail + 1) % self.buffer.len;
        self.count += 1;

        self.condition.signal();
        return true;
    }

    /// Non-blocking pop (returns null if empty)
    pub fn tryPop(self: *Self) ?Event {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.count == 0) {
            return null;
        }

        const event = self.buffer[self.head];
        self.head = (self.head + 1) % self.buffer.len;
        self.count -= 1;

        return event;
    }

    /// Blocking pop with timeout (timeout in nanoseconds)
    /// Returns null on timeout
    pub fn waitWithTimeout(self: *Self, timeout_ns: i128) ?Event {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.count == 0) {
            if (timeout_ns < 0) {
                // Block forever
                self.condition.wait(&self.mutex);
            } else {
                // Wait with timeout
                const timeout_u64: u64 = @intCast(@min(timeout_ns, std.math.maxInt(u64)));
                self.condition.timedWait(&self.mutex, timeout_u64) catch {
                    // Timeout occurred
                    return null;
                };
            }
        }

        if (self.count == 0) {
            return null; // Spurious wakeup
        }

        const event = self.buffer[self.head];
        self.head = (self.head + 1) % self.buffer.len;
        self.count -= 1;

        return event;
    }

    /// Get current queue length
    pub fn len(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.count;
    }

    /// Check if queue is empty
    pub fn isEmpty(self: *Self) bool {
        return self.len() == 0;
    }

    /// Clear all events
    pub fn clear(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.head = 0;
        self.tail = 0;
        self.count = 0;
    }

    /// Drain all events into a slice (caller provides buffer)
    pub fn drainInto(self: *Self, out: []Event) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < out.len and self.count > 0) {
            out[i] = self.buffer[self.head];
            self.head = (self.head + 1) % self.buffer.len;
            self.count -= 1;
            i += 1;
        }

        return i;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "EventQueue basic operations" {
    var queue = try EventQueue.init(std.testing.allocator);
    defer queue.deinit();

    // Push and pop
    const event = Event{ .system = .quit_requested };
    try std.testing.expect(queue.push(event));
    try std.testing.expect(queue.len() == 1);

    const popped = queue.tryPop();
    try std.testing.expect(popped != null);
    try std.testing.expect(queue.isEmpty());
}

test "EventQueue coalescing" {
    var queue = try EventQueue.init(std.testing.allocator);
    defer queue.deinit();

    // Push two resize events - should coalesce
    const resize1 = Event{ .system = .{ .resize = .{ .cols = 80, .rows = 24 } } };
    const resize2 = Event{ .system = .{ .resize = .{ .cols = 100, .rows = 40 } } };

    try std.testing.expect(queue.push(resize1));
    try std.testing.expect(queue.push(resize2));
    try std.testing.expect(queue.len() == 1); // Coalesced

    const popped = queue.tryPop();
    try std.testing.expect(popped != null);
    try std.testing.expect(popped.?.system.resize.cols == 100); // Latest value
}

test "Event priority ordering" {
    const sys_event = Event{ .system = .quit_requested };
    const input_event = Event{ .input = .{ .key_press = .{ .key = .enter } } };
    const internal_event = Event{ .internal = .physics_tick };

    try std.testing.expect(@intFromEnum(sys_event.priority()) < @intFromEnum(input_event.priority()));
    try std.testing.expect(@intFromEnum(input_event.priority()) < @intFromEnum(internal_event.priority()));
}
