const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Stack = @This();

pub const StackError = error{
    StackOverflow,
    StackUnderflow,
};

pub const DataSize = enum(u1) {
    b8,
    b16,
    b32,

    pub fn toBytes(self: DataSize) usize {
        return switch (self) {
            .b8 => 1,
            .b16 => 2,
            .b32 => 4,
        };
    }
};

pub const StackOptions = struct {
    max_size: usize = 1024, // Default maximum size of the stack
};
sp: u32 = 0,
bp: u32 = 0,
data: ArrayList(u8),
max_size: usize,

pub fn init(options: StackOptions, allocator: Allocator) !Stack {
    const data = ArrayList(u8).init(allocator);
    var result = Stack{
        .sp = 0,
        .bp = 0,
        .max_size = options.max_size,
        .data = data,
    };
    try result.data.ensureTotalCapacity(options.max_size);
    return result;
}

pub fn deinit(self: *Stack) void {
    self.data.deinit();
}

pub fn push(self: *Stack, bytes: []const u8) !void {
    if (self.sp + bytes.len > self.max_size) return StackError.StackOverflow;
    try self.data.appendSlice(bytes);
    self.sp += @intCast(bytes.len);
}

pub fn pushValue(self: *Stack, comptime T: type, value: T) !void {
    const bytes = @sizeOf(T);
    if (self.sp + bytes > self.max_size) return StackError.StackOverflow;
    const slice = std.mem.asBytes(&value);
    try self.data.appendSlice(slice);
    self.sp += @intCast(bytes);
}

pub fn pop(self: *Stack, count: usize) ![]const u8 {
    if (self.sp < count) return StackError.StackUnderflow;
    self.sp -= @intCast(count);
    return self.data.items[self.sp .. self.sp + count];
}

pub fn popValue(self: *Stack, data_size: DataSize) !switch (data_size) {
    .b8 => u8,
    .b16 => u16,
} {
    const count = data_size.toBytes();
    if (self.sp < count) return StackError.StackUnderflow;
    self.sp -= @intCast(count);
    return switch (data_size) {
        .b8 => @as(u8, self.data.items[self.sp]),
        .b16 => @as(u16, std.mem.bytesAsValue(u16, self.data.items[self.sp .. self.sp + count])),
    };
}

pub fn peek(self: *Stack, data_size: DataSize) !switch (data_size) {
    .b8 => u8,
    .b16 => u16,
} {
    const count = data_size.toBytes();
    if (self.sp < count) return StackError.StackUnderflow;
    return self.data.items[self.sp - count .. self.sp];
}

pub fn dup(self: *Stack, data_size: DataSize) !void {
    const count = data_size.toBytes();
    if (self.sp + count > self.max_size) return StackError.StackOverflow;
    const slice = self.data.items[self.sp - count .. self.sp];
    try self.data.appendSlice(slice);
    self.sp += @intCast(count);
}

pub fn swap(self: *Stack, data_size: DataSize) !void {
    const count = data_size.toBytes();
    if (self.sp < count * 2) return StackError.StackUnderflow;
    const second: [count]u8 = undefined;
    @memcpy(second, self.data.items[self.sp - (count * 2) .. self.sp - count]);
    @memcpy(self.data.items[self.sp - (count * 2) .. self.sp - count], self.data.items[self.sp - count .. self.sp]);
    @memcpy(self.data.items[self.sp - count .. self.sp], second);
}

pub fn over(self: *Stack, data_size: DataSize) !void {
    const count = data_size.toBytes();
    if (self.sp < count * 2) return StackError.StackUnderflow;
    const second: [count]u8 = undefined;
    @memcpy(second, self.data.items[self.sp - (count * 2) .. self.sp - count]);
    try self.data.appendSlice(second);
    self.sp += @intCast(count);
}

pub fn clear(self: *Stack) void {
    self.sp = 0;
    self.bp = 0;
    self.data.clear();
}

pub fn size(self: *Stack) usize {
    return self.sp;
}

pub fn is_empty(self: *Stack) bool {
    return self.sp == 0;
}

pub fn is_full(self: *Stack) bool {
    return self.sp >= self.max_size;
}
