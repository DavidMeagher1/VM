// structures for memory management

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;

pub const MemoryOptions = struct {
    max_size: usize = 65536, // default maximum size of memory
};

pub const HardwareMappingError = error{
    InvalidHardwareId,
    InvalidMemoryRange,
    DuplicateHardware,
    DuplicateMemoryRange,
    HardwareNotFound,
    MemoryRangeConflict,
};

pub const Hardware = struct {
    context: *Memory,
    id: u32 = 0,

    pub const Writer = struct {
        const Self = @This();
        context: *Hardware,
        write_fn: fn (context: *Hardware, address: usize, data: []const u8) anyerror!usize,
        pub fn init(context: *Hardware, write_fn: fn (context: *Hardware, address: usize, data: []const u8) anyerror!usize) Self {
            return Self{
                .context = context,
                .write_fn = write_fn,
            };
        }

        pub fn write(self: *Self, address: usize, data: []const u8) !usize {
            return self.write_fn(self.context, address, data);
        }

        pub fn writeByte(self: *Self, address: usize, byte: u8) !void {
            var buffer: [1]u8 = .{byte};
            try self.write(address, buffer[0..1]);
        }
    };

    pub const Reader = struct {
        const Self = @This();
        context: *Hardware,
        read_fn: fn (context: *Hardware, address: usize, buffer: []u8) anyerror!usize,

        pub fn init(context: *Hardware, read_fn: fn (context: *Hardware, address: usize, buffer: []u8) anyerror!usize) Self {
            return Self{
                .context = context,
                .read_fn = read_fn,
            };
        }

        pub fn read(self: *Self, address: usize, buffer: []u8) !usize {
            return self.read_fn(self.context, address, buffer);
        }

        pub fn readByte(self: *Self, address: usize) !u8 {
            var buffer: [1]u8 = undefined;
            const bytes_read = try self.read(address, buffer[0..1]);
            if (bytes_read != 1) return HardwareMappingError.InvalidMemoryRange;
            return buffer[0];
        }
    };

    pub fn writer(self: *Hardware) Writer {
        return Writer.init(self, self.write);
    }

    pub fn reader(self: *Hardware) Reader {
        return Reader.init(self, self.read);
    }
};

pub const MemoryRange = struct {
    start: u32,
    end: u32,

    pub fn size(self: *MemoryRange) u32 {
        return self.end - self.start;
    }

    pub fn contains(self: *MemoryRange, address: u32) bool {
        return address >= self.start and address < self.end;
    }

    pub fn overlaps(self: *MemoryRange, other: MemoryRange) bool {
        return self.start < other.end and self.end > other.start;
    }

    pub fn _lessThan(comptime T: type, a: T, b: T) bool {
        return a.start < b.start or (a.start == b.start and a.end < b.end);
    }
};

pub const HardwareMap = AutoHashMap(
    u32, // hardware id
    Hardware, // hardware details
);

pub const HardwareRangeMap = AutoHashMap(
    u32, // hardware id
    MemoryRange, // memory range for the hardware
);

