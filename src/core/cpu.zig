const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const opcode = @import("opcode.zig");
const Instruction = opcode.Instruction;
const Memory = @import("memory.zig");

const Stack = @import("stack.zig");
const StackOptions = Stack.StackOptions;
const DataSize = Stack.DataSize;
const Value = Stack.Value;

const CPU = @This();

const CPUError = error{
    IllegalInstruction,
};

pub const VMOptions = struct {
    working_stack: StackOptions = .{ .max_size = 1024 }, // Default stack size
    return_stack: StackOptions = .{ .max_size = 1024 }, // Default stack size
    memory: Memory.MemoryOptions = .{ .size = 65536 }, // Default memory size
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

pub const Register = enum {
    pc,
    status,
    // bit layout:
    // 0: 0x01 - Interrupt enable 0x00 - Interrupt disable
    intm, // Interrupt mask register
    wsp,
    wbp,
    rsp,
    rbp,
    SIZE,
};

const RegisterError = error{
    InvalidRegister,
};

allocator: Allocator,
data_stack: Stack,
return_stack: Stack, // Return stack for subroutine calls
memory: Memory, // Memory for the CPU

registers: struct {
    const Self = @This();

    pc: u16 = 0, // Program counter
    status: u8 = 0, // Status register
    intm: u16 = 0, // Interrupt mask register
    // Additional registers can be added here

    pub fn getRegister(self: Self, renum: Register, in_buffer: []u8) !usize {
        // Get a register value by index
        const value = switch (renum) {
            .pc => self.pc,
            .status => self.status,
            .intm => self.intm,
            else => return RegisterError.InvalidRegister,
        };
        const bytes = &std.mem.toBytes(value);
        @memcpy(in_buffer, bytes);
        return bytes.len;
    }

    pub fn setRegister(self: *Self, renum: Register, bytes: []const u8) !void {
        // Set a register value by index
        switch (renum) {
            .pc => {
                const value = std.mem.bytesAsValue(u16, bytes);
                self.pc = value.*;
            },
            .status => {
                const value = std.mem.bytesAsValue(u8, bytes);
                self.status = value.*;
            },
            .intm => {
                const value = std.mem.bytesAsValue(u16, bytes);
                self.intm = value.*;
            },
            else => return RegisterError.InvalidRegister,
        }
    }
} = .{},

pub fn init(options: VMOptions, allocator: Allocator) !CPU {
    const working_stack = try Stack.init(options.working_stack, allocator);
    const return_stack = try Stack.init(options.return_stack, allocator);
    const memory = try Memory.init(options.memory, allocator);
    return CPU{
        .allocator = allocator,
        .data_stack = working_stack,
        .return_stack = return_stack,
        .memory = memory,
    };
}

pub fn deinit(self: *CPU) void {
    self.data_stack.deinit();
    self.return_stack.deinit();
    self.memory.deinit();
}

pub fn execute(self: *CPU) !u8 {
    var mem_reader = try self.memory.reader();
    var mem_writer = try self.memory.writer();

    const instruction = try mem_reader.readByte(self.registers.pc);
    const inst: Instruction = Instruction.fromByte(instruction);
    const data_size = switch (inst.width) {
        0 => DataSize.b8, // 8-bit data size
        1 => DataSize.b16, // 16-bit data size
    };
    const selected_stack = switch (inst.stack) {
        0 => &self.data_stack,
        1 => &self.return_stack,
    };

    switch (inst.baseOpcode) {
        .special => switch (@as(opcode.StandardOpcode.Special, @enumFromInt((@as(u2, inst.width) << 1) | inst.stack))) {
            .illegal => return CPUError.IllegalInstruction,
            .noop => {},
            .ret => {
                // Handle return from subroutine
                const bytes = try self.return_stack.pop(2);
                const addr = std.mem.bytesToValue(u16, bytes);
                self.registers.pc = addr; // Set program counter to return address

            },
            .rti => {}, // Handle return from interrupt
        },
        .push => {
            self.registers.pc += 1;
            switch (inst.width) {
                0 => {
                    const imm = try mem_reader.readByte(self.registers.pc);
                    const value = Value{
                        .b8 = imm,
                    };
                    try selected_stack.pushValue(value);
                },
                1 => {
                    var buffer: [2]u8 = undefined;
                    const bytes = try mem_reader.read(self.registers.pc, &buffer);
                    self.registers.pc += 1; // Increment PC for 16-bit value
                    const imm = std.mem.bytesToValue(u16, bytes);
                    const value = Value{
                        .b16 = imm,
                    };
                    try selected_stack.pushValue(value);
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
            const reg_index = try mem_reader.readByte(self.registers.pc);
            if (reg_index >= @intFromEnum(Register.SIZE)) return RegisterError.InvalidRegister;
            var buffer: [2]u8 = undefined;
            const count = try self.registers.getRegister(@enumFromInt(reg_index), &buffer);
            try selected_stack.push(buffer[0..count]);
        },

        .pop_reg => {
            self.registers.pc += 1;
            const reg_index = try mem_reader.readByte(self.registers.pc);
            if (reg_index >= @intFromEnum(Register.SIZE)) return RegisterError.InvalidRegister;
            const bytes = try selected_stack.pop(data_size.toBytes());
            try self.registers.setRegister(@enumFromInt(reg_index), bytes);
        },

        .load => {
            const count = switch (inst.width) {
                0 => try selected_stack.popValue(.b8),
                1 => try selected_stack.popValue(.b16),
            };
            const address = try selected_stack.popValue(.b16); // Out of bounds TODO
            const buffer = try self.allocator.alloc(u8, count.asU32());
            defer self.allocator.free(buffer);
            const bytes = try mem_reader.read(address.b16, buffer);
            try selected_stack.push(bytes);
        },

        .store => {
            const count = switch (inst.width) {
                0 => try selected_stack.popValue(.b8),
                1 => try selected_stack.popValue(.b16),
            };

            const address = try selected_stack.popValue(.b16);
            const values = try selected_stack.pop(count.asU32());

            if (address.asU32() + count.asU32() >= self.memory.data.len) return CPUError.IllegalInstruction; // Out of bounds
            _ = try mem_writer.write(address.b16, values);
        },

        .flip => {
            switch (inst.stack) {
                0 => {
                    // place the top value of the working stack onto the return stack
                    switch (inst.width) {
                        0 => {
                            const top_value = try self.data_stack.popValue(.b8);
                            try self.return_stack.pushValue(top_value);
                        },
                        1 => {
                            const top_value = try self.data_stack.popValue(.b16);
                            try self.return_stack.pushValue(top_value);
                        },
                    }
                },
                1 => {
                    // place the top value of the return stack onto the working stack
                    switch (inst.width) {
                        0 => {
                            const top_value = try self.return_stack.popValue(.b8);
                            try self.data_stack.pushValue(top_value);
                        },
                        1 => {
                            const top_value = try self.return_stack.popValue(.b16);
                            try self.data_stack.pushValue(top_value);
                        },
                    }
                },
            }
        },

        .add => {
            const a = switch (inst.width) {
                0 => try selected_stack.popValue(.b8),
                1 => try selected_stack.popValue(.b16),
            };
            const b = try selected_stack.popValue(a.tag());
            try selected_stack.pushValue(a.add(b));
        },

        .sub => {
            const a = switch (inst.width) {
                0 => try selected_stack.popValue(.b8),
                1 => try selected_stack.popValue(.b16),
            };
            const b = try selected_stack.popValue(a.tag());
            try selected_stack.pushValue(a.sub(b));
        },

        .mul => {
            const a = switch (inst.width) {
                0 => try selected_stack.popValue(.b8),
                1 => try selected_stack.popValue(.b16),
            };
            const b = try selected_stack.popValue(a.tag());
            try selected_stack.pushValue(a.mul(b));
        },

        .div => {
            const a = switch (inst.width) {
                0 => try selected_stack.popValue(.b8),
                1 => try selected_stack.popValue(.b16),
            };
            const b = try selected_stack.popValue(a.tag());
            // Check for division by zero
            if (b.asU32() == 0) return CPUError.IllegalInstruction; // Handle division by zero
            try selected_stack.pushValue(a.div(b));
        },

        .fx_add => {
            const a = switch (inst.width) {
                0 => try selected_stack.popValue(.b16),
                1 => try selected_stack.popValue(.b32),
            };
            const b = try selected_stack.popValue(a.tag());
            try selected_stack.pushValue(a.fx_add(b));
        },

        .fx_sub => {
            const a = switch (inst.width) {
                0 => try selected_stack.popValue(.b16),
                1 => try selected_stack.popValue(.b32),
            };
            const b = try selected_stack.popValue(a.tag());
            try selected_stack.pushValue(a.fx_sub(b));
        },

        .fx_mul => {
            const a = switch (inst.width) {
                0 => try selected_stack.popValue(.b16),
                1 => try selected_stack.popValue(.b32),
            };
            const b = try selected_stack.popValue(a.tag());
            try selected_stack.pushValue(a.fx_mul(b));
        },

        .fx_div => {
            const a = switch (inst.width) {
                0 => try selected_stack.popValue(.b16),
                1 => try selected_stack.popValue(.b32),
            };
            const b = try selected_stack.popValue(a.tag());
            // Check for division by zero
            if (b.asU32() == 0) return CPUError.IllegalInstruction; // Handle division by zero
            try selected_stack.pushValue(a.fx_div(b));
        },

        .@"and" => {
            const a = switch (inst.width) {
                0 => try selected_stack.popValue(.b8),
                1 => try selected_stack.popValue(.b16),
            };
            const b = try selected_stack.popValue(a.tag());
            try selected_stack.pushValue(a.@"and"(b));
        },

        .@"or" => {
            const a = switch (inst.width) {
                0 => try selected_stack.popValue(.b8),
                1 => try selected_stack.popValue(.b16),
            };
            const b = try selected_stack.popValue(a.tag());
            try selected_stack.pushValue(a.@"or"(b));
        },

        .xor => {
            const a = switch (inst.width) {
                0 => try selected_stack.popValue(.b8),
                1 => try selected_stack.popValue(.b16),
            };
            const b = try selected_stack.popValue(a.tag());
            try selected_stack.pushValue(a.xor(b));
        },

        .not => {
            const a = switch (inst.width) {
                0 => try selected_stack.popValue(.b8),
                1 => try selected_stack.popValue(.b16),
            };
            try selected_stack.pushValue(a.not());
        },

        .shl => {
            const a = switch (inst.width) {
                0 => try selected_stack.popValue(.b8),
                1 => try selected_stack.popValue(.b16),
            };
            const b = try selected_stack.popValue(a.tag());
            try selected_stack.pushValue(a.shl(b));
        },

        .shr => {
            const a = switch (inst.width) {
                0 => try selected_stack.popValue(.b8),
                1 => try selected_stack.popValue(.b16),
            };
            const b = try selected_stack.popValue(a.tag());
            try selected_stack.pushValue(a.shr(b));
        },

        .cmp => {
            self.registers.pc += 1; // Increment PC to get the immediate value
            var buffer: [1]u8 = undefined;
            _ = try mem_reader.read(self.registers.pc, &buffer);
            const cmp_type = CMPType.fromByte(buffer[0]);
            const a = switch (inst.width) {
                0 => try selected_stack.popValue(.b8),
                1 => try selected_stack.popValue(.b16),
            };
            const b = try selected_stack.popValue(a.tag());
            const result = @intFromBool(switch (cmp_type) {
                .Equal => a.equal(b),
                .NotEqual => !a.equal(b),
                .LessThan => a.lessThan(b),
                .GreaterThan => !a.lessThan(b),
                .LessThanOrEqual => a.lessThanEqual(b),
                .GreaterThanOrEqual => !a.lessThan(b) or a.equal(b),
            });
            // Push the result of the comparison back onto the stack
            try selected_stack.pushValue(Value{ .b8 = result });
        },

        .jmp => {
            self.registers.pc += 1; // Increment PC to get the immediate address
            // if datasize is 8 bits read 1 byte and treat it as a relative jump
            switch (inst.width) {
                0 => {
                    var buffer: [1]u8 = undefined;
                    _ = try mem_reader.read(self.registers.pc, &buffer);
                    const new_pc = @addWithOverflow(buffer[0], self.registers.pc);
                    self.registers.pc = new_pc[0]; // Relative jump
                },
                1 => {
                    var buffer: [2]u8 = undefined;
                    _ = try mem_reader.read(self.registers.pc, &buffer);
                    self.registers.pc = std.mem.bytesAsValue(u16, &buffer).*; // Absolute jump
                },
            }
            return 0;
        },

        .jnz => {
            const condition = try selected_stack.popValue(.b8);
            if (condition.b8 != 0) {
                self.registers.pc += 1; // Increment PC to get the immediate address
                switch (inst.width) {
                    0 => {
                        var buffer: [1]u8 = undefined;
                        _ = try self.memory.read(self.registers.pc, &buffer);
                        const new_pc = @addWithOverflow(buffer[0], self.registers.pc);
                        self.registers.pc = new_pc[0]; // Relative jump
                    },
                    1 => {
                        var buffer: [2]u8 = undefined;
                        _ = try self.memory.read(self.registers.pc, &buffer);
                        self.registers.pc = std.mem.bytesAsValue(u16, &buffer).*; // Absolute jump
                    },
                }
            }
            return 0;
        },

        .call => {
            const is_direct = inst.width == 0; // Check if it's a direct call
            const is_foreign = inst.stack == 1; // Check if it's a foreign function call
            if (is_direct) {
                self.registers.pc += 1; // Increment PC to get the immediate address
                if (!is_foreign) {
                    // Direct call, read the next 2 bytes as the address
                    var buffer: [2]u8 = undefined;
                    _ = try mem_reader.read(self.registers.pc, &buffer);
                    const addr = std.mem.bytesAsValue(u16, &buffer).*;
                    try self.return_stack.pushValue(Value{ .b16 = self.registers.pc + 2 }); // Push return address onto return stack
                    self.registers.pc = addr; // Jump to subroutine
                } else {
                    // todo: handle foreign function call
                    // For now, we just print the address as an example
                    var buffer: [2]u8 = undefined;
                    _ = try mem_reader.read(self.registers.pc, &buffer);
                    const addr = std.mem.bytesAsValue(u16, &buffer);
                    std.debug.print("Foreign function call to address: {}\n", .{addr});
                }
            } else {
                if (!is_foreign) {
                    // Indirect call, get the address from the top of the working stack
                    const addr = try selected_stack.popValue(.b16);
                    try self.return_stack.pushValue(Value{ .b16 = self.registers.pc + 2 }); // Push return address onto return stack
                    self.registers.pc = addr.b16; // Jump to subroutine
                } else {
                    //todo: handle foreign function call
                    // For now, we just print the address as an example
                    const addr = try selected_stack.popValue(.b16);
                    std.debug.print("Foreign function call to address: {}\n", .{addr});
                }
            }
            return 0;
        },

        .trap => {
            // Perform a system call to the host via a trap code from the top of the selected stack
            const trap_code = switch (inst.width) {
                0 => try selected_stack.popValue(.b8),
                1 => try selected_stack.popValue(.b16),
            };
            // Here you would handle the trap code, e.g., by calling a host function
            // For now, we just print it as an example
            std.debug.print("Trap code: {}\n", .{trap_code});
        },

        .halt => {
            const exit_code = try selected_stack.popValue(.b8);
            std.debug.print("CPU halted with exit code: {}\n", .{exit_code});
            return exit_code.b8; // Exit the CPU
        },

        .int => {
            // Signal a software interrupt, the interrupt id will be in the top value of the selected stack
            const interrupt_id = try selected_stack.popValue(.b8);
            // Here you would handle the interrupt, e.g., by calling an interrupt handler
            std.debug.print("Software interrupt with ID: {}\n", .{interrupt_id});
        },

        // Add more cases for other opcodes...
        //else => return CPUError.IllegalInstruction,
    }
    self.registers.pc += 1; // Increment program counter after executing instruction
    return 0; // Return 0 to indicate successful execution
}

pub fn hardwareInterrupt(self: *CPU, interrupt_id: u8) !void {
    // old return stack pointer is set to bp
    if ((self.registers.status & 0x01) == 0) {
        return; // Maskable Interrupts are disabled
    }
    if ((self.registers.intm & (1 << interrupt_id)) == 0) {
        return; // Interrupt is not enabled
    }

    try self.return_stack.pushValue(Value{ .b16 = self.registers.pc });
    try self.return_stack.pushValue(Value{ .b8 = self.registers.status });
    try self.return_stack.pushValue(Value{ .b16 = self.registers.intm });
    //TODO : interrupt vector table
    //TODO : set the program counter to the interrupt vector address
    self.registers.pc = 0; // Set program counter to interrupt vector address
    self.registers.status &= 0xFE; // Disable interrupts

}
