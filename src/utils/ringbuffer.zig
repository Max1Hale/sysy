const std = @import("std");

pub fn CircularBuffer(comptime T: type, comptime capacity: usize) type {
    return struct {
        data: [capacity]T,
        head: usize,
        size: usize,

        const Self = @This();

        pub fn init() Self {
            return .{
                .data = undefined,
                .head = 0,
                .size = 0,
            };
        }

        pub fn push(self: *Self, item: T) void {
            self.data[self.head] = item;
            self.head = (self.head + 1) % capacity;
            if (self.size < capacity) self.size += 1;
        }

        pub fn get(self: *const Self, index: usize) ?T {
            if (index >= self.size) return null;
            const actual_index = (self.head + capacity - self.size + index) % capacity;
            return self.data[actual_index];
        }

        pub fn len(self: *const Self) usize {
            return self.size;
        }

        pub fn clear(self: *Self) void {
            self.head = 0;
            self.size = 0;
        }

        pub fn isFull(self: *const Self) bool {
            return self.size == capacity;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.size == 0;
        }
    };
}

test "CircularBuffer: basic push and get" {
    var buf = CircularBuffer(i32, 5).init();
    try std.testing.expect(buf.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), buf.len());

    buf.push(1);
    buf.push(2);
    buf.push(3);

    try std.testing.expectEqual(@as(usize, 3), buf.len());
    try std.testing.expectEqual(@as(i32, 1), buf.get(0).?);
    try std.testing.expectEqual(@as(i32, 2), buf.get(1).?);
    try std.testing.expectEqual(@as(i32, 3), buf.get(2).?);
}

test "CircularBuffer: wrap around" {
    var buf = CircularBuffer(i32, 3).init();

    buf.push(1);
    buf.push(2);
    buf.push(3);
    try std.testing.expect(buf.isFull());

    buf.push(4);
    buf.push(5);

    try std.testing.expectEqual(@as(usize, 3), buf.len());
    try std.testing.expectEqual(@as(i32, 3), buf.get(0).?);
    try std.testing.expectEqual(@as(i32, 4), buf.get(1).?);
    try std.testing.expectEqual(@as(i32, 5), buf.get(2).?);
}

test "CircularBuffer: out of bounds access" {
    var buf = CircularBuffer(i32, 5).init();
    buf.push(1);
    buf.push(2);

    try std.testing.expect(buf.get(2) == null);
    try std.testing.expect(buf.get(10) == null);
}

test "CircularBuffer: clear" {
    var buf = CircularBuffer(i32, 5).init();
    buf.push(1);
    buf.push(2);
    buf.push(3);

    buf.clear();

    try std.testing.expect(buf.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), buf.len());
    try std.testing.expect(buf.get(0) == null);
}

test "CircularBuffer: with f64" {
    var buf = CircularBuffer(f64, 60).init();

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        buf.push(@as(f64, @floatFromInt(i)) * 0.5);
    }

    try std.testing.expectEqual(@as(usize, 60), buf.len());
    try std.testing.expect(buf.isFull());
    try std.testing.expectEqual(@as(f64, 40.0 * 0.5), buf.get(0).?);
    try std.testing.expectEqual(@as(f64, 99.0 * 0.5), buf.get(59).?);
}
