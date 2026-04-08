//! Hook system for the Terminal Spatial Engine.
//! Implements a 3-phase dispatch model: before (can cancel) -> on (handle) -> after (cleanup)

const std = @import("std");
const event_queue = @import("event_queue.zig");
const Event = event_queue.Event;

// =============================================================================
// Hook Types
// =============================================================================

pub const HookPhase = enum {
    before, // Pre-processing, can cancel event
    on, // Main handling
    after, // Post-processing, cleanup
};

pub const HookResult = enum {
    continue_, // Process next hook
    stop, // Stop processing this event (handled)
    cancel, // Cancel event entirely (only valid in .before phase)
};

pub const HookHandle = struct {
    id: u64,
};

// =============================================================================
// Event Filter
// =============================================================================

pub const EventType = enum {
    input,
    external,
    internal,
    system,
};

pub const InputEventType = enum {
    key_press,
    key_release,
    mouse_move,
    mouse_press,
    mouse_release,
    mouse_scroll,
    mouse_drag,
    touch_start,
    touch_move,
    touch_end,
};

pub const ExternalEventType = enum {
    ai_token,
    ai_complete,
    ai_error,
    file_changed,
    file_created,
    file_deleted,
    ipc_message,
};

pub const InternalEventType = enum {
    physics_tick,
    physics_settled,
    physics_started,
    animation_frame,
    animation_complete,
    node_added,
    node_removed,
    edge_added,
    edge_removed,
    selection_changed,
    viewport_changed,
    zoom_changed,
    focus_changed,
    mode_changed,
};

pub const SystemEventType = enum {
    resize,
    focus_gained,
    focus_lost,
    signal,
    quit_requested,
    suspend_requested,
    resumed, // 'resume' is a reserved keyword in Zig
};

pub const SpecificFilter = union(enum) {
    input: InputEventType,
    external: ExternalEventType,
    internal: InternalEventType,
    system: SystemEventType,
};

pub const EventFilter = union(enum) {
    all: void, // Match all events
    event_type: EventType, // Match by category
    specific: SpecificFilter, // Match specific variant

    pub fn matches(self: EventFilter, event: *const Event) bool {
        return switch (self) {
            .all => true,
            .event_type => |et| switch (et) {
                .input => event.* == .input,
                .external => event.* == .external,
                .internal => event.* == .internal,
                .system => event.* == .system,
            },
            .specific => |sf| switch (sf) {
                .input => |it| if (event.* == .input) matchInputType(event.input, it) else false,
                .external => |et| if (event.* == .external) matchExternalType(event.external, et) else false,
                .internal => |it| if (event.* == .internal) matchInternalType(event.internal, it) else false,
                .system => |st| if (event.* == .system) matchSystemType(event.system, st) else false,
            },
        };
    }

    fn matchInputType(input: event_queue.InputEvent, filter: InputEventType) bool {
        return switch (filter) {
            .key_press => input == .key_press,
            .key_release => input == .key_release,
            .mouse_move => input == .mouse_move,
            .mouse_press => input == .mouse_press,
            .mouse_release => input == .mouse_release,
            .mouse_scroll => input == .mouse_scroll,
            .mouse_drag => input == .mouse_drag,
            .touch_start => input == .touch_start,
            .touch_move => input == .touch_move,
            .touch_end => input == .touch_end,
        };
    }

    fn matchExternalType(external: event_queue.ExternalEvent, filter: ExternalEventType) bool {
        return switch (filter) {
            .ai_token => external == .ai_token,
            .ai_complete => external == .ai_complete,
            .ai_error => external == .ai_error,
            .file_changed => external == .file_changed,
            .file_created => external == .file_created,
            .file_deleted => external == .file_deleted,
            .ipc_message => external == .ipc_message,
        };
    }

    fn matchInternalType(internal: event_queue.InternalEvent, filter: InternalEventType) bool {
        return switch (filter) {
            .physics_tick => internal == .physics_tick,
            .physics_settled => internal == .physics_settled,
            .physics_started => internal == .physics_started,
            .animation_frame => internal == .animation_frame,
            .animation_complete => internal == .animation_complete,
            .node_added => internal == .node_added,
            .node_removed => internal == .node_removed,
            .edge_added => internal == .edge_added,
            .edge_removed => internal == .edge_removed,
            .selection_changed => internal == .selection_changed,
            .viewport_changed => internal == .viewport_changed,
            .zoom_changed => internal == .zoom_changed,
            .focus_changed => internal == .focus_changed,
            .mode_changed => internal == .mode_changed,
        };
    }

    fn matchSystemType(system: event_queue.SystemEvent, filter: SystemEventType) bool {
        return switch (filter) {
            .resize => system == .resize,
            .focus_gained => system == .focus_gained,
            .focus_lost => system == .focus_lost,
            .signal => system == .signal,
            .quit_requested => system == .quit_requested,
            .suspend_requested => system == .suspend_requested,
            .resumed => system == .resumed,
        };
    }
};

