const std = @import("std");

pub const Mode = enum {
    snapshot,
    continuous,
};

pub const Args = struct {
    mode: Mode,

    pub fn parse(allocator: std.mem.Allocator) !Args {
        var args = try std.process.argsWithAllocator(allocator);
        defer args.deinit();

        _ = args.next();

        var mode: ?Mode = null;

        while (args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--snapshot")) {
                if (mode != null) return error.DuplicateMode;
                mode = .snapshot;
            } else if (std.mem.eql(u8, arg, "--continuous")) {
                if (mode != null) return error.DuplicateMode;
                mode = .continuous;
            } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                printHelp();
                return error.HelpRequested;
            } else {
                std.debug.print("Unknown argument: {s}\n", .{arg});
                return error.InvalidArgument;
            }
        }

        return Args{
            .mode = mode orelse .continuous,
        };
    }

    fn printHelp() void {
        const help =
            \\sysy - System Monitor
            \\
            \\Usage: sysy [OPTIONS]
            \\
            \\Options:
            \\  --snapshot      Show current metrics and exit
            \\  --continuous    Continuously update metrics (default)
            \\  -h, --help      Show this help message
            \\
        ;
        std.debug.print("{s}\n", .{help});
    }
};

test "Args: default to continuous" {
    var argv = [_][]const u8{"sysy"};
    const parsed = try parseFromSlice(&argv);
    try std.testing.expectEqual(Mode.continuous, parsed.mode);
}

test "Args: parse snapshot" {
    var argv = [_][]const u8{ "sysy", "--snapshot" };
    const parsed = try parseFromSlice(&argv);
    try std.testing.expectEqual(Mode.snapshot, parsed.mode);
}

test "Args: parse continuous" {
    var argv = [_][]const u8{ "sysy", "--continuous" };
    const parsed = try parseFromSlice(&argv);
    try std.testing.expectEqual(Mode.continuous, parsed.mode);
}

fn parseFromSlice(argv: []const []const u8) !Args {
    var mode: ?Mode = null;

    for (argv[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--snapshot")) {
            if (mode != null) return error.DuplicateMode;
            mode = .snapshot;
        } else if (std.mem.eql(u8, arg, "--continuous")) {
            if (mode != null) return error.DuplicateMode;
            mode = .continuous;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return error.HelpRequested;
        } else {
            return error.InvalidArgument;
        }
    }

    return Args{
        .mode = mode orelse .continuous,
    };
}
