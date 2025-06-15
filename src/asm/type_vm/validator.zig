// functions to validate stack effects of instructions
pub const StackSelector = enum {
    data_stack,
    return_stack,
};
pub const StackSizeEffect = struct {
    data_stack_additions: KnownOrVar,
    data_stack_removals: KnownOrVar,
    return_stack_additions: KnownOrVar,
    return_stack_removals: KnownOrVar,
};

pub const KnownOrVar = union(enum) { variadic: void, known: u32, mixed: union(enum) {
    known: u32,
    variadic: void,
} };

pub fn known(value: u32) KnownOrVar {
    return KnownOrVar{ .known = value };
}

pub fn mixed(value: u32) KnownOrVar {
    return KnownOrVar{ .mixed = KnownOrVar{ .known = value } };
}

const variadic = KnownOrVar{ .variadic = .{} };

pub fn getStackSizeEffect(instruction: Instruction) StackSizeEffect {
    const selector = if (instruction.stack == 0) StackSelector.data_stack else StackSelector.return_stack;
    var data_stack_additions: u32 = undefined;
    var data_stack_removals: u32 = undefined;
    var return_stack_additions: u32 = undefined;
    var return_stack_removals: u32 = undefined;

    switch (selector) {
        .data_stack => {
            switch (instruction.opcode) {
                .push, .push_reg => data_stack_additions = known(1),
                .pop, .pop_reg => data_stack_removals = known(1),
                .dup => data_stack_additions = known(1),
                .swap, .over => data_stack_additions = known(0), // no net change
                .load => {
                    data_stack_removals = known(2); // a value for len and a pointer is removed
                    data_stack_additions = variadic; // the additions is dependant on the value
                },
                .store => data_stack_removals = mixed(1), // a value for len is removed and a pointer and N values,
                .flip => {
                    data_stack_removals = known(1);
                    return_stack_additions = known(1);
                },
                // arithmetic operations
                .add, .sub, .mul, .div => {
                    data_stack_removals = known(2);
                    data_stack_additions = known(1);
                },
                // fixed point operations
                .fx_add, .fx_sub, .fx_mul, .fx_div => {
                    data_stack_removals = known(2);
                    data_stack_additions = known(1);
                },
                // bitwise operations
                .@"and", .@"or", .xor, .not => {
                    data_stack_removals = known(2);
                    data_stack_additions = known(1);
                },
                // shift operations
                .shl, .shr => {
                    data_stack_removals = known(2);
                    data_stack_additions = known(1);
                },
                // logical operations
                .cmp => {
                    data_stack_removals = known(2);
                    data_stack_additions = known(1);
                },
                // control flow
                .jmp => data_stack_removals = known(0), // no net change
                .jnz => data_stack_removals = known(1), // one value is removed for the condition
                .call => {
                    // stack selector for call is actually used to tell if it is a FFI call or native
                    // we need to check the width bit to see if it is immediate or not
                    // if it is immediate we dont remove anything from the data stack
                    // if it is not immediate we remove the return address from the data stack

                    switch (instruction.width) {
                        0 => data_stack_removals = known(0), // immediate
                        1 => data_stack_removals = known(1), // not immediate
                    }
                    return_stack_additions = known(1); // we add the return address to the return stack
                },
                .trap => data_stack_removals = known(1),
                .hault => data_stack_removals = known(1), // no net change
                .int => data_stack_removals = known(1), // no net change
            }
        },
        .return_stack => {
            switch (instruction.opcode) {
                .push => return_stack_additions = known(1),
                .pop => return_stack_removals = known(1),
                .dup => return_stack_additions = known(1),
                .swap, .over => return_stack_additions = known(0), // no net change
                .load => {
                    return_stack_removals = known(2); // a value for len and a pointer is removed
                    return_stack_additions = variadic; // the additions is dependant on the value
                },
                .store => return_stack_removals = mixed(1), // a value for len is removed and a pointer and N values,
                .flip => {
                    return_stack_removals = known(1);
                    data_stack_additions = known(1);
                },
                // arithmetic operations
                .add, .sub, .mul, .div => {
                    return_stack_removals = known(2);
                    return_stack_additions = known(1);
                },
                // fixed point operations
                .fx_add, .fx_sub, .fx_mul, .fx_div => {
                    return_stack_removals = known(2);
                    return_stack_additions = known(1);
                },
                // bitwise operations
                .@"and", .@"or", .xor, .not => {
                    return_stack_removals = known(2);
                    return_stack_additions = known(1);
                },
                // shift operations
                .shl, .shr => {
                    return_stack_removals = known(2);
                    return_stack_additions = known(1);
                },
                // logical operations
                .cmp => {
                    return_stack_removals = known(2);
                    return_stack_additions = known(1);
                },
                // control flow
                .jmp => return_stack_removals = known(0), // no net change
                .jnz => return_stack_removals = known(1), // one value is removed for the condition
                .call => {
                    // stack selector for call is actually used to tell if it is a FFI call or native
                    // we need to check the width bit to see if it is immediate or not
                    // if it is immediate we dont remove anything from the return stack
                    // if it is not immediate we remove the return address from the return stack

                    switch (instruction.width) {
                        0 => return_stack_removals = known(0), // immediate
                        1 => return_stack_removals = known(1), // not immediate
                    }
                    return_stack_additions = known(1); // we add the return address to the data stack
                },
                .trap => return_stack_removals = known(1),
                .hault => return_stack_removals = known(1), // no net change
                .int => return_stack_removals = known(1), // no net change
            }
        },
    }
    return StackSizeEffect{
        .data_stack_additions = data_stack_additions,
        .data_stack_removals = data_stack_removals,
        .return_stack_additions = return_stack_additions,
        .return_stack_removals = return_stack_removals,
    };
}

const types = @import("types.zig");
const Type = types.Type;
const Stack = @import("stack.zig");
const psudo_opcodes = @import("psudo_opcodes.zig");
const core = @import("core");
const opcode = core.opcode;
const Instruction = opcode.Instruction;
const Registry = @import("registry.zig");