// =============================================================================
// Hook Registry
// =============================================================================

pub const HookCallback = *const fn (*Event, ?*anyopaque) HookResult;

const Handler = struct {
    id: u64,
    phase: HookPhase,
    priority: i32, // Lower = earlier
    filter: EventFilter,
    callback: HookCallback,
    context: ?*anyopaque,
};

pub const HookRegistry = struct {
    const Self = @This();

    handlers: std.ArrayList(Handler),
    next_id: u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .handlers = std.ArrayList(Handler).init(allocator),
            .next_id = 1,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.handlers.deinit();
    }

    /// Register a hook handler
    pub fn register(
        self: *Self,
        phase: HookPhase,
        filter: EventFilter,
        callback: HookCallback,
        context: ?*anyopaque,
    ) !HookHandle {
        return self.registerWithPriority(phase, filter, callback, context, 0);
    }

    /// Register a hook handler with explicit priority
    pub fn registerWithPriority(
        self: *Self,
        phase: HookPhase,
        filter: EventFilter,
        callback: HookCallback,
        context: ?*anyopaque,
        priority: i32,
    ) !HookHandle {
        const id = self.next_id;
        self.next_id += 1;

        try self.handlers.append(.{
            .id = id,
            .phase = phase,
            .priority = priority,
            .filter = filter,
            .callback = callback,
            .context = context,
        });

        // Sort by phase (before < on < after), then by priority
        std.mem.sort(Handler, self.handlers.items, {}, lessThan);

        return HookHandle{ .id = id };
    }

    fn lessThan(_: void, a: Handler, b: Handler) bool {
        const phase_a = @intFromEnum(a.phase);
        const phase_b = @intFromEnum(b.phase);
        if (phase_a != phase_b) {
            return phase_a < phase_b;
        }
        return a.priority < b.priority;
    }

    /// Unregister a hook handler
    pub fn unregister(self: *Self, handle: HookHandle) void {
        for (self.handlers.items, 0..) |handler, i| {
            if (handler.id == handle.id) {
                _ = self.handlers.orderedRemove(i);
                return;
            }
        }
    }

    /// Dispatch an event through all registered hooks
    /// Returns false if the event was cancelled, true otherwise
    pub fn dispatch(self: *Self, event: *Event) bool {
        // Before phase - can cancel
        for (self.handlers.items) |handler| {
            if (handler.phase != .before) break; // Handlers sorted by phase
            if (!handler.filter.matches(event)) continue;

            switch (handler.callback(event, handler.context)) {
                .cancel => return false, // Event cancelled
                .stop => break, // Stop before phase
                .continue_ => {},
            }
        }

        // On phase - main handling
        for (self.handlers.items) |handler| {
            if (handler.phase == .before) continue;
            if (handler.phase == .after) break;
            if (!handler.filter.matches(event)) continue;

            switch (handler.callback(event, handler.context)) {
                .stop => break, // Stop on phase
                .cancel, .continue_ => {},
            }
        }

        // After phase - cleanup (always runs, can't stop)
        for (self.handlers.items) |handler| {
            if (handler.phase != .after) continue;
            if (!handler.filter.matches(event)) continue;

            _ = handler.callback(event, handler.context);
        }

        return true;
    }

    /// Get count of registered handlers
    pub fn handlerCount(self: *Self) usize {
        return self.handlers.items.len;
    }
};

// =============================================================================
// Convenience Builders
// =============================================================================

