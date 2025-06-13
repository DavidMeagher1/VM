const std = @import("std");
const Allocator = std.mem.Allocator;

const opcode = @import("opcode.zig");
const Instruction = opcode.Instruction;
const hardware = @import("hardware.zig");
const Memory = hardware.Memory;

const math = @import("math.zig");

const Stack = @import("stack.zig");
const StackOptions = Stack.StackOptions;
const DataSize = Stack.DataSize;

const VM = @This();

const VMError = error{
    IllegalInstruction,
};

pub const VMOptions = struct {
    working_stack: StackOptions = .{ .max_size = 1024 }, // Default stack size
    return_stack: StackOptions = .{ .max_size = 1024 }, // Default stack size
    memory: hardware.MemoryOptions = .{ .max_size = 65536 }, // Default memory size
};

pub const CMPType = enum(u8) {
    Equal,
    NotEqual,
    LessThan,
    GreaterThan,
    LessThanOrEqual,
    GreaterThanOrEqual,

    pub fn fromByte(value: u8) CMPType {
        return switch (value) {
            0 => .Equal,
            1 => .NotEqual,
            2 => .LessThan,
            3 => .GreaterThan,
            4 => .LessThanOrEqual,
            5 => .GreaterThanOrEqual,
            else => unreachable, // Invalid value
        };
    }
};

allocator: Allocator,
data_stack: Stack,
return_stack: Stack, // Return stack for subroutine calls
memory: Memory, // Memory for the VM
registers: struct {
    const Self = @This();

    pc: u16 = 0, // Program counter
    status: u8 = 0, // Status register
    // Additional registers can be added here

    pub fn getRegister(self: *Self, index: u8) u16 {
        // Get a register value by index
        switch (index) {
            0 => return self.registers.pc,
            1 => return self.registers.status,
            else => return 0, // Handle invalid register access
        }
    }

    pub fn setRegister(self: *Self, index: u8, value: u16) void {
        // Set a register value by index
        switch (index) {
            0 => self.registers.pc = value,
            1 => self.registers.status = @intCast(value),
            else => {}, // Handle invalid register access
        }
    }
} = .{},

pub fn init(options: VMOptions, allocator: Allocator) !VM {
    const working_stack = try Stack.init(options.working_stack, allocator);
    const return_stack = try Stack.init(options.return_stack, allocator);
    const memory = try Memory.init(options.memory, allocator);
    return VM{
        .allocator = allocator,
        .data_stack = working_stack,
        .return_stack = return_stack,
        .memory = memory,
    };
}

pub fn deinit(self: *VM) void {
    self.data_stack.deinit();
    self.return_stack.deinit();
    self.memory.deinit();
}

