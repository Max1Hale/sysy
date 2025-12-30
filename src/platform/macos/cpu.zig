const std = @import("std");
const bindings = @import("bindings.zig");
const types = @import("../../metrics/types.zig");

pub const CPUCollector = struct {
    allocator: std.mem.Allocator,
    host: bindings.mach_port_t,
    previous_ticks: ?[]PrevTicks,
    core_count: usize,

    const PrevTicks = struct {
        user: u32,
        system: u32,
        idle: u32,
        nice: u32,
    };

    pub fn init(allocator: std.mem.Allocator) !CPUCollector {
        const host = bindings.machHostSelf();

        var collector = CPUCollector{
            .allocator = allocator,
            .host = host,
            .previous_ticks = null,
            .core_count = 0,
        };

        var initial_metrics = try collector.collect();
        initial_metrics.deinit(allocator);

        return collector;
    }

    pub fn deinit(self: *CPUCollector) void {
        if (self.previous_ticks) |ticks| {
            self.allocator.free(ticks);
        }
    }

    pub fn collect(self: *CPUCollector) !types.CPUMetrics {
        const info = try bindings.hostProcessorInfo(self.host);
        defer bindings.vmDeallocate(
            @intFromPtr(info.info_array),
            @as(usize, @intCast(info.info_count)) * @sizeOf(c_int),
        );

        const core_count = info.processor_count;

        if (self.previous_ticks == null) {
            self.core_count = core_count;
            self.previous_ticks = try self.allocator.alloc(PrevTicks, core_count);

            for (info.cpu_load, 0..) |cpu, i| {
                self.previous_ticks.?[i] = .{
                    .user = cpu.cpu_ticks[bindings.CPU_STATE_USER],
                    .system = cpu.cpu_ticks[bindings.CPU_STATE_SYSTEM],
                    .idle = cpu.cpu_ticks[bindings.CPU_STATE_IDLE],
                    .nice = cpu.cpu_ticks[bindings.CPU_STATE_NICE],
                };
            }

            const per_core = try self.allocator.alloc(f64, core_count);
            for (per_core) |*usage| {
                usage.* = 0.0;
            }

            return types.CPUMetrics{
                .total_usage = 0.0,
                .per_core = per_core,
            };
        }

        var total_usage: f64 = 0.0;
        const per_core = try self.allocator.alloc(f64, core_count);

        for (info.cpu_load, 0..) |cpu, i| {
            const prev = self.previous_ticks.?[i];

            const user_delta = cpu.cpu_ticks[bindings.CPU_STATE_USER] - prev.user;
            const system_delta = cpu.cpu_ticks[bindings.CPU_STATE_SYSTEM] - prev.system;
            const idle_delta = cpu.cpu_ticks[bindings.CPU_STATE_IDLE] - prev.idle;
            const nice_delta = cpu.cpu_ticks[bindings.CPU_STATE_NICE] - prev.nice;

            const total_ticks = user_delta + system_delta + idle_delta + nice_delta;

            if (total_ticks > 0) {
                const active_ticks = user_delta + system_delta + nice_delta;
                per_core[i] = (@as(f64, @floatFromInt(active_ticks)) / @as(f64, @floatFromInt(total_ticks))) * 100.0;
            } else {
                per_core[i] = 0.0;
            }

            total_usage += per_core[i];

            self.previous_ticks.?[i] = .{
                .user = cpu.cpu_ticks[bindings.CPU_STATE_USER],
                .system = cpu.cpu_ticks[bindings.CPU_STATE_SYSTEM],
                .idle = cpu.cpu_ticks[bindings.CPU_STATE_IDLE],
                .nice = cpu.cpu_ticks[bindings.CPU_STATE_NICE],
            };
        }

        total_usage /= @as(f64, @floatFromInt(core_count));

        return types.CPUMetrics{
            .total_usage = total_usage,
            .per_core = per_core,
        };
    }
};
