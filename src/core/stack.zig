const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Stack = @This();

pub const StackError = error{
    StackOverflow,
    StackUnderflow,
};

pub const DataSize = enum(u2) {
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

pub const Value = union(DataSize) {
    b8: u8,
    b16: u16,
    b32: u32,

    pub fn asU32(self: Value) u32 {
        return switch (self) {
            .b8 => @as(u32, self.b8),
            .b16 => @as(u32, self.b16),
            .b32 => self.b32,
        };
    }
    pub fn tag(self: Value) DataSize {
        return switch (self) {
            .b8 => DataSize.b8,
            .b16 => DataSize.b16,
            .b32 => DataSize.b32,
        };
    }

    pub fn size(self: Value) usize {
        return switch (self.tag()) {
            .b8 => @sizeOf(u8),
            .b16 => @sizeOf(u16),
            .b32 => @sizeOf(u32),
        };
    }

    pub fn add(self: Value, other: Value) Value {
        return switch (self.tag()) {
            .b8 => Value{ .b8 = self.b8 + other.b8 },
            .b16 => Value{ .b16 = self.b16 + other.b16 },
            .b32 => Value{ .b32 = self.b32 + other.b32 },
        };
    }
    pub fn sub(self: Value, other: Value) Value {
        return switch (self.tag()) {
            .b8 => Value{ .b8 = self.b8 - other.b8 },
            .b16 => Value{ .b16 = self.b16 - other.b16 },
            .b32 => Value{ .b32 = self.b32 - other.b32 },
        };
    }
    pub fn mul(self: Value, other: Value) Value {
        return switch (self.tag()) {
            .b8 => Value{ .b8 = self.b8 * other.b8 },
            .b16 => Value{ .b16 = self.b16 * other.b16 },
            .b32 => Value{ .b32 = self.b32 * other.b32 },
        };
    }
    pub fn div(self: Value, other: Value) Value {
        return switch (self.tag()) {
            .b8 => Value{ .b8 = self.b8 / other.b8 },
            .b16 => Value{ .b16 = self.b16 / other.b16 },
            .b32 => Value{ .b32 = self.b32 / other.b32 },
        };
    }
    pub fn @"and"(self: Value, other: Value) Value {
        return switch (self.tag()) {
            .b8 => Value{ .b8 = self.b8 & other.b8 },
            .b16 => Value{ .b16 = self.b16 & other.b16 },
            .b32 => Value{ .b32 = self.b32 & other.b32 },
        };
    }
    pub fn @"or"(self: Value, other: Value) Value {
        return switch (self.tag()) {
            .b8 => Value{ .b8 = self.b8 | other.b8 },
            .b16 => Value{ .b16 = self.b16 | other.b16 },
            .b32 => Value{ .b32 = self.b32 | other.b32 },
        };
    }
    pub fn xor(self: Value, other: Value) Value {
        return switch (self.tag()) {
            .b8 => Value{ .b8 = self.b8 ^ other.b8 },
            .b16 => Value{ .b16 = self.b16 ^ other.b16 },
            .b32 => Value{ .b32 = self.b32 ^ other.b32 },
        };
    }
    pub fn not(self: Value) Value {
        return switch (self.tag()) {
            .b8 => Value{ .b8 = ~self.b8 },
            .b16 => Value{ .b16 = ~self.b16 },
            .b32 => Value{ .b32 = ~self.b32 },
        };
    }
    pub fn shl(self: Value, amount: Value) Value {
        return switch (self.tag()) {
            .b8 => Value{ .b8 = self.b8 << @truncate(amount.b8) },
            .b16 => Value{ .b16 = self.b16 << @truncate(amount.b16) },
            .b32 => Value{ .b32 = self.b32 << @truncate(amount.b32) },
        };
    }
    pub fn shr(self: Value, amount: Value) Value {
        return switch (self.tag()) {
            .b8 => Value{ .b8 = self.b8 >> @truncate(amount.b8) },
            .b16 => Value{ .b16 = self.b16 >> @truncate(amount.b16) },
            .b32 => Value{ .b32 = self.b32 >> @truncate(amount.b32) },
        };
    }

    pub fn fx_add(self: Value, other: Value) Value {
        return switch (self.tag()) {
            .b8 => Value{ .b8 = self.b8 + other.b8 },
            .b16 => Value{ .b16 = self.b16 + other.b16 },
            .b32 => Value{ .b32 = self.b32 + other.b32 },
        };
    }

    pub fn fx_sub(self: Value, other: Value) Value {
        return switch (self.tag()) {
            .b8 => Value{ .b8 = self.b8 - other.b8 },
            .b16 => Value{ .b16 = self.b16 - other.b16 },
            .b32 => Value{ .b32 = self.b32 - other.b32 },
        };
    }

    pub fn fx_mul(self: Value, other: Value) Value {
        // this needs to correct for scale factors
        // for example if we have 8.8 fixed point and we multiply two values
        // we need to shift the result right by 8 bits
        const scale: u32 = switch (self.tag()) {
            .b16 => 1 << 8, // 8.8 fixed point for 32-bit ints
            .b32 => 1 << 16, // 16.16 fixed point for 64-bit ints
            else => return Value{ .b8 = 0 }, // unsupported type
        };
        return switch (self.tag()) {
            .b16 => Value{ .b16 = @divTrunc(self.b16 * other.b16, @as(u16, @truncate(scale))) },
            .b32 => Value{ .b32 = @divTrunc(self.b32 * other.asU32(), scale) },
            else => unreachable,
        };
    }

    pub fn fx_div(self: Value, other: Value) Value {
        // this needs to correct for scale factors
        // for example if we have 8.8 fixed point and we divide two values
        // we need to shift the result left by 8 bits
        const scale: u32 = switch (self.tag()) {
            .b16 => 1 << 8, // 8.8 fixed point for 32-bit ints
            .b32 => 1 << 16, // 16.16 fixed point for 64-bit ints
            else => return Value{ .b8 = 0 }, // unsupported type
        };
        if (other.asU32() == 0) return Value{ .b8 = 0 }; // division by zero
        return switch (self.tag()) {
            .b16 => Value{ .b16 = @divTrunc(self.b16 * @as(u16, @truncate(scale)), other.b16) },
            .b32 => Value{ .b32 = @divTrunc(self.b32 * scale, other.asU32()) },
            else => unreachable,
        };
    }

    pub inline fn equal(self: Value, other: Value) bool {
        return switch (self.tag()) {
            .b8 => self.b8 == other.b8,
            .b16 => self.b16 == other.b16,
            .b32 => self.b32 == other.b32,
        };
    }

    pub inline fn lessThan(self: Value, other: Value) bool {
        return switch (self.tag()) {
            .b8 => self.b8 < other.b8,
            .b16 => self.b16 < other.b16,
            .b32 => self.b32 < other.b32,
        };
    }

    pub inline fn lessThanEqual(self: Value, other: Value) bool {
        return switch (self.tag()) {
            .b8 => self.b8 <= other.b8,
            .b16 => self.b16 <= other.b16,
            .b32 => self.b32 <= other.b32,
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

pub fn pushValue(self: *Stack, value: Value) !void {
    const bytes = value.size();
    if (self.sp + bytes > self.max_size) return StackError.StackOverflow;
    // check if we need to grow the stack
    // if we are at the end of the stack and we need to grow it
    // we need to append the value to the end of the stack
    // if we are not at the end of the stack we need to copy the value to the end of the stack
    const to_end_of_stack = self.data.items.len - self.sp;
    if (to_end_of_stack < bytes) {
        // first we need to copy the value to the end of the stack
        switch (value.tag()) {
            .b8 => @memcpy(self.data.items[self.sp .. self.sp + to_end_of_stack], std.mem.asBytes(&value.b8)[0..to_end_of_stack]),
            .b16 => @memcpy(self.data.items[self.sp .. self.sp + to_end_of_stack], std.mem.asBytes(&value.b16)[0..to_end_of_stack]),
            .b32 => @memcpy(self.data.items[self.sp .. self.sp + to_end_of_stack], std.mem.asBytes(&value.b32)[0..to_end_of_stack]),
        }
        // we need to grow the stack
        try self.data.ensureTotalCapacity(self.sp + bytes);
        // now we add the rest of the value to the end of the stack
        switch (value.tag()) {
            .b8 => try self.data.appendSlice(std.mem.asBytes(&value.b8)[to_end_of_stack..bytes]),
            .b16 => try self.data.appendSlice(std.mem.asBytes(&value.b16)[to_end_of_stack..bytes]),
            .b32 => try self.data.appendSlice(std.mem.asBytes(&value.b32)[to_end_of_stack..bytes]),
        }
    } else {
        // we need to copy the value to the end of the stack
        switch (value.tag()) {
            .b8 => @memcpy(self.data.items[self.sp .. self.sp + bytes], std.mem.asBytes(&value.b8)),
            .b16 => @memcpy(self.data.items[self.sp .. self.sp + bytes], std.mem.asBytes(&value.b16)),
            .b32 => @memcpy(self.data.items[self.sp .. self.sp + bytes], std.mem.asBytes(&value.b32)),
        }
    }
    self.sp += @intCast(bytes);
}

pub fn pop(self: *Stack, count: usize) ![]const u8 {
    if (self.sp < count) return StackError.StackUnderflow;
    self.sp -= @intCast(count);
    return self.data.items[self.sp .. self.sp + count];
}

pub fn popValue(self: *Stack, data_size: DataSize) !Value {
    const bytes = data_size.toBytes();
    if (self.sp < bytes) return StackError.StackUnderflow;
    self.sp -= @intCast(bytes);
    var value: Value = undefined;
    const slice = self.data.items[self.sp .. self.sp + bytes];
    switch (data_size) {
        .b8 => value = Value{ .b8 = std.mem.bytesAsValue(u8, slice).* },
        .b16 => value = Value{ .b16 = std.mem.bytesAsValue(u16, slice).* },
        .b32 => value = Value{ .b32 = std.mem.bytesAsValue(u32, slice).* },
    }
    return value;
}

pub fn peek(self: *Stack, count: usize) ![]const u8 {
    if (self.sp < count) return StackError.StackUnderflow;
    return self.data.items[self.sp - count .. self.sp];
}

pub fn peekValue(self: *Stack, data_size: DataSize) !Value {
    const bytes = data_size.toBytes();
    if (self.sp < bytes) return StackError.StackUnderflow;
    const slice = self.data.items[self.sp - bytes .. self.sp];
    var value: Value = undefined;
    switch (data_size) {
        .b8 => value = Value{ .b8 = std.mem.bytesAsValue(u8, slice).* },
        .b16 => value = Value{ .b16 = std.mem.bytesAsValue(u16, slice).* },
        .b32 => value = Value{ .b32 = std.mem.bytesAsValue(u32, slice).* },
        else => unreachable,
    }
    return value;
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
    var second: [4]u8 = undefined;
    @memcpy(second[0..count], self.data.items[self.sp - (count * 2) .. self.sp - count]);
    @memcpy(self.data.items[self.sp - (count * 2) .. self.sp - count], self.data.items[self.sp - count .. self.sp]);
    @memcpy(self.data.items[self.sp - count .. self.sp], second[0..count]);
}

pub fn over(self: *Stack, data_size: DataSize) !void {
    const count = data_size.toBytes();
    if (self.sp < count * 2) return StackError.StackUnderflow;
    var second: [4]u8 = undefined;
    @memcpy(second[0..count], self.data.items[self.sp - (count * 2) .. self.sp - count]);
    try self.data.appendSlice(second[0..count]);
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
