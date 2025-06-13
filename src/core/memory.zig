// we are going to make a memory structure for the VM
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Memory = struct {
    allocator: *Allocator,
    data: []u8,

    pub fn init(allocator: *Allocator, size: usize) !Memory {
        const memory = try allocator.alloc(u8, size);
        return Memory{
            .allocator = allocator,
            .data = memory,
        };
    }

    pub fn deinit(self: *Memory) void {
        self.allocator.free(self.data);
    }
};