pub fn execute(self: *VM, instruction: u8) !u8 {
    const inst: Instruction = Instruction.fromByte(instruction);
    const data_size = switch (inst.width) {
        0 => DataSize.b8, // 8-bit data size
        1 => DataSize.b16, // 16-bit data size
    };
    const fx_data_size = switch (inst.width) {
        0 => DataSize.b16, // 16-bit fixed point data size
        1 => DataSize.b32, // 32-bit fixed point data size
    };
    const selected_stack = switch (inst.stack) {
        0 => &self.data_stack,
        1 => &self.return_stack,
    };

    switch (inst.opcode) {
        .special => switch (inst.special) {
            .illegal => return VMError.IllegalInstruction,
            .noop => {},
            .ret => {
                // Handle return from subroutine
                const bytes: u16 = try self.return_stack.pop(2);
                const addr = std.mem.bytesAsValue(u16, bytes);
                self.registers.pc = addr; // Set program counter to return address

            },
            .rti => {}, // Handle return from interrupt
        },
        .push => {
            self.registers.pc += 1;
            var data_buffer: [2]u8 = undefined;
            switch (inst.width) {
                0 => {
                    self.memory.read(self.registers.pc, &data_buffer[0..1]);
                    const value = data_buffer[0];
                    try selected_stack.pushValue(@TypeOf(value), value);
                },
                1 => {
                    self.memory.read(self.registers.pc, &data_buffer[0..2]);
                    self.registers.pc += 1; // Increment PC for 16-bit value
                    const value = std.mem.bytesAsValue(u16, data_buffer[0..2]);
                    try selected_stack.pushValue(@TypeOf(value), value);
                },
            }
        },
        .pop => {
            _ = try selected_stack.pop(data_size.toBytes());
        },

        .dup => {
            try selected_stack.dup(data_size);
        },

        .swap => {
            try selected_stack.swap(data_size);
        },

        .over => {
            try selected_stack.over(data_size);
        },

        .push_reg => {
            self.registers.pc += 1;
            const T = switch (data_size) {
                .b8 => u8,
                .b16 => u16,
            };
            var buffer: [1]u8 = undefined;
            self.memory.read(self.registers.pc, &buffer);
            const reg_index = buffer[0];
            const reg_value = self.registers.getRegister(reg_index);
            try selected_stack.pushValue(@TypeOf(T), reg_value);
        },

        .pop_reg => {
            self.registers.pc += 1;
            var buffer: [1]u8 = undefined;
            self.memory.read(self.registers.pc, &buffer);
            const reg_index = buffer[0];
            const value = try selected_stack.popValue(data_size);
            self.registers.setRegister(reg_index, @as(u16, value));
        },

        .load => {
            const count = try selected_stack.popValue(data_size);
            const address = try selected_stack.popValue(DataSize.b16);
            if (address + count > self.memory.max_size) return VMError.IllegalInstruction; // Out of bounds TODO
            const buffer = self.allocator.alloc(u8, count) catch unreachable;
            defer self.allocator.free(buffer);
            self.memory.read(address, buffer);
            const bytes = self.memory.items[address .. address + count];
            try selected_stack.push(bytes);
        },

        .store => {
            const count = try selected_stack.popValue(data_size);
            const address = try selected_stack.popValue(DataSize.b16);
            const values = try selected_stack.pop(count);
            if (address + count > self.memory.items.len) return VMError.IllegalInstruction; // Out of bounds TODO
            self.memory.write(address, values);
        },

        .flip => {
            switch (inst.stack) {
                0 => {
                    // place the top value of the working stack onto the return stack
                    const top_value = try self.data_stack.popValue(data_size);
                    try self.return_stack.pushValue(@TypeOf(top_value), top_value);
                },
                1 => {
                    // place the top value of the return stack onto the working stack
                    const top_value = try self.return_stack.popValue(data_size);
                    try self.data_stack.pushValue(@TypeOf(top_value), top_value);
                },
            }
        },

        .add => {
            const a = try selected_stack.popValue(data_size);
            const b = try selected_stack.popValue(data_size);
            try selected_stack.pushValue(@TypeOf(a), a + b);
        },

        .sub => {
            const a = try selected_stack.popValue(data_size);
            const b = try selected_stack.popValue(data_size);
            try selected_stack.pushValue(@TypeOf(a), a - b);
        },

        .mul => {
            const a = try selected_stack.popValue(data_size);
            const b = try selected_stack.popValue(data_size);
            try selected_stack.pushValue(@TypeOf(a), a * b);
        },

        .div => {
            const a = try selected_stack.popValue(data_size);
            const b = try selected_stack.popValue(data_size);
            if (b == 0) return VMError.IllegalInstruction; // Handle division by zero
            try selected_stack.pushValue(@TypeOf(a), a / b);
        },

        .fx_add => {
            const a = try selected_stack.popValue(fx_data_size);
            const b = try selected_stack.popValue(fx_data_size);
            try selected_stack.pushValue(@TypeOf(a), math.fx_add(@TypeOf(a), a, b));
        },

        .fx_sub => {
            const a = try selected_stack.popValue(fx_data_size);
            const b = try selected_stack.popValue(fx_data_size);
            try selected_stack.pushValue(@TypeOf(a), math.fx_sub(@TypeOf(a), a, b));
        },

        .fx_mul => {
            const a = try selected_stack.popValue(fx_data_size);
            const b = try selected_stack.popValue(fx_data_size);
            const result = try math.fx_mul(@TypeOf(a), a, b);
            try selected_stack.pushValue(@TypeOf(a), result);
        },

        .fx_div => {
            const a = try selected_stack.popValue(fx_data_size);
            const b = try selected_stack.popValue(fx_data_size);
            const result = try math.fx_div(@TypeOf(a), a, b);
            try selected_stack.pushValue(@TypeOf(a), result);
        },

        .@"and" => {
            const a = try selected_stack.popValue(data_size);
            const b = try selected_stack.popValue(data_size);
            try selected_stack.pushValue(@TypeOf(a), a & b);
        },

        .@"or" => {
            const a = try selected_stack.popValue(data_size);
            const b = try selected_stack.popValue(data_size);
            try selected_stack.pushValue(@TypeOf(a), a | b);
        },

        .xor => {
            const a = try selected_stack.popValue(data_size);
            const b = try selected_stack.popValue(data_size);
            try selected_stack.pushValue(@TypeOf(a), a ^ b);
        },

        .not => {
            const a = try selected_stack.popValue(data_size);
            try selected_stack.pushValue(@TypeOf(a), ~a);
        },

        .shl => {
            const a = try selected_stack.popValue(data_size);
            const b = try selected_stack.popValue(data_size);
            try selected_stack.pushValue(@TypeOf(a), a << b);
        },

        .shr => {
            const a = try selected_stack.popValue(data_size);
            const b = try selected_stack.popValue(data_size);
            try selected_stack.pushValue(@TypeOf(a), a >> b);
        },

        .cmp => {
            self.registers.pc += 1; // Increment PC to get the immediate value
            const buffer: [1]u8 = undefined;
            self.memory.read(self.registers.pc, &buffer);
            const cmp_type = CMPType.fromByte(buffer[0]);
            const a = try selected_stack.popValue(data_size);
            const b = try selected_stack.popValue(data_size);
            const result = @intFromBool(switch (cmp_type) {
                .Equal => a == b,
                .NotEqual => a != b,
                .LessThan => a < b,
                .GreaterThan => a > b,
                .LessThanOrEqual => a <= b,
                .GreaterThanOrEqual => a >= b,
            });
            // Push the result of the comparison back onto the stack
            try selected_stack.pushValue(u8, result);
        },

        .jmp => {
            self.registers.pc += 1; // Increment PC to get the immediate address
            // if datasize is 8 bits read 1 byte and treat it as a relative jump
            switch (data_size) {
                .b8 => {
                    const buffer: [1]u8 = undefined;
                    self.memory.read(self.registers.pc, &buffer);
                    const offset: i8 = @bitCast(buffer[0]);
                    self.registers.pc += offset; // Relative jump
                },
                .b16 => {
                    const buffer: [2]u8 = undefined;
                    self.memory.read(self.registers.pc, &buffer);
                    self.registers.pc = std.mem.bytesAsValue(u16, &buffer); // Absolute jump
                },
            }
            return 0;
        },

        .jnz => {
            const condition = try selected_stack.popValue(data_size);
            if (condition != 0) {
                self.registers.pc += 1; // Increment PC to get the immediate address
                switch (data_size) {
                    .b8 => {
                        const buffer: [1]u8 = undefined;
                        self.memory.read(self.registers.pc, &buffer);
                        const offset: i8 = @bitCast(buffer[0]);
                        self.registers.pc += offset; // Relative jump
                    },
                    .b16 => {
                        const buffer: [2]u8 = undefined;
                        self.memory.read(self.registers.pc, &buffer);
                        self.registers.pc = std.mem.bytesAsValue(u16, &buffer); // Absolute jump
                    },
                }
            }
            return 0;
        },

        .call => {
            const is_direct = inst.w == 0; // Check if it's a direct call
            const is_foreign = inst.s == 1; // Check if it's a foreign function call
            if (is_direct) {
                self.registers.pc += 1; // Increment PC to get the immediate address
                if (!is_foreign) {
                    // Direct call, read the next 2 bytes as the address
                    const buffer: [2]u8 = undefined;
                    self.memory.read(self.registers.pc, &buffer);
                    const addr = std.mem.bytesAsValue(u16, &buffer);
                    try self.return_stack.pushValue(u16, self.registers.pc + 2); // Push return address onto return stack
                    self.registers.pc = addr; // Jump to subroutine
                } else {
                    // todo: handle foreign function call
                    // For now, we just print the address as an example
                    const buffer: [2]u8 = undefined;
                    self.memory.read(self.registers.pc, &buffer);
                    const addr = std.mem.bytesAsValue(u16, &buffer);
                    std.debug.print("Foreign function call to address: {}\n", .{addr});
                }
            } else {
                if (!is_foreign) {
                    // Indirect call, get the address from the top of the working stack
                    const addr = try selected_stack.popValue(DataSize.b16);
                    try self.return_stack.pushValue(u16, self.registers.pc + 2); // Push return address onto return stack
                    self.registers.pc = @as(u16, addr); // Jump to subroutine
                } else {
                    //todo: handle foreign function call
                    // For now, we just print the address as an example
                    const addr = try selected_stack.popValue(DataSize.b16);
                    std.debug.print("Foreign function call to address: {}\n", .{addr});
                }
            }
            return 0;
        },

        .trap => {
            // Perform a system call to the host via a trap code from the top of the selected stack
            const trap_code = try selected_stack.popValue(data_size);
            // Here you would handle the trap code, e.g., by calling a host function
            // For now, we just print it as an example
            std.debug.print("Trap code: {}\n", .{trap_code});
        },

        .halt => {
            const exit_code = try selected_stack.popValue(DataSize.b8);
            std.debug.print("VM halted with exit code: {}\n", .{exit_code});
            return exit_code; // Exit the VM
        },

        .int => {
            // Signal a software interrupt, the interrupt id will be in the top value of the selected stack
            const interrupt_id = try selected_stack.popValue(DataSize.b8);
            // Here you would handle the interrupt, e.g., by calling an interrupt handler
            std.debug.print("Software interrupt with ID: {}\n", .{interrupt_id});
        },

        // Add more cases for other opcodes...
        else => return VMError.IllegalInstruction,
    }
    self.registers.pc += 1; // Increment program counter after executing instruction
    return 0; // Return 0 to indicate successful execution
}

pub fn run(self: *VM, bytecode: []const u8) !u8 {
    self.memory.ensureTotalCapacity(bytecode.len) catch unreachable;
    @memcpy(self.memory.items, bytecode);
    while (self.registers.pc < self.memory.items.len) {
        const instruction = self.memory.items[self.registers.pc];
        const result = try self.execute(instruction);
        if (result != 0) {
            return result; // Return if an error occurred or if the VM halted
        }
    }
    return 0; // Return 0 to indicate successful execution of the bytecode
}
