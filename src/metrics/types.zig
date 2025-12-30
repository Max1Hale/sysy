const std = @import("std");

pub const CPUMetrics = struct {
    total_usage: f64,
    per_core: []f64,

    pub fn deinit(self: *CPUMetrics, allocator: std.mem.Allocator) void {
        allocator.free(self.per_core);
    }
};

pub const MemoryMetrics = struct {
    total: u64,
    used: u64,
    free: u64,
    active: u64,
    inactive: u64,
    wired: u64,

    pub fn usagePercent(self: *const MemoryMetrics) f64 {
        if (self.total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.used)) / @as(f64, @floatFromInt(self.total)) * 100.0;
    }
};

pub const DiskMetrics = struct {
    read_bytes_per_sec: u64,
    write_bytes_per_sec: u64,
    operations_per_sec: u64,
};

pub const NetworkMetrics = struct {
    bytes_in_per_sec: u64,
    bytes_out_per_sec: u64,
    packets_in_per_sec: u64,
    packets_out_per_sec: u64,
};

pub const Metrics = struct {
    cpu: CPUMetrics,
    memory: MemoryMetrics,
    disk: DiskMetrics,
    network: NetworkMetrics,
    timestamp: i64,

    pub fn deinit(self: *Metrics, allocator: std.mem.Allocator) void {
        self.cpu.deinit(allocator);
    }
};

test "MemoryMetrics: usagePercent calculation" {
    const mem = MemoryMetrics{
        .total = 16 * 1024 * 1024 * 1024,
        .used = 8 * 1024 * 1024 * 1024,
        .free = 8 * 1024 * 1024 * 1024,
        .active = 6 * 1024 * 1024 * 1024,
        .inactive = 2 * 1024 * 1024 * 1024,
        .wired = 2 * 1024 * 1024 * 1024,
    };

    const percent = mem.usagePercent();
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), percent, 0.1);
}

test "MemoryMetrics: usagePercent with zero total" {
    const mem = MemoryMetrics{
        .total = 0,
        .used = 0,
        .free = 0,
        .active = 0,
        .inactive = 0,
        .wired = 0,
    };

    const percent = mem.usagePercent();
    try std.testing.expectEqual(@as(f64, 0.0), percent);
}
