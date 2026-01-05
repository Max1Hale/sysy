const std = @import("std");
const args_mod = @import("cli/args.zig");
const types = @import("metrics/types.zig");
const cpu_collector = @import("platform/macos/cpu.zig");
const memory_collector = @import("platform/macos/memory.zig");
const disk_collector = @import("platform/macos/disk.zig");
const network_collector = @import("platform/macos/network.zig");
const process_collector = @import("platform/macos/process.zig");
const Renderer = @import("ui/renderer.zig").Renderer;
const ui_state = @import("ui/ui_state.zig");
const vaxis = @import("vaxis");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parsed_args = args_mod.Args.parse(allocator) catch |err| {
        if (err == error.HelpRequested) return;
        return err;
    };

    var cpu = try cpu_collector.CPUCollector.init(allocator);
    defer cpu.deinit();

    var mem = try memory_collector.MemoryCollector.init();
    defer mem.deinit();

    var disk = try disk_collector.DiskCollector.init();
    defer disk.deinit();

    var net = try network_collector.NetworkCollector.init(allocator);
    defer net.deinit();

    switch (parsed_args.mode) {
        .snapshot => try runSnapshot(allocator, &cpu, &mem, &disk, &net),
        .continuous => try runContinuous(allocator, &cpu, &mem, &disk, &net),
    }
}

fn runSnapshot(
    allocator: std.mem.Allocator,
    cpu: *cpu_collector.CPUCollector,
    mem: *memory_collector.MemoryCollector,
    disk: *disk_collector.DiskCollector,
    net: *network_collector.NetworkCollector,
) !void {
    std.Thread.sleep(std.time.ns_per_s);

    var cpu_metrics = try cpu.collect();
    defer cpu_metrics.deinit(allocator);

    const mem_metrics = try mem.collect();
    const disk_metrics = try disk.collect();
    const net_metrics = try net.collect();

    const metrics = types.Metrics{
        .cpu = cpu_metrics,
        .memory = mem_metrics,
        .disk = disk_metrics,
        .network = net_metrics,
        .timestamp = std.time.milliTimestamp(),
    };

    printMetricsSnapshot(metrics);
}

fn runContinuous(
    allocator: std.mem.Allocator,
    cpu: *cpu_collector.CPUCollector,
    mem: *memory_collector.MemoryCollector,
    disk: *disk_collector.DiskCollector,
    net: *network_collector.NetworkCollector,
) !void {
    var renderer = try Renderer.init(allocator);
    defer renderer.deinitWithoutVaxis();

    var proc_collector = try process_collector.ProcessCollector.init(allocator);
    defer proc_collector.deinit();

    var buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(&buffer);
    defer tty.deinit();

    var loop: vaxis.Loop(Event) = .{
        .vaxis = renderer.vx,
        .tty = &tty,
    };
    try loop.init();

    try loop.start();
    defer loop.stop();

    const tty_writer = tty.writer();

    try renderer.vx.enterAltScreen(tty_writer);
    try renderer.vx.queryTerminal(tty_writer, 1 * std.time.ns_per_s);

    var should_quit = false;
    var last_metrics_collect: i64 = 0; // Track when we last collected metrics
    var ready_to_render = false;
    var needs_render = true; // Force initial render

    // Cache for metrics to use between collection cycles
    var cached_cpu_metrics: ?types.CPUMetrics = null;
    var cached_mem_metrics: types.MemoryMetrics = undefined;
    var cached_disk_metrics: types.DiskMetrics = undefined;
    var cached_net_metrics: types.NetworkMetrics = undefined;

    while (!should_quit) {
        // Check for events without blocking (vaxis loop runs in background thread)
        while (loop.tryEvent()) |event| {
            switch (event) {
                .key_press => |key| {
                    if (key.matches('c', .{ .ctrl = true }) or key.matches('q', .{})) {
                        should_quit = true;
                        break;
                    } else if (key.matches('j', .{})) {
                        // Vim: scroll down
                        const processes = proc_collector.process_list.items;
                        renderer.ui_state.scrollDown(processes.len);
                        needs_render = true;
                    } else if (key.matches('k', .{})) {
                        // Vim: scroll up
                        renderer.ui_state.scrollUp();
                        needs_render = true;
                    } else if (key.matches('d', .{})) {
                        // Vim: page down
                        const processes = proc_collector.process_list.items;
                        renderer.ui_state.pageDown(processes.len);
                        needs_render = true;
                    } else if (key.matches('u', .{})) {
                        // Vim: page up
                        renderer.ui_state.pageUp();
                        needs_render = true;
                    } else if (key.matches('1', .{})) {
                        // Switch to CPU panel
                        renderer.ui_state.switchToPanel(.cpu);
                        needs_render = true;
                    } else if (key.matches('2', .{})) {
                        // Switch to Memory panel
                        renderer.ui_state.switchToPanel(.memory);
                        needs_render = true;
                    } else if (key.matches('3', .{})) {
                        // Switch to Disk panel
                        renderer.ui_state.switchToPanel(.disk);
                        needs_render = true;
                    } else if (key.matches('4', .{})) {
                        // Switch to Network panel
                        renderer.ui_state.switchToPanel(.network);
                        needs_render = true;
                    } else if (key.matches('5', .{})) {
                        // Switch to Processes panel
                        renderer.ui_state.switchToPanel(.processes);
                        needs_render = true;
                    } else if (key.matches('s', .{})) {
                        // Toggle process sort mode
                        renderer.ui_state.toggleProcessSort();
                        needs_render = true;
                    }
                },
                .winsize => |ws| {
                    const vaxis_allocator = renderer.vaxis_arena.allocator();
                    try renderer.vx.resize(vaxis_allocator, tty_writer, ws);
                    ready_to_render = true;
                    needs_render = true;
                },
            }
        }

        if (should_quit) break;

        // Only render after we've received at least one winsize event
        if (!ready_to_render) {
            std.Thread.sleep(50 * std.time.ns_per_ms);
            continue;
        }

        // Collect metrics once per second
        const now = std.time.milliTimestamp();
        if (now - last_metrics_collect >= 1000) {
            // Clean up old cached metrics if any
            if (cached_cpu_metrics) |*old_cpu| {
                old_cpu.deinit(allocator);
            }

            // Collect new metrics
            cached_cpu_metrics = try cpu.collect();
            cached_mem_metrics = try mem.collect();
            cached_disk_metrics = try disk.collect();
            cached_net_metrics = try net.collect();

            // Convert UI sort mode to ProcessCollector sort mode
            const sort_mode: process_collector.ProcessSortMode = switch (renderer.ui_state.process_sort_mode) {
                .memory => .memory,
                .cpu => .cpu,
            };
            _ = try proc_collector.collect(sort_mode);

            // Update graph history only when we have new metrics
            const new_metrics = types.Metrics{
                .cpu = cached_cpu_metrics.?,
                .memory = cached_mem_metrics,
                .disk = cached_disk_metrics,
                .network = cached_net_metrics,
                .timestamp = now,
            };
            renderer.updateHistory(new_metrics);

            last_metrics_collect = now;
            needs_render = true;
        }

        // Render immediately when UI state changes or metrics are updated
        if (needs_render and cached_cpu_metrics != null) {
            const metrics = types.Metrics{
                .cpu = cached_cpu_metrics.?,
                .memory = cached_mem_metrics,
                .disk = cached_disk_metrics,
                .network = cached_net_metrics,
                .timestamp = now,
            };

            const processes = proc_collector.process_list.items;

            // Render the UI
            try renderer.render(metrics, processes, tty_writer);
            needs_render = false;
        }

        std.Thread.sleep(16 * std.time.ns_per_ms); // ~60fps for responsive input
    }

    // Clean up cached metrics
    if (cached_cpu_metrics) |*cpu_m| {
        cpu_m.deinit(allocator);
    }

    try renderer.vx.exitAltScreen(tty_writer);
}

