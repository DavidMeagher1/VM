const std = @import("std");
const Allocator = std.mem.Allocator;
const CPU = @import("cpu.zig");
const MemoryFrame = @import("memory.zig").MemoryFrame;

pub fn Hardware(
    comptime Context: type,
    comptime HardwareError: type,
    comptime update_fn: *const fn (context: *Context, memory: *MemoryFrame) anyerror!void,
) type {
    return struct {
        const Self = @This();
        pub const Error = HardwareError;
        context: Context,
        memory: MemoryFrame = MemoryFrame{
            .address = 0,
            .data = &[_]u8{},
        },
        pub fn init(context: Context) !Self {
            return Self{
                .context = context,
            };
        }

        pub fn update(self: *Self) !void {
            // Call the update function with the context
            try update_fn(&self.context, &self.memory);
        }
    };
}
