//stack for the type vm

pub const Error = error{
    StackOverflow,
    StackUnderflow,
};

data: TypeList,
sp: u32, // stack pointer

pub fn init(allocator: Allocator) !Stack {
    return Stack{
        .data = try TypeList.init(allocator),
    };
}

pub fn deinit(self: *Stack) void {
    self.data.deinit();
}

pub fn push(self: *Stack, type_: Type) !void {
    if (self.sp >= self.data.items.len) {
        try self.data.append(type_);
    } else {
        self.data.items[self.sp] = type_;
    }
    self.sp += 1;
}

pub fn pop(self: *Stack) !Type {
    if (self.sp == 0) {
        return Error.StackUnderflow;
    }
    self.sp -= 1;
    return self.data.items[self.sp];
}

pub fn peek(self: *Stack) !Type {
    if (self.sp == 0) {
        return Error.StackUnderflow;
    }
    return self.data.items[self.sp - 1];
}

pub fn dup(self: *Stack) !void {
    if (self.sp == 0) {
        return Error.StackUnderflow;
    }
    if (self.sp >= self.data.items.len) {
        try self.data.append(self.data.items[self.sp - 1]);
    } else {
        self.data.items[self.sp] = self.data.items[self.sp - 1];
    }
    self.sp += 1;
}

pub fn swap(self: *Stack) !void {
    if (self.sp < 2) {
        return Error.StackUnderflow;
    }
    const a = self.data.items[self.sp - 1];
    const b = self.data.items[self.sp - 2];
    self.data.items[self.sp - 1] = b;
    self.data.items[self.sp - 2] = a;
}

pub fn over(self: *Stack) !void {
    // like dup but for the second last element
    if (self.sp < 2) {
        return Error.StackUnderflow;
    }
    if (self.sp >= self.data.items.len) {
        try self.data.append(self.data.items[self.sp - 2]);
    } else {
        self.data.items[self.sp] = self.data.items[self.sp - 2];
    }
    self.sp += 1;
}

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const types = @import("types.zig");
const Type = types.Type;
const TypeIndex = types.TypeIndex;
const TypeList = types.TypeList;

const Stack = @This();
