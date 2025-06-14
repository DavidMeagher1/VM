// we are going to make a memory structure for the VM
const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Memory = @This();

pub const Error = error{
    OutOfMemory,
    InvalidAddress,
};

pub const MemoryFrame = struct {
    const Error = error{
        InvalidAddress,
        OutOfMemory,
    };
    address: usize,
    data: []u8,

    pub fn write(self: *MemoryFrame, address: usize, data: []const u8) !usize {
        if (address + data.len > self.data.len) {
            return MemoryFrame.Error.InvalidAddress;
        }
        @memcpy(self.data[address .. address + data.len], data);
        return data.len;
    }

    pub fn read(self: *MemoryFrame, address: usize, in_buffer: []u8) ![]const u8 {
        if (address + in_buffer.len > self.data.len) {
            return MemoryFrame.Error.InvalidAddress;
        }
        @memcpy(in_buffer, self.data[address .. address + in_buffer.len]);
        return in_buffer[0..in_buffer.len];
    }
};

allocator: Allocator,
data: []u8,

pub const MemoryOptions = struct {
    size: usize,
};

pub fn init(options: MemoryOptions, allocator: Allocator) !Memory {
    const result = Memory{
        .allocator = allocator,
        .data = try allocator.alloc(u8, options.size),
    };
    @memset(result.data, 0);
    return result;
}

pub fn deinit(self: *Memory) void {
    self.allocator.free(self.data);
    self.data = &[_]u8{};
}

pub fn getFrame(self: *Memory, address: usize, size: usize) !MemoryFrame {
    if (address + size > self.data.len) {
        return Error.InvalidAddress;
    }
    return MemoryFrame{
        .address = address,
        .data = self.data[address .. address + size],
    };
}

pub fn write(self: *Memory, address: usize, data: []const u8) !usize {
    if (address + data.len > self.data.len) {
        return Error.OutOfMemory;
    }
    @memcpy(self.data[address .. address + data.len], data);
    return data.len;
}

pub fn read(self: *Memory, address: usize, in_buffer: []u8) ![]const u8 {
    if (address + in_buffer.len > self.data.len) {
        return Error.InvalidAddress;
    }
    @memcpy(in_buffer, self.data[address .. address + in_buffer.len]);
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
