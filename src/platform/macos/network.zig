const std = @import("std");
const bindings = @import("bindings.zig");
const types = @import("../../metrics/types.zig");

pub const NetworkCollector = struct {
    allocator: std.mem.Allocator,
    previous_bytes_in: u64,
    previous_bytes_out: u64,
    previous_packets_in: u64,
    previous_packets_out: u64,
    previous_timestamp: i64,

    pub fn init(allocator: std.mem.Allocator) !NetworkCollector {
        var collector = NetworkCollector{
            .allocator = allocator,
            .previous_bytes_in = 0,
            .previous_bytes_out = 0,
            .previous_packets_in = 0,
            .previous_packets_out = 0,
            .previous_timestamp = std.time.milliTimestamp(),
        };

        const stats = try collector.getInterfaceStats();
        collector.previous_bytes_in = stats.bytes_in;
        collector.previous_bytes_out = stats.bytes_out;
        collector.previous_packets_in = stats.packets_in;
        collector.previous_packets_out = stats.packets_out;

        return collector;
    }

    pub fn deinit(self: *NetworkCollector) void {
        _ = self;
    }

    const InterfaceStats = struct {
        bytes_in: u64,
        bytes_out: u64,
        packets_in: u64,
        packets_out: u64,
    };

    fn getInterfaceStats(self: *NetworkCollector) !InterfaceStats {
        const mib = [_]c_int{ bindings.CTL_NET, bindings.PF_ROUTE, 0, 0, bindings.NET_RT_IFLIST2, 0 };

        const required_size = try bindings.sysctlBufferSize(&mib);
        const buffer = try self.allocator.alloc(u8, required_size);
        defer self.allocator.free(buffer);

        const len = try bindings.sysctlBuffer(buffer, &mib);

        var total_bytes_in: u64 = 0;
        var total_bytes_out: u64 = 0;
        var total_packets_in: u64 = 0;
        var total_packets_out: u64 = 0;

        var offset: usize = 0;
        while (offset < len) {
            if (offset + @sizeOf(bindings.if_msghdr2) > len) break;

            const msg_ptr = @as(*align(1) const bindings.if_msghdr2, @ptrCast(&buffer[offset]));
            const msg_len = msg_ptr.ifm_msglen;

            if (msg_len == 0 or msg_len > len - offset) break;

            if (msg_ptr.ifm_type == bindings.RTM_IFINFO2) {
                total_bytes_in +|= msg_ptr.ifm_data.ifi_ibytes;
                total_bytes_out +|= msg_ptr.ifm_data.ifi_obytes;
                total_packets_in +|= msg_ptr.ifm_data.ifi_ipackets;
                total_packets_out +|= msg_ptr.ifm_data.ifi_opackets;
            }

            offset += msg_len;
        }

        return InterfaceStats{
            .bytes_in = total_bytes_in,
            .bytes_out = total_bytes_out,
            .packets_in = total_packets_in,
            .packets_out = total_packets_out,
        };
    }

    pub fn collect(self: *NetworkCollector) !types.NetworkMetrics {
        const now = std.time.milliTimestamp();
        const elapsed = @as(f64, @floatFromInt(now - self.previous_timestamp)) / 1000.0;

        if (elapsed < 0.001) {
            return types.NetworkMetrics{
                .bytes_in_per_sec = 0,
                .bytes_out_per_sec = 0,
                .packets_in_per_sec = 0,
                .packets_out_per_sec = 0,
            };
        }

        const stats = try self.getInterfaceStats();

        const bytes_in_delta = if (stats.bytes_in >= self.previous_bytes_in)
            stats.bytes_in - self.previous_bytes_in
        else
            0;

        const bytes_out_delta = if (stats.bytes_out >= self.previous_bytes_out)
            stats.bytes_out - self.previous_bytes_out
        else
            0;

        const packets_in_delta = if (stats.packets_in >= self.previous_packets_in)
            stats.packets_in - self.previous_packets_in
        else
            0;

        const packets_out_delta = if (stats.packets_out >= self.previous_packets_out)
            stats.packets_out - self.previous_packets_out
        else
            0;

        const bytes_in_per_sec = @as(u64, @intFromFloat(@as(f64, @floatFromInt(bytes_in_delta)) / elapsed));
        const bytes_out_per_sec = @as(u64, @intFromFloat(@as(f64, @floatFromInt(bytes_out_delta)) / elapsed));
        const packets_in_per_sec = @as(u64, @intFromFloat(@as(f64, @floatFromInt(packets_in_delta)) / elapsed));
        const packets_out_per_sec = @as(u64, @intFromFloat(@as(f64, @floatFromInt(packets_out_delta)) / elapsed));

        self.previous_bytes_in = stats.bytes_in;
        self.previous_bytes_out = stats.bytes_out;
        self.previous_packets_in = stats.packets_in;
        self.previous_packets_out = stats.packets_out;
        self.previous_timestamp = now;

        return types.NetworkMetrics{
            .bytes_in_per_sec = bytes_in_per_sec,
            .bytes_out_per_sec = bytes_out_per_sec,
            .packets_in_per_sec = packets_in_per_sec,
            .packets_out_per_sec = packets_out_per_sec,
        };
    }
};
