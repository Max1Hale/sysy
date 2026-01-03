const std = @import("std");
const vaxis = @import("vaxis");
const types = @import("../metrics/types.zig");
const formatting = @import("formatting.zig");
const graph = @import("graph.zig");
const ringbuffer = @import("../utils/ringbuffer.zig");
const ui_state = @import("ui_state.zig");
const process_collector = @import("../platform/macos/process.zig");

pub const Renderer = struct {
    allocator: std.mem.Allocator,
    vaxis_arena: *std.heap.ArenaAllocator,
    vx: *vaxis.Vaxis,
    cpu_history: ringbuffer.CircularBuffer(f64, 120),
    mem_history: ringbuffer.CircularBuffer(f64, 120),
    ui_state: ui_state.UIState,

    // Persistent buffers to ensure strings remain valid until render
    render_buffer: [16384]u8,

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
            .cpu_history = ringbuffer.CircularBuffer(f64, 120).init(),
            .mem_history = ringbuffer.CircularBuffer(f64, 120).init(),
            .ui_state = ui_state.UIState.init(),
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

    pub fn updateHistory(self: *Renderer, metrics: types.Metrics) void {
        self.cpu_history.push(metrics.cpu.total_usage);
        self.mem_history.push(metrics.memory.usagePercent());
    }

    pub fn render(self: *Renderer, metrics: types.Metrics, processes: []const process_collector.ProcessInfo, tty_writer: anytype) !void {
        // Use a fixed buffer allocator for all text rendering
        var fba = std.heap.FixedBufferAllocator.init(&self.render_buffer);
        const buf_alloc = fba.allocator();

        var win = self.vx.window();
        win.clear();

        // Update UI state with current window size
        self.ui_state.setScreenSize(win.width, win.height);

        var row: usize = 0;

        // Top section: System metrics with line graphs
        const graph_height: usize = 3;
        const graph_width = win.width;

        // Render graphs in a 2x2 grid
        const col_width = graph_width / 2;

        // CPU Graph (top-left) - Panel 1
        _ = try self.renderCPUGraph(&win, metrics.cpu, row, graph_height, col_width, 0, buf_alloc);

        // Memory Graph (top-right) - Panel 2
        _ = try self.renderMemoryGraph(&win, metrics.memory, row, graph_height, col_width, col_width, buf_alloc);

        row += graph_height + 1;

        // Disk I/O (bottom-left) - Panel 3
        row += try self.renderDiskInfo(&win, metrics.disk, row, col_width, 0, buf_alloc);

        // Network I/O (bottom-right) - Panel 4
        _ = try self.renderNetworkInfo(&win, metrics.network, row - 2, col_width, col_width, buf_alloc);
        row += 1;

        // Separator
        const sep_line = try std.fmt.allocPrint(buf_alloc, "{s}", .{"─" ** 80});
        _ = win.print(&.{.{ .text = sep_line[0..@min(sep_line.len, graph_width * 3)] }}, .{ .row_offset = @intCast(row) });
        row += 1;

        // Bottom section: Process list - Panel 5
        try self.renderProcessList(&win, processes, row, buf_alloc);

        // Status bar at the bottom
        try self.renderStatusBar(&win, buf_alloc);

        try self.vx.render(tty_writer);
    }

    fn renderCPUGraph(self: *Renderer, win: *vaxis.Window, cpu: types.CPUMetrics, row_start: usize, height: usize, width: usize, col_offset: usize, alloc: std.mem.Allocator) !usize {
        var percent_buf: [32]u8 = undefined;
        const percent_str = try formatting.formatPercent(cpu.total_usage, &percent_buf);
        const title = try std.fmt.allocPrint(alloc, "1:CPU {s}", .{percent_str});

        const color: vaxis.Color = if (self.ui_state.active_panel == .cpu)
            .{ .index = 3 } // Yellow when active
        else
            .{ .index = 4 }; // Blue when inactive

        var graph_data: [120]f64 = undefined;
        var i: usize = 0;
        while (i < self.cpu_history.len()) : (i += 1) {
            graph_data[i] = self.cpu_history.get(i) orelse 0.0;
        }

        // Render with column offset
        var child = win.child(.{ .x_off = @intCast(col_offset), .y_off = @intCast(row_start), .width = @intCast(width), .height = @intCast(height + 1) });
        return try graph.renderLineGraph(&child, graph_data[0..self.cpu_history.len()], 100.0, 0, height, width - 2, title, color, alloc);
    }

    fn renderMemoryGraph(self: *Renderer, win: *vaxis.Window, mem: types.MemoryMetrics, row_start: usize, height: usize, width: usize, col_offset: usize, alloc: std.mem.Allocator) !usize {
        var percent_buf: [32]u8 = undefined;
        const percent_str = try formatting.formatPercent(mem.usagePercent(), &percent_buf);
        const title = try std.fmt.allocPrint(alloc, "2:Mem {s}", .{percent_str});

        const color: vaxis.Color = if (self.ui_state.active_panel == .memory)
            .{ .index = 3 } // Yellow when active
        else
            .{ .index = 2 }; // Green when inactive

        var graph_data: [120]f64 = undefined;
        var i: usize = 0;
        while (i < self.mem_history.len()) : (i += 1) {
            graph_data[i] = self.mem_history.get(i) orelse 0.0;
        }

        var child = win.child(.{ .x_off = @intCast(col_offset), .y_off = @intCast(row_start), .width = @intCast(width), .height = @intCast(height + 1) });
        return try graph.renderLineGraph(&child, graph_data[0..self.mem_history.len()], 100.0, 0, height, width - 2, title, color, alloc);
    }

    fn renderDiskInfo(self: *Renderer, win: *vaxis.Window, disk: types.DiskMetrics, row_start: usize, width: usize, col_offset: usize, alloc: std.mem.Allocator) !usize {
        const color: vaxis.Color = if (self.ui_state.active_panel == .disk)
            .{ .index = 3 }
        else
            .{ .index = 5 };

        var buf1: [32]u8 = undefined;
        var buf2: [32]u8 = undefined;
        const read_str = try formatting.formatBytesPerSec(disk.read_bytes_per_sec, &buf1);
        const write_str = try formatting.formatBytesPerSec(disk.write_bytes_per_sec, &buf2);

        const line = try std.fmt.allocPrint(alloc, "3:Disk R:{s} W:{s}", .{ read_str, write_str });
        var child = win.child(.{ .x_off = @intCast(col_offset), .y_off = @intCast(row_start), .width = @intCast(width), .height = 2 });
        _ = child.print(&.{.{ .text = line, .style = .{ .bold = true, .fg = color } }}, .{});
        return 2;
    }

    fn renderNetworkInfo(self: *Renderer, win: *vaxis.Window, net: types.NetworkMetrics, row_start: usize, width: usize, col_offset: usize, alloc: std.mem.Allocator) !usize {
        const color: vaxis.Color = if (self.ui_state.active_panel == .network)
            .{ .index = 3 }
        else
            .{ .index = 6 };

        var buf1: [32]u8 = undefined;
        var buf2: [32]u8 = undefined;
        const in_str = try formatting.formatBytesPerSec(net.bytes_in_per_sec, &buf1);
        const out_str = try formatting.formatBytesPerSec(net.bytes_out_per_sec, &buf2);

        const line = try std.fmt.allocPrint(alloc, "4:Net ↓{s} ↑{s}", .{ in_str, out_str });
        var child = win.child(.{ .x_off = @intCast(col_offset), .y_off = @intCast(row_start), .width = @intCast(width), .height = 2 });
        _ = child.print(&.{.{ .text = line, .style = .{ .bold = true, .fg = color } }}, .{});
        return 2;
    }

    fn renderProcessList(self: *Renderer, win: *vaxis.Window, processes: []const process_collector.ProcessInfo, row_start: usize, alloc: std.mem.Allocator) !void {
        const color: vaxis.Color = if (self.ui_state.active_panel == .processes)
            .{ .index = 3 }
        else
            .{ .index = 7 };

        // Header
        const header = try std.fmt.allocPrint(alloc, "5:Processes (PID | Name | Memory)", .{});
        _ = win.print(&.{.{ .text = header, .style = .{ .bold = true, .fg = color } }}, .{ .row_offset = @intCast(row_start) });

        // Render visible processes
        const visible_height = if (win.height > row_start + 2) win.height - row_start - 2 else 1;
        const end_idx = @min(self.ui_state.process_scroll_offset + visible_height, processes.len);

        var row = row_start + 1;
        for (processes[self.ui_state.process_scroll_offset..end_idx], 0..) |proc, rel_idx| {
            const abs_idx = self.ui_state.process_scroll_offset + rel_idx;
            const is_selected = abs_idx == self.ui_state.selected_process_index and self.ui_state.active_panel == .processes;

            var mem_buf: [32]u8 = undefined;
            const mem_str = try formatting.formatBytes(proc.mem_bytes, &mem_buf);

            const line = try std.fmt.allocPrint(alloc, "{d:>6} | {s:<20} | {s:>8}", .{
                proc.pid,
                proc.getName()[0..@min(proc.getName().len, 20)],
                mem_str,
            });

            const style: vaxis.Style = if (is_selected)
                .{ .bg = .{ .index = 7 }, .fg = .{ .index = 0 }, .reverse = true }
            else
                .{};

            _ = win.print(&.{.{ .text = line, .style = style }}, .{ .row_offset = @intCast(row) });
            row += 1;
        }
    }

    fn renderStatusBar(self: *Renderer, win: *vaxis.Window, alloc: std.mem.Allocator) !void {
        const status = try std.fmt.allocPrint(
            alloc,
            " Vim: j/k=scroll d/u=page q=quit | Numbers: 1-5=switch panel | Panel: {s}",
            .{@tagName(self.ui_state.active_panel)},
        );

        const row = if (win.height > 0) win.height - 1 else 0;
        _ = win.print(&.{.{ .text = status, .style = .{ .bg = .{ .index = 7 }, .fg = .{ .index = 0 } } }}, .{ .row_offset = @intCast(row) });
    }
};

test {
    // Import all tests from test files
    _ = @import("renderer_test.zig");
    _ = @import("vaxis_memory_test.zig");
}
