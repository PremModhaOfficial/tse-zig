const std = @import("std");

pub const Entity = u32;
pub const MAX_ENTITIES: u32 = 100_000;
pub const NULL_ENTITY: Entity = std.math.maxInt(Entity);

pub fn SparseSet(comptime Component: type) type {
    return struct {
        const Self = @This();
        
        allocator: std.mem.Allocator,
        sparse: std.ArrayList(Entity),
        dense: std.ArrayList(Entity),
        components: std.ArrayList(Component),

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .sparse = std.ArrayList(Entity).init(allocator),
                .dense = std.ArrayList(Entity).init(allocator),
                .components = std.ArrayList(Component).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.sparse.deinit();
            self.dense.deinit();
            self.components.deinit();
        }

        pub fn contains(self: *const Self, entity: Entity) bool {
            if (entity >= self.sparse.items.len) return false;
            const dense_idx = self.sparse.items[entity];
            return dense_idx < self.dense.items.len and self.dense.items[dense_idx] == entity;
        }

        pub fn add(self: *Self, entity: Entity, component: Component) !void {
            if (self.contains(entity)) {
                self.components.items[self.sparse.items[entity]] = component;
                return;
            }

            if (entity >= self.sparse.items.len) {
                // Resize sparse array
                const new_len = @max(self.sparse.items.len * 2, entity + 1);
                try self.sparse.resize(new_len);
                // Fill with null entity logic not strictly needed if we check dense bound, 
                // but setting to NULL_ENTITY is safer
                @memset(self.sparse.items[self.sparse.items.len - (new_len - self.sparse.items.len) ..], NULL_ENTITY);
            }

            const dense_idx = @as(Entity, @intCast(self.dense.items.len));
            self.sparse.items[entity] = dense_idx;
            try self.dense.append(entity);
            try self.components.append(component);
        }

        pub fn remove(self: *Self, entity: Entity) void {
            if (!self.contains(entity)) return;

            const dense_idx = self.sparse.items[entity];
            const last_dense_idx = @as(Entity, @intCast(self.dense.items.len - 1));

            if (dense_idx != last_dense_idx) {
                // Swap with last
                const last_entity = self.dense.items[last_dense_idx];
                self.dense.items[dense_idx] = last_entity;
                self.components.items[dense_idx] = self.components.items[last_dense_idx];
                self.sparse.items[last_entity] = dense_idx;
            }

            _ = self.dense.pop();
            _ = self.components.pop();
            self.sparse.items[entity] = NULL_ENTITY;
        }

        pub fn get(self: *Self, entity: Entity) ?*Component {
            if (!self.contains(entity)) return null;
            return &self.components.items[self.sparse.items[entity]];
        }
        
        pub fn getConst(self: *const Self, entity: Entity) ?*const Component {
            if (!self.contains(entity)) return null;
            return &self.components.items[self.sparse.items[entity]];
        }
    };
}

pub const Registry = struct {
    allocator: std.mem.Allocator,
    next_entity: Entity = 0,

    pub fn init(allocator: std.mem.Allocator) Registry {
        return Registry{
            .allocator = allocator,
        };
    }

    pub fn deinit(_: *Registry) void {
        // In a full implementation, we'd keep a type-erased list of pools to deinit
    }

    pub fn createEntity(self: *Registry) Entity {
        const entity = self.next_entity;
        self.next_entity += 1;
        return entity;
    }
};

test "SparseSet basic operations" {
    const allocator = std.testing.allocator;
    var set = SparseSet(u32).init(allocator);
    defer set.deinit();

    try set.add(5, 42);
    try std.testing.expect(set.contains(5));
    try std.testing.expectEqual(@as(u32, 42), set.get(5).?.*);

    try set.add(10, 100);
    try std.testing.expect(set.contains(10));
    try std.testing.expectEqual(@as(u32, 100), set.get(10).?.*);

    set.remove(5);
    try std.testing.expect(!set.contains(5));
    try std.testing.expect(set.contains(10));
    try std.testing.expectEqual(@as(u32, 100), set.get(10).?.*);
}