fn printMetricsSnapshot(metrics: types.Metrics) void {
    const formatting = @import("ui/formatting.zig");
    var buf: [256]u8 = undefined;

    std.debug.print("=== System Metrics ===\n", .{});
    std.debug.print("\nCPU Usage:\n", .{});
    const cpu_percent = formatting.formatPercent(metrics.cpu.total_usage, &buf) catch "N/A";
    std.debug.print("  Total: {s}\n", .{cpu_percent});
    for (metrics.cpu.per_core, 0..) |core_usage, idx| {
        const core_percent = formatting.formatPercent(core_usage, &buf) catch "N/A";
        std.debug.print("  Core {d}: {s}\n", .{ idx, core_percent });
    }

    std.debug.print("\nMemory Usage:\n", .{});
    var buf2: [256]u8 = undefined;
    var buf3: [256]u8 = undefined;
    const mem_used = formatting.formatBytes(metrics.memory.used, &buf) catch "N/A";
    const mem_total = formatting.formatBytes(metrics.memory.total, &buf2) catch "N/A";
    const mem_percent = formatting.formatPercent(metrics.memory.usagePercent(), &buf3) catch "N/A";
    std.debug.print("  {s} / {s} ({s})\n", .{ mem_used, mem_total, mem_percent });

    std.debug.print("\nDisk I/O:\n", .{});
    var buf4: [256]u8 = undefined;
    const disk_read = formatting.formatBytesPerSec(metrics.disk.read_bytes_per_sec, &buf) catch "N/A";
    const disk_write = formatting.formatBytesPerSec(metrics.disk.write_bytes_per_sec, &buf4) catch "N/A";
    std.debug.print("  Read: {s}  Write: {s}\n", .{ disk_read, disk_write });

    std.debug.print("\nNetwork I/O:\n", .{});
    var buf5: [256]u8 = undefined;
    const net_in = formatting.formatBytesPerSec(metrics.network.bytes_in_per_sec, &buf) catch "N/A";
    const net_out = formatting.formatBytesPerSec(metrics.network.bytes_out_per_sec, &buf5) catch "N/A";
    std.debug.print("  In: {s}  Out: {s}\n", .{ net_in, net_out });
}

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};
