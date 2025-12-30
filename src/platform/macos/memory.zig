const std = @import("std");
const bindings = @import("bindings.zig");
const types = @import("../../metrics/types.zig");

pub const MemoryCollector = struct {
    host: bindings.mach_port_t,
    page_size: u64,
    total_memory: u64,

    pub fn init() !MemoryCollector {
        const host = bindings.machHostSelf();

        // Page size on macOS: 4096 on Intel, 16384 on Apple Silicon
        const page_size: u64 = if (@import("builtin").cpu.arch == .aarch64) 16384 else 4096;

        const total_memory = try bindings.sysctlValue(
            u64,
            &[_]c_int{ bindings.CTL_HW, bindings.HW_MEMSIZE },
        );

        return MemoryCollector{
            .host = host,
            .page_size = page_size,
            .total_memory = total_memory,
        };
    }

    pub fn deinit(self: *MemoryCollector) void {
        _ = self;
    }

    pub fn collect(self: *MemoryCollector) !types.MemoryMetrics {
        var vm_stat: bindings.vm_statistics64 = undefined;
        try bindings.hostStatistics64(self.host, bindings.HOST_VM_INFO64, &vm_stat);

        const free = @as(u64, vm_stat.free_count) * self.page_size;
        const active = @as(u64, vm_stat.active_count) * self.page_size;
        const inactive = @as(u64, vm_stat.inactive_count) * self.page_size;
        const wired = @as(u64, vm_stat.wire_count) * self.page_size;

        const used = active + inactive + wired;

        return types.MemoryMetrics{
            .total = self.total_memory,
            .used = used,
            .free = free,
            .active = active,
            .inactive = inactive,
            .wired = wired,
        };
    }
};
