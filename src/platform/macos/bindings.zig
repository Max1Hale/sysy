const std = @import("std");

pub const mach_port_t = c_uint;
pub const host_t = mach_port_t;
pub const host_flavor_t = c_int;
pub const host_info_t = *c_int;
pub const host_info64_t = *u64;
pub const mach_msg_type_number_t = c_uint;
pub const natural_t = c_uint;
pub const processor_flavor_t = c_int;
pub const processor_info_array_t = *c_int;
pub const kern_return_t = c_int;

pub const KERN_SUCCESS: kern_return_t = 0;

pub const HOST_VM_INFO64: host_flavor_t = 4;
pub const HOST_VM_INFO64_COUNT: mach_msg_type_number_t = @sizeOf(vm_statistics64) / @sizeOf(c_int);

pub const PROCESSOR_CPU_LOAD_INFO: processor_flavor_t = 2;
pub const CPU_STATE_USER: usize = 0;
pub const CPU_STATE_SYSTEM: usize = 1;
pub const CPU_STATE_IDLE: usize = 2;
pub const CPU_STATE_NICE: usize = 3;
pub const CPU_STATE_MAX: usize = 4;

pub const vm_statistics64 = extern struct {
    free_count: c_uint,
    active_count: c_uint,
    inactive_count: c_uint,
    wire_count: c_uint,
    zero_fill_count: u64,
    reactivations: u64,
    pageins: u64,
    pageouts: u64,
    faults: u64,
    cow_faults: u64,
    lookups: u64,
    hits: u64,
    purges: u64,
    purgeable_count: c_uint,
    speculative_count: c_uint,
    decompressions: u64,
    compressions: u64,
    swapins: u64,
    swapouts: u64,
    compressor_page_count: c_uint,
    throttled_count: c_uint,
    external_page_count: c_uint,
    internal_page_count: c_uint,
    total_uncompressed_pages_in_compressor: u64,
};

pub const processor_cpu_load_info = extern struct {
    cpu_ticks: [CPU_STATE_MAX]c_uint,
};

pub const CTL_NET: c_int = 4;
pub const PF_ROUTE: c_int = 17;
pub const NET_RT_IFLIST2: c_int = 6;

pub const CTL_HW: c_int = 6;
pub const HW_MEMSIZE: c_int = 24;
pub const HW_PAGESIZE: c_int = 7;

pub const RTM_IFINFO2: u8 = 0x12;

pub const if_msghdr2 = extern struct {
    ifm_msglen: c_ushort,
    ifm_version: u8,
    ifm_type: u8,
    ifm_addrs: c_int,
    ifm_flags: c_int,
    ifm_index: c_ushort,
    ifm_snd_len: c_int,
    ifm_snd_maxlen: c_int,
    ifm_snd_drops: c_int,
    ifm_timer: c_int,
    ifm_data: if_data64,
};

pub const if_data64 = extern struct {
    ifi_type: u8,
    ifi_typelen: u8,
    ifi_physical: u8,
    ifi_addrlen: u8,
    ifi_hdrlen: u8,
    ifi_recvquota: u8,
    ifi_xmitquota: u8,
    ifi_unused1: u8,
    ifi_mtu: u32,
    ifi_metric: u32,
    ifi_baudrate: u64,
    ifi_ipackets: u64,
    ifi_ierrors: u64,
    ifi_opackets: u64,
    ifi_oerrors: u64,
    ifi_collisions: u64,
    ifi_ibytes: u64,
    ifi_obytes: u64,
    ifi_imcasts: u64,
    ifi_omcasts: u64,
    ifi_iqdrops: u64,
    ifi_noproto: u64,
    ifi_recvtiming: u32,
    ifi_xmittiming: u32,
    ifi_lastchange: timeval32,
};

pub const timeval32 = extern struct {
    tv_sec: i32,
    tv_usec: i32,
};

extern "c" fn mach_host_self() mach_port_t;

