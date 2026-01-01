const std = @import("std");
const c = @cImport({
    @cInclude("sys/sysctl.h");
    @cInclude("libproc.h");
    @cInclude("sys/proc_info.h");
});

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

pub const ProcessCollector = struct {
    allocator: std.mem.Allocator,
    process_list: std.ArrayList(ProcessInfo),

    pub fn init(allocator: std.mem.Allocator) !ProcessCollector {
        return .{
            .allocator = allocator,
            .process_list = .{},
        };
    }

    pub fn deinit(self: *ProcessCollector) void {
        self.process_list.deinit(self.allocator);
    }

    pub fn collect(self: *ProcessCollector) ![]ProcessInfo {
        self.process_list.clearRetainingCapacity();

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
                // CPU is in nanoseconds, we'll need to calculate percentage in a future iteration
                info.cpu_percent = 0.0; // Placeholder for now
                info.state = task_info.pbsd.pbi_status;
            }

            try self.process_list.append(self.allocator, info);
        }

        // Sort by memory usage (descending)
        std.mem.sort(ProcessInfo, self.process_list.items, {}, struct {
            fn lessThan(_: void, a: ProcessInfo, b: ProcessInfo) bool {
                return a.mem_bytes > b.mem_bytes;
            }
        }.lessThan);

        return self.process_list.items;
    }
};
