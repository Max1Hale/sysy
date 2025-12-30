const std = @import("std");
const vaxis = @import("vaxis");
const types = @import("../metrics/types.zig");
const formatting = @import("formatting.zig");
const graph = @import("graph.zig");
const ringbuffer = @import("../utils/ringbuffer.zig");

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    vaxis_arena: *std.heap.ArenaAllocator,
    vx: *vaxis.Vaxis,
    cpu_history: ringbuffer.CircularBuffer(f64, 60),
    mem_history: ringbuffer.CircularBuffer(f64, 60),

    // Persistent buffers to ensure strings remain valid until render
    render_buffer: [8192]u8,

    pub fn init(allocator: std.mem.Allocator) !Renderer {
        // Create an ArenaAllocator for vaxis to handle all its internal allocations
        // This ensures all vaxis memory (including screens created during resize) is freed together
        const vaxis_arena = try allocator.create(std.heap.ArenaAllocator);
        vaxis_arena.* = std.heap.ArenaAllocator.init(allocator);
        errdefer {
            vaxis_arena.deinit();
            allocator.destroy(vaxis_arena);
        }

        const vaxis_allocator = vaxis_arena.allocator();
        const vx = try vaxis_allocator.create(vaxis.Vaxis);
        vx.* = try vaxis.init(vaxis_allocator, .{});

        return Renderer{
            .allocator = allocator,
            .vaxis_arena = vaxis_arena,
            .vx = vx,
            .cpu_history = ringbuffer.CircularBuffer(f64, 60).init(),
            .mem_history = ringbuffer.CircularBuffer(f64, 60).init(),
            .render_buffer = undefined,
        };
    }

    pub fn deinit(self: *Renderer, tty_writer: anytype) void {
        const vaxis_allocator = self.vaxis_arena.allocator();
        self.vx.deinit(vaxis_allocator, tty_writer);
        self.vaxis_arena.deinit();
        self.allocator.destroy(self.vaxis_arena);
    }

    pub fn deinitWithoutVaxis(self: *Renderer) void {
        self.vaxis_arena.deinit();
        self.allocator.destroy(self.vaxis_arena);
    }

    pub fn render(self: *Renderer, metrics: types.Metrics, tty_writer: anytype) !void {
        self.cpu_history.push(metrics.cpu.total_usage);
        self.mem_history.push(metrics.memory.usagePercent());

        // Use a fixed buffer allocator for all text rendering
        // This ensures strings remain valid until vx.render() is called
        var fba = std.heap.FixedBufferAllocator.init(&self.render_buffer);
        const buf_alloc = fba.allocator();

        var win = self.vx.window();
        win.clear();

        var row: usize = 0;

        try self.renderCPU(&win, metrics.cpu, &row, buf_alloc);
        row += 1;

        try self.renderMemory(&win, metrics.memory, &row, buf_alloc);
        row += 1;

        try self.renderDisk(&win, metrics.disk, &row, buf_alloc);
        row += 1;

        try self.renderNetwork(&win, metrics.network, &row, buf_alloc);

        try self.vx.render(tty_writer);
    }

    fn renderCPU(self: *Renderer, win: *vaxis.Window, cpu: types.CPUMetrics, row: *usize, alloc: std.mem.Allocator) !void {
        const title = "CPU Usage";
        const title_seg = vaxis.Segment{ .text = title, .style = .{ .bold = true, .fg = .{ .index = 4 } } };
        _ = win.printSegment(title_seg, .{ .row_offset = @intCast(row.*) });
        row.* += 1;

        var percent_buf: [64]u8 = undefined;
        const percent_str = try formatting.formatPercent(cpu.total_usage, &percent_buf);
        const line = try std.fmt.allocPrint(alloc, "  Total: {s}", .{percent_str});
        _ = win.print(&.{.{ .text = line }}, .{ .row_offset = @intCast(row.*) });
        row.* += 1;

        var graph_data: [60]f64 = undefined;
        var i: usize = 0;
        while (i < self.cpu_history.len()) : (i += 1) {
            graph_data[i] = self.cpu_history.get(i) orelse 0.0;
        }

        var graph_buf: [512]u8 = undefined;
        const sparkline = try graph.renderSparkline(graph_data[0..self.cpu_history.len()], 100.0, &graph_buf);
        const graph_line = try std.fmt.allocPrint(alloc, "  {s}", .{sparkline});
        _ = win.print(&.{.{ .text = graph_line }}, .{ .row_offset = @intCast(row.*) });
        row.* += 1;

        for (cpu.per_core, 0..) |core_usage, core_idx| {
            var core_buf: [64]u8 = undefined;
            const core_str = try formatting.formatPercent(core_usage, &core_buf);
            const core_line = try std.fmt.allocPrint(alloc, "  Core {d}: {s}", .{ core_idx, core_str });
            _ = win.print(&.{.{ .text = core_line }}, .{ .row_offset = @intCast(row.*) });
            row.* += 1;
        }
    }

    fn renderMemory(self: *Renderer, win: *vaxis.Window, mem: types.MemoryMetrics, row: *usize, alloc: std.mem.Allocator) !void {
        const title = "Memory Usage";
        const title_seg = vaxis.Segment{ .text = title, .style = .{ .bold = true, .fg = .{ .index = 2 } } };
        _ = win.printSegment(title_seg, .{ .row_offset = @intCast(row.*) });
        row.* += 1;

        var buf1: [64]u8 = undefined;
        var buf2: [64]u8 = undefined;
        var buf3: [64]u8 = undefined;
        const used_str = try formatting.formatBytes(mem.used, &buf1);
        const total_str = try formatting.formatBytes(mem.total, &buf2);
        const percent_str = try formatting.formatPercent(mem.usagePercent(), &buf3);

        const line = try std.fmt.allocPrint(alloc, "  {s} / {s} ({s})", .{ used_str, total_str, percent_str });
        _ = win.print(&.{.{ .text = line }}, .{ .row_offset = @intCast(row.*) });
        row.* += 1;

        var graph_data: [60]f64 = undefined;
        var i: usize = 0;
        while (i < self.mem_history.len()) : (i += 1) {
            graph_data[i] = self.mem_history.get(i) orelse 0.0;
        }

        var graph_buf: [512]u8 = undefined;
        const sparkline = try graph.renderSparkline(graph_data[0..self.mem_history.len()], 100.0, &graph_buf);
        const graph_line = try std.fmt.allocPrint(alloc, "  {s}", .{sparkline});
        _ = win.print(&.{.{ .text = graph_line }}, .{ .row_offset = @intCast(row.*) });
        row.* += 1;
    }

    fn renderDisk(self: *Renderer, win: *vaxis.Window, disk: types.DiskMetrics, row: *usize, alloc: std.mem.Allocator) !void {
        _ = self;
        const title = "Disk I/O";
        const title_seg = vaxis.Segment{ .text = title, .style = .{ .bold = true, .fg = .{ .index = 5 } } };
        _ = win.printSegment(title_seg, .{ .row_offset = @intCast(row.*) });
        row.* += 1;

        var buf1: [64]u8 = undefined;
        var buf2: [64]u8 = undefined;
        const read_str = try formatting.formatBytesPerSec(disk.read_bytes_per_sec, &buf1);
        const write_str = try formatting.formatBytesPerSec(disk.write_bytes_per_sec, &buf2);

        const line = try std.fmt.allocPrint(alloc, "  Read: {s}  Write: {s}", .{ read_str, write_str });
        _ = win.print(&.{.{ .text = line }}, .{ .row_offset = @intCast(row.*) });
        row.* += 1;
    }

    fn renderNetwork(self: *Renderer, win: *vaxis.Window, net: types.NetworkMetrics, row: *usize, alloc: std.mem.Allocator) !void {
        _ = self;
        const title = "Network I/O";
        const title_seg = vaxis.Segment{ .text = title, .style = .{ .bold = true, .fg = .{ .index = 6 } } };
        _ = win.printSegment(title_seg, .{ .row_offset = @intCast(row.*) });
        row.* += 1;

        var buf1: [64]u8 = undefined;
        var buf2: [64]u8 = undefined;
        const in_str = try formatting.formatBytesPerSec(net.bytes_in_per_sec, &buf1);
        const out_str = try formatting.formatBytesPerSec(net.bytes_out_per_sec, &buf2);

        const line = try std.fmt.allocPrint(alloc, "  In: {s}  Out: {s}", .{ in_str, out_str });
        _ = win.print(&.{.{ .text = line }}, .{ .row_offset = @intCast(row.*) });
        row.* += 1;
    }
};

test {
    // Import all tests from test files
    _ = @import("renderer_test.zig");
    _ = @import("vaxis_memory_test.zig");
}
