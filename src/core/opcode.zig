//working on a stack based virtual machine that uses a custom bytecode

// the bytecode layout will be as follows:
// the first bit will be the extension bit, which will indicate if the instruction is a single byte or a two byte instruction
// the next bit will determine the size of the data the instruction will operate on or another option depending on the instruction
// the next bit will determine which stack the instruction will operate on or another option depending on the instruction
// the next bits will be the opcode, which will determine the operation to be performed
// if the instruction is a two byte instruction, the next byte will also be part of the opcode
//eg: E W S O O O O O for a single byte instruction
// and E W S O O O O O - O O O O O O O O for a two byte instruction
// E = extension bit
// W = width bit (0 for 8 bit, 1 for 16 bit)
// S = stack bit (0 for the working stack, and 1 for the return stack)
// O = opcode bits (the rest of the bits will be used for the opcode)
// if all of the Opcode id bits are 0, then the instruction will use the W and S bits to determine a special opertion
// 0000 0000 will be an illegal instruction so that if we encounter uninitialized memory we can detect it and halt the program gracefully

// all memory addresses will be 16 bits, so the maximum addressable memory will be 65536 bytes

pub const StandardOpcode = enum(u5) {
    // special operations for when the opcode id bits are all 0
    // these operations will use the W and S bits to determine the operation

    pub const Special = enum(u2) {
        illegal, // illegal instruction, will cause the VM to halt
        noop, // no operation, does nothing
        ret, // return from a subroutine, will pop the return stack and jump to the address
        rti, // return from interrupt
    };
    special,
    // single byte instructions

    // stack operations

    push, // pushes a value onto the selected stack
    pop, // pops a value from the selected stack
    dup, // duplicates the top value of the selected stack
    swap, // swaps the top two values of the selected stack
    over, // duplicates the second value of the selected stack
    push_reg, // pushes a value from a register onto the selected stack
    pop_reg, // pops a value from the selected stack into a register
    load, // loads n values from memory into the selected stack
    store, // stores n values from the selected stack into memory
    flip, // depending on the S bit, takes what is on the top of the selected stack and flips it to the other stack

    // arithmetic operations

    add, // adds the top two values of the selected stack
    sub, // subtracts the top two values of the selected stack
    mul, // multiplies the top two values of the selected stack
    div, // divides the top two values of the selected stack

    // fixed point operations
    // these operations will use the W bit to determine if it is a 16 or 32 bit fixed point operation

    fx_add, // adds the top two values of the selected stack with a fixed point addition
    fx_sub, // subtracts the top two values of the selected stack with a fixed point subtraction
    fx_mul, // multiplies the top two values of the selected stack with a fixed point multiplication
    fx_div, // divides the top two values of the selected stack with a fixed point division

    // bitwise operations

    @"and", // bitwise and of the top two values of the selected stack
    @"or", // bitwise or of the top two values of the selected stack
    xor, // bitwise xor of the top two values of the selected stack
    not, // bitwise not of the top value of the selected stack
    shl, // shifts the top value of the selected stack left by one
    shr, // shifts the top value of the selected stack right by one
    // logical operations
    cmp, // compares the top two values of the selected stack takes an immediate value to determine the comparison type
    // control flow operations
    jmp, // jumps to a an immidiate label in the bytecode
    jnz, // jumps to an immidiate label in the bytecode if the top value of the selected stack is not zero
    call, // calls a subroutine at a label in the bytecode, pushes the return address onto the return stack
    // call uses the W bit to determine if it is a direct or indirect call
    // and the S bit to determine if it is a foriegn function call or a local subroutine call
    // direct call will expect the next 2 bytes to be the address of the subroutine
    // indirect call will get the address from the top of the working stack
    // this applies to both local and foreign function calls
    trap, // performs a system call to the host via a trap code from the top of the selected stack
    halt, // pops an exit code from the selected stack and exits the VM
    int, // signals a software interrupt, the interrupt id will be in the top value of the selected stack
};

// unused until we need more opcodes
pub const ExtendedOpcode = enum(u13) {
    reserved, // reserved for future use
    _,
};

pub const Instruction = packed struct {
    extension: u1, // E
    width: u1, // W
    stack: u1, // S
    baseOpcode: StandardOpcode,
    //extendedOpcode: ?ExtendedOpcode = null, // O O O O O - O O O O O O O O

    pub fn fromByte(byte: u8) Instruction {
        const extension = @as(u1, (byte & 0x80) >> 7); // E
        const width = @as(u1, (byte & 0x40) >> 6); // W
        const stack = @as(u1, (byte & 0x20) >> 5); // S
        const baseOpcode: StandardOpcode = @enumFromInt(@as(u5, byte & 0x1F)); // O O O O O

        return Instruction{
            .extension = extension,
            .width = width,
            .stack = stack,
            .baseOpcode = baseOpcode,
        };
    }

    pub fn toByte(self: Instruction) u8 {
        const byte = (@as(u8, self.extension) << 7) | (@as(u8, self.width) << 6) | (@as(u8, self.stack) << 5) | @intFromEnum(self.baseOpcode);
        return byte;
    }
};
