//implementation of the type VM

registry: Registry,
data_stack: Stack,
return_stack: Stack,
memory: Memory,
allocator: Allocator,
pc: u32,

pub fn init(allocator: Allocator) !VM {
    return VM{
        .data_stack = try Stack.init(allocator),
        .return_stack = try Stack.init(allocator),
    };
}

pub fn deinit(self: *VM) void {
    self.data_stack.deinit();
    self.return_stack.deinit();
}

pub fn execute(self: *VM) !u8 {
    var mem_reader = try self.memory.reader();
    const byte = try mem_reader.readByte();
    const instruction = Instruction.fromByte(byte);
    const stack = if (instruction.stack == 0) &self.data_stack else &self.return_stack;
    switch (instruction.opcode) {
        .piush => {
            self.pc += 1;
            const buffer: [4]u8 = undefined;
            const data = try mem_reader.read(self.pc, buffer);
            const type_index: TypeIndex = std.mem.bytesToValue(TypeIndex, data);
            const type_ = try self.registry.get_type_by_index(type_index);
            try stack.push(type_);
        },
        .pop => {
            _ = try stack.pop();
        },
        .dup => {
            try stack.dup();
        },
        .swap => {
            try stack.swap();
        },
        .over => {
            try stack.over();
        },
        .push_reg => {
            // push reg takes an immediate value
            // the immediate value is the index of the register
            // and then it will push the value of the register onto the stack
            const reg_index = try stack.pop();
            if (!reg_index.isEqual(.{ .integer = .{
                .size = 8,
                .sign = .unsigned,
                .alignment = 1,
            } })) {}
            const type_index: TypeIndex = @intCast(data);
            const type_ = try self.registry.get_type_by_index(type_index);
            try stack.push(type_);
        },
    }
    self.pc += 1;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Registry = @import("registry.zig");
const types = @import("types.zig");
const Type = types.Type;
const TypeList = types.TypeList;
const TypeIndex = types.TypeIndex;
const Stack = @import("stack.zig");
const psudo_opcodes = @import("psudo_opcodes.zig");
const Instruction = psudo_opcodes.Instruction;
const core = @import("core");
const Memory = core.Memory;
const VM = @This();
