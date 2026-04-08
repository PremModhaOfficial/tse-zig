const std = @import("std");

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn mul(self: Vec2, scalar: f32) Vec2 {
        return .{ .x = self.x * scalar, .y = self.y * scalar };
    }

    pub fn div(self: Vec2, scalar: f32) Vec2 {
        return .{ .x = self.x / scalar, .y = self.y / scalar };
    }

    pub fn magSq(self: Vec2) f32 {
        return self.x * self.x + self.y * self.y;
    }

    pub fn mag(self: Vec2) f32 {
        return @sqrt(self.magSq());
    }

    pub fn norm(self: Vec2) Vec2 {
        const m = self.mag();
        if (m == 0.0) return .{ .x = 0.0, .y = 0.0 };
        return self.div(m);
    }
};

pub const Transform = struct {
    position: Vec2,
    velocity: Vec2 = .{ .x = 0, .y = 0 },
    force: Vec2 = .{ .x = 0, .y = 0 },
    mass: f32 = 1.0,
    locked: bool = false,
};

pub const Edge = struct {
    source: u32, // Entity ID
    target: u32, // Entity ID
    spring_length: f32 = 100.0,
};

pub const PhysicsConfig = struct {
    gravity: f32 = 0.1,
    repulsion: f32 = 2000.0,
    spring_k: f32 = 0.05,
    damping: f32 = 0.8,
    max_velocity: f32 = 50.0,
};

// Simplified Fruchterman-Reingold layout step
pub fn stepPhysics(
    nodes: []Transform,
    edges: []const Edge,
    config: PhysicsConfig,
    dt: f32,
) void {
    // 1. Calculate repulsive forces between all node pairs
    for (0..nodes.len) |i| {
        for (i + 1..nodes.len) |j| {
            var diff = nodes[i].position.sub(nodes[j].position);
            const dist_sq = diff.magSq();
            
            if (dist_sq < 0.1) {
                // Avoid division by zero, push apart slightly
                diff = .{ .x = 0.1, .y = 0.1 };
            }
            
            const force_mag = config.repulsion / dist_sq;
            const force_vec = diff.norm().mul(force_mag);

            nodes[i].force = nodes[i].force.add(force_vec);
            nodes[j].force = nodes[j].force.sub(force_vec);
        }
    }

    // 2. Calculate attractive forces for edges
    for (edges) |edge| {
        // Assume edge source/target match node array indices for this simplified step
        if (edge.source >= nodes.len or edge.target >= nodes.len) continue;
        
        const source = &nodes[edge.source];
        const target = &nodes[edge.target];

        var diff = target.position.sub(source.position);
        const dist = diff.mag();
        
        if (dist > 0.1) {
            const force_mag = config.spring_k * (dist - edge.spring_length);
            const force_vec = diff.norm().mul(force_mag);

            source.force = source.force.add(force_vec);
            target.force = target.force.sub(force_vec);
        }
    }

    // 3. Apply gravity (pull towards origin 0,0)
    for (nodes) |*node| {
        const dist = node.position.mag();
        if (dist > 0.1) {
            const force_vec = node.position.norm().mul(-config.gravity * dist);
            node.force = node.force.add(force_vec);
        }
    }

    // 4. Update velocities and positions
    for (nodes) |*node| {
        if (node.locked) {
            node.force = .{ .x = 0, .y = 0 };
            node.velocity = .{ .x = 0, .y = 0 };
            continue;
        }

        // a = F/m
        const accel = node.force.div(node.mass);
        
        // v = (v + a*dt) * damping
        node.velocity = node.velocity.add(accel.mul(dt)).mul(config.damping);

        // Cap velocity
        const v_mag = node.velocity.mag();
        if (v_mag > config.max_velocity) {
            node.velocity = node.velocity.norm().mul(config.max_velocity);
        }

        // p = p + v*dt
        node.position = node.position.add(node.velocity.mul(dt));

        // Reset force for next tick
        node.force = .{ .x = 0, .y = 0 };
    }
}

test "Vec2 basic operations" {
    const a = Vec2{ .x = 3.0, .y = 4.0 };
    const b = Vec2{ .x = 1.0, .y = 2.0 };
    
    const added = a.add(b);
    try std.testing.expectEqual(@as(f32, 4.0), added.x);
    try std.testing.expectEqual(@as(f32, 6.0), added.y);

    try std.testing.expectEqual(@as(f32, 25.0), a.magSq());
    try std.testing.expectEqual(@as(f32, 5.0), a.mag());
}
