const std = @import("std");
const c = @cImport({
    @cInclude("sys/sysctl.h");
    @cInclude("libproc.h");
    @cInclude("sys/proc_info.h");
    @cInclude("mach/mach_time.h");
});

pub const ProcessSortMode = enum {
    memory,
    cpu,
};

pub const ProcessInfo = struct {
    pid: i32,
    name: [256]u8,
    name_len: usize,
    cpu_percent: f64,
    mem_bytes: u64,
    state: u32,

    pub fn getName(self: *const ProcessInfo) []const u8 {
        return self.name[0..self.name_len];
    }
};

const CPUTimeInfo = struct {
    total_time: u64,
    timestamp: i128,
};

pub const ProcessCollector = struct {
    allocator: std.mem.Allocator,
    process_list: std.ArrayList(ProcessInfo),
    cpu_times: std.AutoHashMap(i32, CPUTimeInfo),
    last_update: i128,
    timebase: c.mach_timebase_info_data_t,

    pub fn init(allocator: std.mem.Allocator) !ProcessCollector {
        var timebase: c.mach_timebase_info_data_t = undefined;
        _ = c.mach_timebase_info(&timebase);

        return .{
            .allocator = allocator,
            .process_list = .{},
            .cpu_times = std.AutoHashMap(i32, CPUTimeInfo).init(allocator),
            .last_update = std.time.nanoTimestamp(),
            .timebase = timebase,
        };
    }

    pub fn deinit(self: *ProcessCollector) void {
        self.process_list.deinit(self.allocator);
        self.cpu_times.deinit();
    }

    pub fn collect(self: *ProcessCollector, sort_mode: ProcessSortMode) ![]ProcessInfo {
        self.process_list.clearRetainingCapacity();

        const current_time = std.time.nanoTimestamp();
        const time_delta_ns = current_time - self.last_update;

        // Get number of processes
        const num_pids = c.proc_listpids(c.PROC_ALL_PIDS, 0, null, 0);
        if (num_pids <= 0) return error.FailedToGetProcessCount;

        const max_pids = @as(usize, @intCast(@divTrunc(num_pids, @as(c_int, @intCast(@sizeOf(i32))))));
        const pids = try self.allocator.alloc(i32, max_pids);
        defer self.allocator.free(pids);

        const bytes_used = c.proc_listpids(c.PROC_ALL_PIDS, 0, @ptrCast(pids.ptr), @intCast(pids.len * @sizeOf(i32)));
        if (bytes_used <= 0) return error.FailedToListProcesses;

        const actual_pids = @as(usize, @intCast(bytes_used)) / @sizeOf(i32);

        for (pids[0..actual_pids]) |pid| {
            if (pid == 0) continue;

            var info = ProcessInfo{
                .pid = pid,
                .name = undefined,
                .name_len = 0,
                .cpu_percent = 0.0,
                .mem_bytes = 0,
                .state = 0,
            };

            // Get process name
            var pathbuf: [c.PROC_PIDPATHINFO_MAXSIZE]u8 = undefined;
            const path_len = c.proc_pidpath(pid, &pathbuf, c.PROC_PIDPATHINFO_MAXSIZE);

            if (path_len > 0) {
                const path = pathbuf[0..@as(usize, @intCast(path_len))];
                // Extract basename
                var i = path.len;
                while (i > 0) : (i -= 1) {
                    if (path[i - 1] == '/') break;
                }
                const basename = path[i..];
                const copy_len = @min(basename.len, info.name.len - 1);
                @memcpy(info.name[0..copy_len], basename[0..copy_len]);
                info.name_len = copy_len;
            } else {
                // Fallback to getting name directly
                @memcpy(info.name[0..8], "[unknown");
                info.name[8] = ']';
                info.name_len = 9;
            }

            // Get process task info for memory and CPU
            var task_info: c.proc_taskallinfo = undefined;
            const ret = c.proc_pidinfo(pid, c.PROC_PIDTASKALLINFO, 0, &task_info, @sizeOf(c.proc_taskallinfo));

            if (ret == @sizeOf(c.proc_taskallinfo)) {
                info.mem_bytes = task_info.ptinfo.pti_resident_size;
                info.state = task_info.pbsd.pbi_status;

                // Calculate CPU percentage
                // Note: pti_total_user and pti_total_system are in Mach absolute time units
                const total_time_mach = task_info.ptinfo.pti_total_user + task_info.ptinfo.pti_total_system;

                if (self.cpu_times.get(pid)) |prev_info| {
                    if (total_time_mach > prev_info.total_time) {
                        const time_diff_mach = total_time_mach - prev_info.total_time;
                        // Convert Mach time to nanoseconds
                        const time_diff_ns = time_diff_mach * self.timebase.numer / self.timebase.denom;

                        if (time_delta_ns > 0) {
                            // CPU percent = (cpu_time_used / wall_time_elapsed) * 100
                            const time_diff_f = @as(f64, @floatFromInt(time_diff_ns));
                            const time_delta_f = @as(f64, @floatFromInt(time_delta_ns));
                            info.cpu_percent = (time_diff_f / time_delta_f) * 100.0;
                        }
                    }
                } else {
                    info.cpu_percent = 0.0;
                }

                // Store current CPU time for next iteration (in Mach units)
                try self.cpu_times.put(pid, .{
                    .total_time = total_time_mach,
                    .timestamp = current_time,
                });
            }

            try self.process_list.append(self.allocator, info);
        }

        self.last_update = current_time;

        // Sort by the specified mode (descending)
        switch (sort_mode) {
            .memory => {
                std.mem.sort(ProcessInfo, self.process_list.items, {}, struct {
                    fn lessThan(_: void, a: ProcessInfo, b: ProcessInfo) bool {
                        return a.mem_bytes > b.mem_bytes;
                    }
                }.lessThan);
            },
            .cpu => {
                std.mem.sort(ProcessInfo, self.process_list.items, {}, struct {
                    fn lessThan(_: void, a: ProcessInfo, b: ProcessInfo) bool {
                        return a.cpu_percent > b.cpu_percent;
                    }
                }.lessThan);
            },
        }

        return self.process_list.items;
    }
};
