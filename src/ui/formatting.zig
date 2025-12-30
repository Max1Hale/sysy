const std = @import("std");

pub fn formatBytes(bytes: u64, buffer: []u8) ![]const u8 {
    const kb: f64 = 1024.0;
    const mb: f64 = kb * 1024.0;
    const gb: f64 = mb * 1024.0;
    const tb: f64 = gb * 1024.0;

    const value = @as(f64, @floatFromInt(bytes));

    if (value >= tb) {
        return try std.fmt.bufPrint(buffer, "{d:.2} TB", .{value / tb});
    } else if (value >= gb) {
        return try std.fmt.bufPrint(buffer, "{d:.2} GB", .{value / gb});
    } else if (value >= mb) {
        return try std.fmt.bufPrint(buffer, "{d:.2} MB", .{value / mb});
    } else if (value >= kb) {
        return try std.fmt.bufPrint(buffer, "{d:.2} KB", .{value / kb});
    } else {
        return try std.fmt.bufPrint(buffer, "{d} B", .{bytes});
    }
}

pub fn formatPercent(percent: f64, buffer: []u8) ![]const u8 {
    return try std.fmt.bufPrint(buffer, "{d:.1}%", .{percent});
}

pub fn formatBytesPerSec(bytes_per_sec: u64, buffer: []u8) ![]const u8 {
    const kb: f64 = 1024.0;
    const mb: f64 = kb * 1024.0;
    const gb: f64 = mb * 1024.0;

    const value = @as(f64, @floatFromInt(bytes_per_sec));

    if (value >= gb) {
        return try std.fmt.bufPrint(buffer, "{d:.2} GB/s", .{value / gb});
    } else if (value >= mb) {
        return try std.fmt.bufPrint(buffer, "{d:.2} MB/s", .{value / mb});
    } else if (value >= kb) {
        return try std.fmt.bufPrint(buffer, "{d:.2} KB/s", .{value / kb});
    } else {
        return try std.fmt.bufPrint(buffer, "{d} B/s", .{bytes_per_sec});
    }
}

test "formatBytes: various sizes" {
    var buffer: [64]u8 = undefined;

    const b = try formatBytes(512, &buffer);
    try std.testing.expectEqualStrings("512 B", b);

    const kb = try formatBytes(2048, &buffer);
    try std.testing.expectEqualStrings("2.00 KB", kb);

    const mb = try formatBytes(5 * 1024 * 1024, &buffer);
    try std.testing.expectEqualStrings("5.00 MB", mb);

    const gb = try formatBytes(3 * 1024 * 1024 * 1024, &buffer);
    try std.testing.expectEqualStrings("3.00 GB", gb);
}

test "formatPercent: various values" {
    var buffer: [64]u8 = undefined;

    const low = try formatPercent(12.3456, &buffer);
    try std.testing.expectEqualStrings("12.3%", low);

    const high = try formatPercent(99.9, &buffer);
    try std.testing.expectEqualStrings("99.9%", high);

    const zero = try formatPercent(0.0, &buffer);
    try std.testing.expectEqualStrings("0.0%", zero);
}

test "formatBytesPerSec: various rates" {
    var buffer: [64]u8 = undefined;

    const kb_s = try formatBytesPerSec(2048, &buffer);
    try std.testing.expectEqualStrings("2.00 KB/s", kb_s);

    const mb_s = try formatBytesPerSec(10 * 1024 * 1024, &buffer);
    try std.testing.expectEqualStrings("10.00 MB/s", mb_s);
}