pub const HookBuilder = struct {
    registry: *HookRegistry,
    phase: HookPhase = .on,
    filter: EventFilter = .{ .all = {} },
    priority: i32 = 0,

    pub fn forPhase(self: HookBuilder, phase: HookPhase) HookBuilder {
        var b = self;
        b.phase = phase;
        return b;
    }

    pub fn forEventType(self: HookBuilder, event_type: EventType) HookBuilder {
        var b = self;
        b.filter = .{ .event_type = event_type };
        return b;
    }

    pub fn forInput(self: HookBuilder, input_type: InputEventType) HookBuilder {
        var b = self;
        b.filter = .{ .specific = .{ .input = input_type } };
        return b;
    }

    pub fn forSystem(self: HookBuilder, system_type: SystemEventType) HookBuilder {
        var b = self;
        b.filter = .{ .specific = .{ .system = system_type } };
        return b;
    }

    pub fn withPriority(self: HookBuilder, priority: i32) HookBuilder {
        var b = self;
        b.priority = priority;
        return b;
    }

    pub fn register(self: HookBuilder, callback: HookCallback, context: ?*anyopaque) !HookHandle {
        return self.registry.registerWithPriority(
            self.phase,
            self.filter,
            callback,
            context,
            self.priority,
        );
    }
};

/// Start building a hook registration
pub fn hook(registry: *HookRegistry) HookBuilder {
    return HookBuilder{ .registry = registry };
}

// =============================================================================
// Tests
// =============================================================================

test "HookRegistry basic registration and dispatch" {
    var registry = HookRegistry.init(std.testing.allocator);
    defer registry.deinit();

    var call_count: u32 = 0;

    const handler = struct {
        fn callback(_: *Event, ctx: ?*anyopaque) HookResult {
            const count: *u32 = @ptrCast(@alignCast(ctx));
            count.* += 1;
            return .continue_;
        }
    }.callback;

    _ = try registry.register(.on, .{ .all = {} }, handler, &call_count);

    var event = Event{ .system = .quit_requested };
    const result = registry.dispatch(&event);

    try std.testing.expect(result == true);
    try std.testing.expect(call_count == 1);
}

test "HookRegistry cancel in before phase" {
    var registry = HookRegistry.init(std.testing.allocator);
    defer registry.deinit();

    var on_called = false;

    const cancel_handler = struct {
        fn callback(_: *Event, _: ?*anyopaque) HookResult {
            return .cancel;
        }
    }.callback;

    const on_handler = struct {
        fn callback(_: *Event, ctx: ?*anyopaque) HookResult {
            const called: *bool = @ptrCast(@alignCast(ctx));
            called.* = true;
            return .continue_;
        }
    }.callback;

    _ = try registry.register(.before, .{ .all = {} }, cancel_handler, null);
    _ = try registry.register(.on, .{ .all = {} }, on_handler, &on_called);

    var event = Event{ .system = .quit_requested };
    const result = registry.dispatch(&event);

    try std.testing.expect(result == false); // Cancelled
    try std.testing.expect(on_called == false); // On phase not reached
}

test "EventFilter matches correctly" {
    const quit_event = Event{ .system = .quit_requested };
    const key_event = Event{ .input = .{ .key_press = .{ .key = .enter } } };

    const all_filter = EventFilter{ .all = {} };
    const system_filter = EventFilter{ .event_type = .system };
    const quit_filter = EventFilter{ .specific = .{ .system = .quit_requested } };
    const resize_filter = EventFilter{ .specific = .{ .system = .resize } };

    try std.testing.expect(all_filter.matches(&quit_event));
    try std.testing.expect(all_filter.matches(&key_event));
    try std.testing.expect(system_filter.matches(&quit_event));
    try std.testing.expect(!system_filter.matches(&key_event));
    try std.testing.expect(quit_filter.matches(&quit_event));
    try std.testing.expect(!resize_filter.matches(&quit_event));
}

test "HookBuilder fluent API" {
    var registry = HookRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const noop = struct {
        fn callback(_: *Event, _: ?*anyopaque) HookResult {
            return .continue_;
        }
    }.callback;

    _ = try hook(&registry)
        .forPhase(.before)
        .forSystem(.quit_requested)
        .withPriority(-10)
        .register(noop, null);

    try std.testing.expect(registry.handlerCount() == 1);
}
