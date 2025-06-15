// these are pseudo opcodes
// used for the type vm to keep track of the types

pub const Opcode = enum {
    // stack operations
    illegal,
    noop,
    ret,
    rti,
    push,
    pop,
    dup,
    swap,
    over,
    push_reg,
    pop_reg,
    load,
    store,
    flip,
    // arithmetic operations

    add,
    sub,
    mul,
    div,
    // fixed point operations
    fx_add,
    fx_sub,
    fx_mul,
    fx_div,

    // bitwise operations
    @"and",
    @"or",
    xor,
    not,
    shl,
    shr,

    // logical operations
    cmp,

    // control flow
    jmp,
    jnz,
    call,
    trap,
    hault,
    int,
};

// these instructions do not care about data size, since that is in the type information
const Instruction = struct {
    stack: u1, // 0 = data stack, 1 = return stack
    opcode: Opcode,

    pub fn fromByte(byte: u8) Instruction {
        return Instruction{
            .stack = @truncate((byte & 0b1000_0000) >> 7),
            .opcode = @as(Opcode, @enumFromInt(byte & 0x7F)),
        };
    }

    pub fn toByte(self: Instruction) u8 {
        const stack: u8 = @as(u8, @intCast(self.stack)) << 7;
        const opcode: u8 = @intCast(self.opcode);
        return stack | opcode;
    }
};
