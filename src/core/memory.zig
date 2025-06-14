// we are going to make a memory structure for the VM
const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Memory = @This();

pub const Error = error{
    OutOfMemory,
    InvalidAddress,
};

allocator: Allocator,
data: ArrayList(u8),
max_size: usize,

pub const MemoryOptions = struct {
    max_size: usize,
};

pub fn init(options: MemoryOptions, allocator: Allocator) !Memory {
    var memory = ArrayList(u8).init(allocator);
    try memory.ensureTotalCapacity(options.max_size);
    return Memory{
        .allocator = allocator,
        .data = memory,
        .max_size = options.max_size,
    };
}

pub fn deinit(self: *Memory) void {
    self.data.deinit();
}

pub fn write(self: *Memory, address: usize, data: []const u8) !usize {
    if (address + data.len > self.data.items.len and address + data.len <= self.max_size) {
        try self.data.ensureTotalCapacity(address + data.len);
    } else if (address + data.len > self.max_size) {
        return Error.OutOfMemory;
    }
    if (address + data.len > self.data.items.len) {
        try self.data.resize(address + data.len);
    }
    @memcpy(self.data.items[address .. address + data.len], data);
    return data.len;
}

pub fn read(self: *Memory, address: usize, in_buffer: []u8) ![]const u8 {
    if (address + in_buffer.len > self.data.items.len) {
        return Error.InvalidAddress;
    }
    @memcpy(in_buffer, self.data.items[address .. address + in_buffer.len]);
    return in_buffer[0..in_buffer.len];
}

pub fn writer(self: *Memory) !Writer {
    return Writer.init(self);
}

pub fn reader(self: *Memory) !Reader {
    return Reader.init(self);
}

pub const Writer = struct {
    context: *Memory,
    write_fn: *const fn (context: *Memory, address: usize, data: []const u8) anyerror!usize,

    pub fn init(context: *Memory) !Writer {
        return Writer{
            .context = context,
            .write_fn = Memory.write,
        };
    }

    pub fn write(self: *Writer, address: usize, data: []const u8) !usize {
        return self.write_fn(self.context, address, data);
    }

    pub fn writeByte(self: *Writer, address: usize, byte: u8) !usize {
        return self.write_fn(self.context, address, &byte);
    }
};

pub const Reader = struct {
    context: *Memory,
    read_fn: *const fn (context: *Memory, address: usize, in_buffer: []u8) anyerror![]const u8,

    pub fn init(context: *Memory) !Reader {
        return Reader{
            .context = context,
            .read_fn = Memory.read,
        };
    }

    pub fn read(self: *Reader, address: usize, in_buffer: []u8) ![]const u8 {
        return self.read_fn(self.context, address, in_buffer);
    }

    pub fn readByte(self: *Reader, address: usize) !u8 {
        var buffer: [1]u8 = undefined;
        const out_buffer = try self.read_fn(self.context, address, &buffer);
        const result = out_buffer[0];
        return result;
    }
};
