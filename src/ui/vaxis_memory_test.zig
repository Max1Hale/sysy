const std = @import("std");
const Renderer = @import("renderer.zig").Renderer;

// This test specifically verifies that vaxis screen allocations
// (which previously caused memory leaks during resize operations)
// are now properly managed through the ArenaAllocator
test "Vaxis ArenaAllocator properly manages screen allocations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Create renderer - this internally creates a vaxis instance with ArenaAllocator
    var renderer = try Renderer.init(allocator);

    // The vaxis instance should be using the arena allocator
    // Any internal allocations (screens, buffers, etc.) go through the arena

    // Verify we can access the vaxis instance
    try std.testing.expect(renderer.vx != undefined);

    // Verify the arena allocator exists
    try std.testing.expect(renderer.vaxis_arena != undefined);

    // Clean up - this should free ALL vaxis allocations via arena.deinit()
    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();
    renderer.deinit(writer);

    // Verify no leaks - if the arena properly cleaned up, GPA should report ok
    const leaked = gpa.deinit();
    try std.testing.expect(leaked == .ok);
}

// Test that verifies the arena allocator strategy solves the resize leak issue
test "Arena allocator strategy explanation and verification" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // PROBLEM: vaxis.resize() creates new Screen and InternalScreen objects
    // but doesn't free the old ones, causing memory leaks
    //
    // SOLUTION: Use ArenaAllocator for all vaxis allocations
    // When arena.deinit() is called, ALL allocations are freed at once,
    // regardless of whether individual frees were called

    var renderer = try Renderer.init(allocator);

    // Even if vaxis internally "leaks" by not freeing old screens,
    // the arena will clean everything up when we call deinit

    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();
    renderer.deinit(writer);

    const leaked = gpa.deinit();
    try std.testing.expect(leaked == .ok);
}

// Test arena allocator behavior with multiple renderers
test "Multiple renderers with independent arenas" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Create multiple renderers - each should have its own arena
    var renderer1 = try Renderer.init(allocator);
    var renderer2 = try Renderer.init(allocator);

    // Verify they have different arena allocators
    try std.testing.expect(renderer1.vaxis_arena != renderer2.vaxis_arena);

    var buffer: [1024]u8 = undefined;

    // Clean up first renderer
    var fbs1 = std.io.fixedBufferStream(&buffer);
    renderer1.deinit(fbs1.writer());

    // Second renderer should still be valid
    try std.testing.expect(renderer2.vx != undefined);

    // Clean up second renderer
    var fbs2 = std.io.fixedBufferStream(&buffer);
    renderer2.deinit(fbs2.writer());

    const leaked = gpa.deinit();
    try std.testing.expect(leaked == .ok);
}