pub const Memory = struct {
    const Data = ArrayList(u8);

    data: Data,
    max_size: usize,
    allocator: std.mem.Allocator,
    mapped_hardware: struct {
        hardware: HardwareMap,
        ranges: HardwareRangeMap,
    },
    pub fn init(options: MemoryOptions, allocator: std.mem.Allocator) !Memory {
        var result = Memory{
            .data = Data.init(allocator),
            .max_size = options.max_size,
            .allocator = allocator,
            .mapped_hardware = .{
                .hardware = HardwareMap.init(allocator),
                .ranges = HardwareRangeMap.init(allocator),
            },
        };
        try result.data.ensureTotalCapacity(options.max_size);
        return result;
    }
    pub fn deinit(self: *Memory) void {
        self.data.deinit();
        self.mapped_hardware.hardware.deinit();
        self.mapped_hardware.ranges.deinit();
    }

    pub fn mapHardware(self: *Memory, hardware: *Hardware, range: MemoryRange) !u32 {
        // if hardware id is 0, give it a new id
        if (hardware.id == 0) {
            hardware.id = self.mapped_hardware.hardware.len() + 1;
        }
        if (range.start >= range.end or range.end > self.max_size) return HardwareMappingError.InvalidMemoryRange;

        if (self.mapped_hardware.hardware.get(hardware.id)) {
            return HardwareMappingError.DuplicateHardware;
        }

        if (self.mapped_hardware.ranges.get(hardware.id)) |existing_range| {
            if (existing_range.start < range.end and existing_range.end > range.start) {
                return HardwareMappingError.MemoryRangeConflict;
            }
        }

        try self.mapped_hardware.hardware.put(hardware.id, hardware.*);
        try self.mapped_hardware.ranges.put(hardware.id, range);
        return hardware.id;
    }

    pub fn unmapHardware(self: *Memory, hardware_id: u32) !void {
        if (!self.mapped_hardware.hardware.remove(hardware_id)) {
            return HardwareMappingError.HardwareNotFound;
        }
        if (!self.mapped_hardware.ranges.remove(hardware_id)) {
            return HardwareMappingError.HardwareNotFound;
        }
    }

    pub fn getHardware(self: *Memory, hardware_id: u32) ?Hardware {
        return self.mapped_hardware.hardware.get(hardware_id);
    }

    pub fn getMemoryRange(self: *Memory, hardware_id: u32) ?MemoryRange {
        return self.mapped_hardware.ranges.get(hardware_id);
    }

    pub fn getOverlappingHardware(self: *Memory, range: MemoryRange) ![]Hardware {
        var result = ArrayList(Hardware).init(self.allocator);
        var iter = self.mapped_hardware.ranges.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.overlaps(range)) {
                const hardware = self.mapped_hardware.hardware.get(entry.key_ptr.*) orelse continue;
                try result.append(hardware);
            }
        }
        return result.toOwnedSlice();
    }

    pub fn write(self: *Memory, address: usize, data: []const u8) !usize {
        const range = MemoryRange{
            .start = @intCast(address),
            .end = @intCast(address + data.len),
        };
        if (range.start >= range.end or range.end > self.max_size) return HardwareMappingError.InvalidMemoryRange;
        if (range.start >= self.data.items.len) {
            return HardwareMappingError.InvalidMemoryRange;
        }
        if (range.end > self.data.items.len) {
            self.data.ensureTotalCapacity(range.end) catch unreachable;
        }

        const hardware_in_range: []Hardware = try self.getOverlappingHardware(range);
        defer self.allocator.free(hardware_in_range);
        std.mem.sort(Hardware, hardware_in_range, MemoryRange, MemoryRange._lessThan);
        @memcpy(self.data.items[range.start..range.end], data);
        // write directly to memory if it does not overlap with any hardware
        if (hardware_in_range.len == 0) {
            @memcpy(self.data.items[range.start..range.end], data);
            return data.len;
        }
        for (hardware_in_range) |hardware| {
            //get the memory range for the hardware
            const memory_range = self.getMemoryRange(hardware.id);
            if (memory_range == null) return HardwareMappingError.HardwareNotFound;
            // if hardware range start is after the address we are writing to write memory up to start directly to memory
            if (memory_range.start > range.start) {
                const bytes_to_write = memory_range.start - range.start;
                @memcpy(self.data.items[range.start .. range.start + bytes_to_write], data[0..bytes_to_write]);
                range.start += bytes_to_write;
            }
            // then write data to hardware until the end of the hardware range
            var bytes_to_write = memory_range.end - range.start;
            if (bytes_to_write > data.len - range.start) {
                bytes_to_write = data.len - range.start;
            }
            try hardware.writer().write(range.start, data[range.start .. range.start + bytes_to_write]);
            range.start += bytes_to_write;
            if (range.start >= range.end) break;
        }
        // write any remaining data directly to memory
        if (range.start < range.end) {
            @memcpy(self.data.items[range.start..range.end], data[range.start..range.end]);
        }
        return data.len;
    }

    pub fn read(self: *Memory, address: usize, buffer: []u8) !usize {
        const range = MemoryRange{
            .start = @intCast(address),
            .end = @intCast(address + buffer.len),
        };
        if (range.start >= range.end or range.end > self.max_size) return HardwareMappingError.InvalidMemoryRange;
        if (range.start >= self.data.items.len) {
            return HardwareMappingError.InvalidMemoryRange;
        }
        if (range.end > self.data.items.len) {
            self.data.ensureTotalCapacity(range.end) catch unreachable;
        }

        const hardware_in_range: []Hardware = self.getOverlappingHardware(range);
        defer self.allocator.free(hardware_in_range);
        std.mem.sort(Hardware, hardware_in_range, Hardware, MemoryRange._lessThan);
        // read directly from memory if it does not overlap with any hardware
        if (hardware_in_range.len == 0) {
            @memcpy(buffer, self.data.items[range.start..range.end]);
            return buffer.len;
        }
        for (hardware_in_range) |hardware| {
            //get the memory range for the hardware
            const memory_range = self.getMemoryRange(hardware.id);
            if (memory_range == null) return HardwareMappingError.HardwareNotFound;
            // if hardware range start is after the address we are reading to, read memory up to start directly from memory
            if (memory_range.start > range.start) {
                const bytes_to_read = memory_range.start - range.start;
                @memcpy(buffer[0..bytes_to_read], self.data.items[range.start .. range.start + bytes_to_read]);
                range.start += bytes_to_read;
            }
            // then read data from hardware until the end of the hardware range
            var bytes_to_read = memory_range.end - range.start;
            if (bytes_to_read > buffer.len - range.start) {
                bytes_to_read = buffer.len - range.start;
            }
            try hardware.reader().read(range.start, buffer[range.start .. range.start + bytes_to_read]);
            range.start += bytes_to_read;
            if (range.start >= range.end) break;
        }
        // read any remaining data directly from memory
        if (range.start < range.end) {
            @memcpy(buffer[range.start..range.end], self.data.items[range.start..range.end]);
        }
        return buffer.len;
    }

    pub fn writeByte(self: *Memory, address: usize, byte: u8) !void {
        var buffer: [1]u8 = .{byte};
        try self.write(address, buffer[0..1]);
    }

    pub fn readByte(self: *Memory, address: usize) !u8 {
        var buffer: [1]u8 = undefined;
        const bytes_read = try self.read(address, buffer[0..1]);
        if (bytes_read != 1) return HardwareMappingError.InvalidMemoryRange;
        return buffer[0];
    }
};
