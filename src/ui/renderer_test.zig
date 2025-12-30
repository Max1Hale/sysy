const std = @import("std");
const Renderer = @import("renderer.zig").Renderer;
const types = @import("../metrics/types.zig");

test "Renderer init and deinit without leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var renderer = try Renderer.init(allocator);

    // Create a dummy writer for deinit
    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    renderer.deinit(writer);

    const leaked = gpa.deinit();
    try std.testing.expect(leaked == .ok);
}

test "Renderer init and deinitWithoutVaxis without leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var renderer = try Renderer.init(allocator);
    renderer.deinitWithoutVaxis();

    const leaked = gpa.deinit();
    try std.testing.expect(leaked == .ok);
}

test "Renderer with metrics rendering without leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var renderer = try Renderer.init(allocator);

    // Create mock metrics
    var per_core = [_]f64{50.0} ** 8;
    const cpu_metrics = types.CPUMetrics{
        .total_usage = 45.5,
        .per_core = per_core[0..],
    };

    const mem_metrics = types.MemoryMetrics{
        .total = 16 * 1024 * 1024 * 1024,
        .used = 8 * 1024 * 1024 * 1024,
        .free = 8 * 1024 * 1024 * 1024,
    };

    const disk_metrics = types.DiskMetrics{
        .read_bytes_per_sec = 1024 * 1024,
        .write_bytes_per_sec = 512 * 1024,
    };

    const net_metrics = types.NetworkMetrics{
        .bytes_in_per_sec = 2048 * 1024,
        .bytes_out_per_sec = 1024 * 1024,
    };

    const metrics = types.Metrics{
        .cpu = cpu_metrics,
        .memory = mem_metrics,
        .disk = disk_metrics,
        .network = net_metrics,
        .timestamp = std.time.milliTimestamp(),
    };

    // Add data to history multiple times to test memory management
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        renderer.cpu_history.push(metrics.cpu.total_usage);
        renderer.mem_history.push(metrics.memory.usagePercent());
    }

    // Clean up
    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();
    renderer.deinit(writer);

    const leaked = gpa.deinit();
    try std.testing.expect(leaked == .ok);
}

test "Renderer history management without leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var renderer = try Renderer.init(allocator);

    // Test filling up the history buffers beyond their capacity
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const value = @as(f64, @floatFromInt(i)) / 100.0;
        renderer.cpu_history.push(value);
        renderer.mem_history.push(value);
    }

    // Verify we can read the values (should be capped at 60)
    try std.testing.expectEqual(@as(usize, 60), renderer.cpu_history.len());
    try std.testing.expectEqual(@as(usize, 60), renderer.mem_history.len());

    // Clean up
    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();
    renderer.deinit(writer);

    const leaked = gpa.deinit();
    try std.testing.expect(leaked == .ok);
}

test "Renderer multiple init/deinit cycles without leaks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var buffer: [1024]u8 = undefined;

    // Test creating and destroying renderer multiple times
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        var renderer = try Renderer.init(allocator);

        var fbs = std.io.fixedBufferStream(&buffer);
        const writer = fbs.writer();

        renderer.deinit(writer);
    }

    const leaked = gpa.deinit();
    try std.testing.expect(leaked == .ok);
}
