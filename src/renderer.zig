const std = @import("std");
const ecs = @import("ecs.zig");
const spatial = @import("spatial.zig");
const nc = @cImport({
    @cInclude("notcurses/notcurses.h");
});

pub const Renderer = struct {
    const Self = @This();

    ncs: *nc.notcurses,
    stdplane: *nc.ncplane,
    allocator: std.mem.Allocator,

    // Internal RGBA buffer for sub-pixel rendering
    rgba_buffer: []u32,
    buf_width: u32,
    buf_height: u32,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var opts = std.mem.zeroes(nc.notcurses_options);
        opts.flags = nc.NCOPTION_SUPPRESS_BANNERS;

        const ncs = nc.notcurses_init(&opts, null) orelse {
            return error.NotcursesInitFailed;
        };

        const stdplane = nc.notcurses_stdplane(ncs) orelse {
            _ = nc.notcurses_stop(ncs);
            return error.StdplaneInitFailed;
        };

        return Self{
            .ncs = ncs,
            .stdplane = stdplane,
            .allocator = allocator,
            .rgba_buffer = &[_]u32{},
            .buf_width = 0,
            .buf_height = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.rgba_buffer.len > 0) {
            self.allocator.free(self.rgba_buffer);
        }
        _ = nc.notcurses_stop(self.ncs);
    }

    fn ensureBuffer(self: *Self, width: u32, height: u32) !void {
        if (self.buf_width != width or self.buf_height != height) {
            if (self.rgba_buffer.len > 0) {
                self.allocator.free(self.rgba_buffer);
            }
            self.rgba_buffer = try self.allocator.alloc(u32, width * height);
            self.buf_width = width;
            self.buf_height = height;
        }
        
        // Clear buffer with transparent black
        @memset(self.rgba_buffer, 0x00000000);
    }

    fn drawLine(self: *Self, x0: i32, y0: i32, x1: i32, y1: i32, color: u32) void {
        var cx = x0;
        var cy = y0;
        const dx = @as(i32, @intCast(@abs(x1 - x0)));
        const dy = @as(i32, -1) * @as(i32, @intCast(@abs(y1 - y0)));
        const sx: i32 = if (x0 < x1) 1 else -1;
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err = dx + dy;

        while (true) {
            if (cx >= 0 and cx < self.buf_width and cy >= 0 and cy < self.buf_height) {
                const idx = @as(usize, @intCast(cy)) * self.buf_width + @as(usize, @intCast(cx));
                self.rgba_buffer[idx] = color;
            }

            if (cx == x1 and cy == y1) break;
            const e2 = 2 * err;
            if (e2 >= dy) {
                err += dy;
                cx += sx;
            }
            if (e2 <= dx) {
                err += dx;
                cy += sy;
            }
        }
    }

    fn drawCircle(self: *Self, cx: i32, cy: i32, radius: i32, color: u32) void {
        var x: i32 = radius;
        var y: i32 = 0;
        var err: i32 = 0;

        while (x >= y) {
            self.setPixel(cx + x, cy + y, color);
            self.setPixel(cx + y, cy + x, color);
            self.setPixel(cx - y, cy + x, color);
            self.setPixel(cx - x, cy + y, color);
            self.setPixel(cx - x, cy - y, color);
            self.setPixel(cx - y, cy - x, color);
            self.setPixel(cx + y, cy - x, color);
            self.setPixel(cx + x, cy - y, color);

            if (err <= 0) {
                y += 1;
                err += 2 * y + 1;
            }
            if (err > 0) {
                x -= 1;
                err -= 2 * x + 1;
            }
        }
    }

    fn setPixel(self: *Self, x: i32, y: i32, color: u32) void {
        if (x >= 0 and x < self.buf_width and y >= 0 and y < self.buf_height) {
            const idx = @as(usize, @intCast(y)) * self.buf_width + @as(usize, @intCast(x));
            self.rgba_buffer[idx] = color;
        }
    }

    pub fn renderFrame(self: *Self, transforms: []spatial.Transform, edges: []const spatial.Edge) !void {
        var dim_y: c_uint = 0;
        var dim_x: c_uint = 0;
        nc.ncplane_dim_yx(self.stdplane, &dim_y, &dim_x);

        // Sub-pixel braille multiplier (2x4 pixels per braille character)
        const sub_w = dim_x * 2;
        const sub_h = dim_y * 4;

        try self.ensureBuffer(sub_w, sub_h);

        // Viewport mapping (center origin 0,0 to center of screen)
        const cx = @as(f32, @floatFromInt(sub_w)) / 2.0;
        const cy = @as(f32, @floatFromInt(sub_h)) / 2.0;
        const scale: f32 = 2.0; // zoom factor

        // Draw edges
        for (edges) |edge| {
            if (edge.source >= transforms.len or edge.target >= transforms.len) continue;
            const p1 = transforms[edge.source].position;
            const p2 = transforms[edge.target].position;

            const x1 = @as(i32, @intFromFloat(p1.x * scale + cx));
            const y1 = @as(i32, @intFromFloat(p1.y * scale + cy));
            const x2 = @as(i32, @intFromFloat(p2.x * scale + cx));
            const y2 = @as(i32, @intFromFloat(p2.y * scale + cy));

            self.drawLine(x1, y1, x2, y2, 0x888888FF); // Gray
        }

        // Draw nodes
        for (transforms) |t| {
            const px = @as(i32, @intFromFloat(t.position.x * scale + cx));
            const py = @as(i32, @intFromFloat(t.position.y * scale + cy));
            
            // Draw filled circle (roughly) by drawing concentric circles
            const radius = 4;
            var r: i32 = 0;
            while (r <= radius) : (r += 1) {
                self.drawCircle(px, py, r, 0xFFFFFFFF); // White
            }
        }

        // Blit buffer to Notcurses
        var vopts = std.mem.zeroes(nc.ncvisual_options);
        vopts.n = self.stdplane;
        vopts.blitter = nc.NCBLIT_BRAILLE;
        vopts.flags = nc.NCVISUAL_OPTION_NODEGRADE;

        const visual = nc.ncvisual_from_rgba(
            self.rgba_buffer.ptr,
            @as(c_int, @intCast(sub_h)),
            @as(c_int, @intCast(sub_w * 4)), // rowstride in bytes
            @as(c_int, @intCast(sub_w)),
        ) orelse return error.NcVisualCreationFailed;
        defer nc.ncvisual_destroy(visual);

        // Clear plane before blitting
        _ = nc.ncplane_erase(self.stdplane);

        _ = nc.ncvisual_blit(self.ncs, visual, &vopts);

        // Render to terminal
        _ = nc.notcurses_render(self.ncs);
    }
};
