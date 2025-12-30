const std = @import("std");
const types = @import("../../metrics/types.zig");

pub const DiskCollector = struct {
    previous_timestamp: i64,

    pub fn init() !DiskCollector {
        return DiskCollector{
            .previous_timestamp = std.time.milliTimestamp(),
        };
    }

    pub fn deinit(self: *DiskCollector) void {
        _ = self;
    }

    pub fn collect(self: *DiskCollector) !types.DiskMetrics {
        _ = self;
        return types.DiskMetrics{
            .read_bytes_per_sec = 0,
            .write_bytes_per_sec = 0,
            .operations_per_sec = 0,
        };
    }
};
