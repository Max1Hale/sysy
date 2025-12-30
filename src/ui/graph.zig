const std = @import("std");
const vaxis = @import("vaxis");

pub const sparkline_chars = [_]u21{ ' ', '▁', '▂', '▃', '▄', '▅', '▆', '▇', '█' };

/// Render a multi-line graph with axes and labels
/// height: number of rows for the graph (excluding axis labels)
/// Returns the number of lines used
pub fn renderMultiLineGraph(
    win: *vaxis.Window,
    data: []const f64,
    max_value: f64,
    row_start: usize,
    height: usize,
    alloc: std.mem.Allocator,
) !usize {
    if (data.len == 0 or height == 0) return 0;

    const graph_width = @min(data.len, 60);
    var rows_used: usize = 0;

    // Draw top line (100%)
    const top_label = try std.fmt.allocPrint(alloc, "100% ┤", .{});
    _ = win.print(&.{.{ .text = top_label }}, .{ .row_offset = @intCast(row_start + rows_used) });

    // Draw bars for top line
    var top_bar_buf: [128]u8 = undefined;
    var top_stream = std.io.fixedBufferStream(&top_bar_buf);
    for (data[0..graph_width]) |value| {
        const normalized = if (max_value > 0.0) @min(value / max_value, 1.0) else 0.0;
        const in_top_quarter = normalized >= 0.75;
        try top_stream.writer().writeAll(if (in_top_quarter) "█" else " ");
    }
    const top_bar = try std.fmt.allocPrint(alloc, "{s}", .{top_stream.getWritten()});
    _ = win.print(&.{.{ .text = top_bar }}, .{ .row_offset = @intCast(row_start + rows_used), .col_offset = 6 });
    rows_used += 1;

    // Draw middle line (50%)
    const mid_label = try std.fmt.allocPrint(alloc, " 50% ┤", .{});
    _ = win.print(&.{.{ .text = mid_label }}, .{ .row_offset = @intCast(row_start + rows_used) });

    var mid_bar_buf: [128]u8 = undefined;
    var mid_stream = std.io.fixedBufferStream(&mid_bar_buf);
    for (data[0..graph_width]) |value| {
        const normalized = if (max_value > 0.0) @min(value / max_value, 1.0) else 0.0;
        const in_middle = normalized >= 0.25 and normalized < 0.75;
        try mid_stream.writer().writeAll(if (in_middle or normalized >= 0.75) "█" else " ");
    }
    const mid_bar = try std.fmt.allocPrint(alloc, "{s}", .{mid_stream.getWritten()});
    _ = win.print(&.{.{ .text = mid_bar }}, .{ .row_offset = @intCast(row_start + rows_used), .col_offset = 6 });
    rows_used += 1;

    // Draw bottom line (0%)
    const bot_label = try std.fmt.allocPrint(alloc, "  0% └", .{});
    _ = win.print(&.{.{ .text = bot_label }}, .{ .row_offset = @intCast(row_start + rows_used) });

    var bot_bar_buf: [128]u8 = undefined;
    var bot_stream = std.io.fixedBufferStream(&bot_bar_buf);
    for (0..graph_width) |_| {
        try bot_stream.writer().writeAll("─");
    }
    const bot_bar = try std.fmt.allocPrint(alloc, "{s}", .{bot_stream.getWritten()});
    _ = win.print(&.{.{ .text = bot_bar }}, .{ .row_offset = @intCast(row_start + rows_used), .col_offset = 6 });
    rows_used += 1;

    return rows_used;
}

pub fn renderSparkline(data: []const f64, max_value: f64, buffer: []u8) ![]const u8 {
    if (data.len == 0) return buffer[0..0];

    var stream = std.io.fixedBufferStream(buffer);
    var writer = stream.writer();

    for (data) |value| {
        const normalized = if (max_value > 0.0)
            @min(value / max_value, 1.0)
        else
            0.0;

        const index = @as(usize, @intFromFloat(normalized * @as(f64, @floatFromInt(sparkline_chars.len - 1))));
        const char = sparkline_chars[@min(index, sparkline_chars.len - 1)];

        var utf8_buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(char, &utf8_buf);
        try writer.writeAll(utf8_buf[0..len]);
    }

    return stream.getWritten();
}

pub fn renderBar(percent: f64, width: usize, buffer: []u8) ![]const u8 {
    if (width == 0) return buffer[0..0];

    const filled_count = @as(usize, @intFromFloat(@min(percent / 100.0, 1.0) * @as(f64, @floatFromInt(width))));

    var stream = std.io.fixedBufferStream(buffer);
    var writer = stream.writer();

    var i: usize = 0;
    while (i < filled_count) : (i += 1) {
        try writer.writeAll("█");
    }
    while (i < width) : (i += 1) {
        try writer.writeAll("░");
    }

    return stream.getWritten();
}

test "renderSparkline: basic" {
    var buffer: [256]u8 = undefined;
    const data = [_]f64{ 0.0, 25.0, 50.0, 75.0, 100.0 };
    const result = try renderSparkline(&data, 100.0, &buffer);
    try std.testing.expect(result.len > 0);
}

test "renderSparkline: empty data" {
    var buffer: [256]u8 = undefined;
    const data = [_]f64{};
    const result = try renderSparkline(&data, 100.0, &buffer);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "renderBar: full" {
    var buffer: [256]u8 = undefined;
    const result = try renderBar(100.0, 10, &buffer);
    try std.testing.expect(result.len > 0);
}

test "renderBar: half" {
    var buffer: [256]u8 = undefined;
    const result = try renderBar(50.0, 10, &buffer);
    try std.testing.expect(result.len > 0);
}