extern "c" fn host_statistics64(
    host_priv: host_t,
    flavor: host_flavor_t,
    host_info_out: host_info64_t,
    host_info_outCnt: *mach_msg_type_number_t,
) kern_return_t;

extern "c" fn host_processor_info(
    host: mach_port_t,
    flavor: processor_flavor_t,
    out_processor_count: *natural_t,
    out_processor_info: *processor_info_array_t,
    out_processor_info_count: *mach_msg_type_number_t,
) kern_return_t;

extern "c" fn vm_deallocate(
    target_task: mach_port_t,
    address: usize,
    size: usize,
) kern_return_t;

extern "c" fn sysctl(
    name: [*c]const c_int,
    namelen: c_uint,
    oldp: ?*anyopaque,
    oldlenp: *usize,
    newp: ?*const anyopaque,
    newlen: usize,
) c_int;

extern "c" fn sysctlbyname(
    name: [*:0]const u8,
    oldp: ?*anyopaque,
    oldlenp: *usize,
    newp: ?*const anyopaque,
    newlen: usize,
) c_int;

pub fn machHostSelf() mach_port_t {
    return mach_host_self();
}

pub fn hostStatistics64(host_priv: host_t, flavor: host_flavor_t, host_info: *vm_statistics64) !void {
    var count: mach_msg_type_number_t = HOST_VM_INFO64_COUNT;
    const result = host_statistics64(
        host_priv,
        flavor,
        @ptrCast(host_info),
        &count,
    );
    if (result != KERN_SUCCESS) return error.HostStatisticsFailed;
}

pub fn hostProcessorInfo(host: mach_port_t) !struct {
    processor_count: natural_t,
    cpu_load: []processor_cpu_load_info,
    info_array: processor_info_array_t,
    info_count: mach_msg_type_number_t,
} {
    var processor_count: natural_t = undefined;
    var info_array: processor_info_array_t = undefined;
    var info_count: mach_msg_type_number_t = undefined;

    const result = host_processor_info(
        host,
        PROCESSOR_CPU_LOAD_INFO,
        &processor_count,
        &info_array,
        &info_count,
    );

    if (result != KERN_SUCCESS) return error.HostProcessorInfoFailed;

    const cpu_load_ptr: [*]processor_cpu_load_info = @ptrCast(@alignCast(info_array));
    const cpu_load = cpu_load_ptr[0..processor_count];

    return .{
        .processor_count = processor_count,
        .cpu_load = cpu_load,
        .info_array = info_array,
        .info_count = info_count,
    };
}

pub fn vmDeallocate(address: usize, size: usize) void {
    _ = vm_deallocate(machHostSelf(), address, size);
}

pub fn sysctlValue(comptime T: type, name: []const c_int) !T {
    var value: T = undefined;
    var len: usize = @sizeOf(T);
    const result = sysctl(
        name.ptr,
        @intCast(name.len),
        &value,
        &len,
        null,
        0,
    );
    if (result != 0) return error.SysctlFailed;
    return value;
}

pub fn sysctlByName(comptime T: type, name: [*:0]const u8) !T {
    var value: T = undefined;
    var len: usize = @sizeOf(T);
    const result = sysctlbyname(
        name,
        &value,
        &len,
        null,
        0,
    );
    if (result != 0) return error.SysctlFailed;
    return value;
}

pub fn sysctlBuffer(buffer: []u8, name: []const c_int) !usize {
    var len: usize = buffer.len;
    const result = sysctl(
        name.ptr,
        @intCast(name.len),
        buffer.ptr,
        &len,
        null,
        0,
    );
    if (result != 0) {
        std.debug.print("sysctl failed with result: {}\n", .{result});
        return error.SysctlFailed;
    }
    return len;
}

pub fn sysctlBufferSize(name: []const c_int) !usize {
    var len: usize = 0;
    const result = sysctl(
        name.ptr,
        @intCast(name.len),
        null,
        &len,
        null,
        0,
    );
    if (result != 0) return error.SysctlFailed;
    return len;
}
