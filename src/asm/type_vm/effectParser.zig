// @ denotes the data stack
// # denotes the return stack
// so for the signature for a indirect call it would look like this:
// (@*u16 -- #*u16)
// parser for stack effect strings eg: (i8 i8 -- i8)

// first parsing the string into a list of tokens

pub const Error = error{
    InvalidStackEffect,
    InvalidStackEffectToken,
    InvalidStackEffectType,
};

pub const StackSelector = enum {
    data_stack,
    return_stack,
};

pub const Effect = struct { StackSelector, *const Type };

pub const EffectParser = parser.Parser(u8, Effect);
pub const EffectParseResult = parser.ParseResult(u8, Effect);
pub const StackEffectParser = parser.Parser(u8, StackEffect);
pub const StackEffectParseResult = parser.ParseResult(u8, StackEffect);

pub const StackEffect = struct {
    removals: []Effect,
    additions: []Effect,

    pub fn deinit(self: *StackEffect, allocator: Allocator) void {
        allocator.free(self.removals);
        allocator.free(self.additions);
    }
};

const u8_t: Type = .{
    .integer = .{
        .size = 1,
        .sign = .unsigned,
        .alignment = .one,
    },
};

const any_t: Type = .{
    .any = undefined,
};

const void_t: Type = .{
    .void = undefined,
};

const undefined_t: Type = .{
    .undefined = undefined,
};
const bool_t: Type = .{
    .bool = undefined,
};

const comptime_int_t: Type = .{
    .comptime_int = undefined,
};

const comptime_fixed_t: Type = .{
    .comptime_fixed = undefined,
};

const ptr_void_t: Type = .{
    .pointer = .{
        .kind = .one,
        .child = &void_t,
    },
};

const ptr_many_any_t: Type = .{
    .pointer = .{
        .kind = .many,
        .child = &any_t,
    },
};

pub fn getInstructionStackEffect(instruction: Instruction, allocator: Allocator) !StackEffect {
    const selector = if (instruction.stack == 0) StackSelector.data_stack else StackSelector.return_stack;
    var stack_removals = ArrayList(Effect).init(allocator);
    var stack_additions = ArrayList(Effect).init(allocator);
    defer stack_removals.deinit();
    defer stack_additions.deinit();

    switch (selector) {
        .data_stack => {
            switch (instruction.baseOpcode) {
                .push, .push_reg => {
                    try stack_additions.append(.{ .data_stack, &any_t });
                },
                .pop, .pop_reg => {
                    try stack_removals.append(.{ .data_stack, &any_t });
                },
                .dup => {
                    try stack_additions.append(.{ .data_stack, &any_t });
                },
                .swap, .over => {}, // no net change
                .load => {
                    try stack_removals.append(.{ .data_stack, &u8_t });
                    try stack_removals.append(.{ .data_stack, &ptr_many_any_t });
                    try stack_additions.append(.{ .data_stack, &undefined_t });
                },
                .store => {
                    try stack_removals.append(.{ .data_stack, &u8_t });
                    try stack_removals.append(.{ .data_stack, &ptr_many_any_t });
                    try stack_removals.append(.{ .data_stack, &undefined_t });
                },
                .flip => {
                    try stack_removals.append(.{ .data_stack, &any_t });
                    try stack_additions.append(.{ .return_stack, &any_t });
                },
                // arithmetic operations
                .add, .sub, .mul, .div => {
                    try stack_removals.append(.{ .data_stack, &comptime_int_t });
                    try stack_removals.append(.{ .data_stack, &comptime_int_t });
                    try stack_additions.append(.{ .data_stack, &comptime_int_t });
                },
                // fixed point operations
                .fx_add, .fx_sub, .fx_mul, .fx_div => {
                    try stack_removals.append(.{ .data_stack, &comptime_fixed_t });
                    try stack_removals.append(.{ .data_stack, &comptime_fixed_t });
                    try stack_additions.append(.{ .data_stack, &comptime_fixed_t });
                },
                // bitwise operations
                .@"and", .@"or", .xor, .not => {
                    try stack_removals.append(.{ .data_stack, &comptime_int_t });
                    try stack_removals.append(.{ .data_stack, &comptime_int_t });
                    try stack_additions.append(.{ .data_stack, &comptime_int_t });
                },
                // shift operations
                .shl, .shr => {
                    try stack_removals.append(.{ .data_stack, &comptime_int_t });
                    try stack_removals.append(.{ .data_stack, &comptime_int_t });
                    try stack_additions.append(.{ .data_stack, &comptime_int_t });
                },
                // logical operations
                .cmp => {
                    try stack_removals.append(.{ .data_stack, &comptime_int_t });
                    try stack_removals.append(.{ .data_stack, &comptime_int_t });
                    try stack_additions.append(.{ .data_stack, &comptime_int_t });
                },
                // control flow
                .jmp => {}, // no net change
                .jnz => {
                    try stack_removals.append(.{ .data_stack, &bool_t });
                }, // one value is removed for the condition
                .call => {
                    // stack selector for call is actually used to tell if it is a FFI call or native
                    // we need to check the width bit to see if it is immediate or not
                    // if it is immediate we dont remove anything from the data stack
                    // if it is not immediate we remove the return address from the data stack

                    switch (instruction.width) {
                        0 => {}, // immediate
                        1 => {
                            try stack_removals.append(.{ .data_stack, &ptr_void_t });
                        }, // not immediate
                    }
                    try stack_additions.append(.{ .data_stack, &ptr_void_t });
                },
                .trap => {
                    try stack_removals.append(.{ .data_stack, &u8_t });
                },
                .halt => {
                    try stack_removals.append(.{ .data_stack, &u8_t });
                }, // no net change
                .int => {
                    try stack_removals.append(.{ .data_stack, &u8_t });
                }, // no net change
                else => {},
            }
        },
        .return_stack => {
            switch (instruction.baseOpcode) {
                .push => {
                    try stack_additions.append(.{ .return_stack, &any_t });
                },
                .pop => {
                    try stack_removals.append(.{ .return_stack, &any_t });
                },
                .dup => {
                    try stack_additions.append(.{ .return_stack, &any_t });
                },
                .swap, .over => {}, // no net change
                .load => {
                    try stack_removals.append(.{ .return_stack, &u8_t });
                    try stack_removals.append(.{ .return_stack, &ptr_many_any_t });
                    try stack_additions.append(.{ .return_stack, &undefined_t });
                },
                .store => {
                    try stack_removals.append(.{ .return_stack, &u8_t });
                    try stack_removals.append(.{ .return_stack, &ptr_many_any_t });
                    try stack_removals.append(.{ .return_stack, &undefined_t });
                    // we remove a variadic number of any types
                }, // a value for len is removed and a pointer and N values,
                .flip => {
                    try stack_removals.append(.{ .return_stack, &any_t });
                    try stack_additions.append(.{ .data_stack, &any_t });
                },
                // arithmetic operations
                .add, .sub, .mul, .div => {
                    try stack_removals.append(.{ .return_stack, &comptime_int_t });
                    try stack_removals.append(.{ .return_stack, &comptime_int_t });
                    try stack_additions.append(.{ .return_stack, &comptime_int_t });
                },
                // fixed point operations
                .fx_add, .fx_sub, .fx_mul, .fx_div => {
                    try stack_removals.append(.{ .return_stack, &comptime_fixed_t });
                    try stack_removals.append(.{ .return_stack, &comptime_fixed_t });
                    try stack_additions.append(.{ .return_stack, &comptime_fixed_t });
                },
                // bitwise operations
                .@"and", .@"or", .xor, .not => {
                    try stack_removals.append(.{ .return_stack, &comptime_int_t });
                    try stack_removals.append(.{ .return_stack, &comptime_int_t });
                    try stack_additions.append(.{ .return_stack, &comptime_int_t });
                },
                // shift operations
                .shl, .shr => {
                    try stack_removals.append(.{ .return_stack, &comptime_int_t });
                    try stack_removals.append(.{ .return_stack, &comptime_int_t });
                    try stack_additions.append(.{ .return_stack, &comptime_int_t });
                },
                // logical operations
                .cmp => {
                    try stack_removals.append(.{ .return_stack, &any_t });
                    try stack_removals.append(.{ .return_stack, &any_t });
                    try stack_additions.append(.{ .return_stack, &bool_t });
                },
                // control flow
                .jmp => {}, // no net change
                .jnz => {
                    try stack_removals.append(.{ .return_stack, &bool_t });
                }, // one value is removed for the condition
                .call => {
                    // stack selector for call is actually used to tell if it is a FFI call or native
                    // we need to check the width bit to see if it is immediate or not
                    // if it is immediate we dont remove anything from the return stack
                    // if it is not immediate we remove the return address from the return stack

                    switch (instruction.width) {
                        0 => {}, // immediate
                        1 => {
                            try stack_removals.append(.{ .return_stack, &ptr_void_t });
                        }, // not immediate
                    }
                    try stack_additions.append(.{ .return_stack, &ptr_void_t });
                },
                .trap => {
                    try stack_removals.append(.{ .return_stack, &u8_t });
                },
                .halt => {
                    try stack_removals.append(.{ .return_stack, &u8_t });
                }, // no net change
                .int => {
                    try stack_removals.append(.{ .return_stack, &u8_t });
                }, // no net change
                else => {},
            }
        },
    }
    const removals = try stack_removals.toOwnedSlice();
    const additions = try stack_additions.toOwnedSlice();

    return StackEffect{
        .removals = removals,
        .additions = additions,
    };
}

pub fn parseEffect(input: []const u8, arguments: anytype) EffectParseResult {
    //effects start with stack selector
    const selector_chars: []const u8 = &[_]u8{ '@', '#' };
    const a = try char_parser.eitherCharacter(input, selector_chars);
    const stack_selector: StackSelector = switch (a[0][0]) {
        '@' => .data_stack,
        '#' => .return_stack,
        else => return error.InvalidStackEffect,
    };
    const b = type_parser.parseType(a[1], arguments) catch return error.InvalidStackEffect;
    if (b[0].len == 0) {
        return error.InvalidStackEffectType;
    }
    const effect_type: Type = b[0][0];
    if (effect_type.isEqual(undefined_t)) {
        return error.InvalidStackEffectType;
    }
    return .{ &[_]Effect{.{ stack_selector, &effect_type }}, b[1] };
}

pub fn parseStackEffect(input: []const u8, arguments: anytype) StackEffectParseResult {
    var removals = ArrayList(Effect).init(arguments.allocator);
    var additions = ArrayList(Effect).init(arguments.allocator);
    defer removals.deinit();
    defer additions.deinit();

    const State = enum {
        removals,
        additions,
    };

    var current_state: State = .removals;

    var remaining_input = input;
    const lparen = char_parser.character(remaining_input, '(') catch return error.InvalidStackEffect;
    remaining_input = lparen[1];
    const opt_begin_whitespace = try char_parser.optionalManyWhitespace(remaining_input, arguments);
    remaining_input = opt_begin_whitespace[1];
    if (remaining_input.len == 0) {
        return error.InvalidStackEffect;
    }

    while (remaining_input.len > 0) {
        const opt_effect = try parser.optional(u8, Effect, parseEffect)(remaining_input, arguments);
        if (opt_effect[0].len == 0) {
            // no more effects, switch to additions
            if (current_state == .removals) {
                current_state = .additions;
                continue;
            } else {
                // no more effects and already in additions state, break
                break;
            }
        }
        const effect = opt_effect;
        const effect_item = effect[0][0];
        switch (current_state) {
            .removals => {
                try removals.append(effect_item);
            },
            .additions => {
                try additions.append(effect_item);
            },
        }
        remaining_input = effect[1];
        const whitespace = char_parser.manyWhitespace(remaining_input, arguments) catch return error.InvalidStackEffect;
        remaining_input = whitespace[1];
        if (remaining_input.len == 0) {
            return error.InvalidStackEffect;
        }
        const dash_str: []const u8 = "--";
        const dash = parser.optional(u8, u8, char_parser.string)(remaining_input, dash_str) catch return error.InvalidStackEffect;
        if (dash[0].len > 0) {
            // switch to additions state
            if (current_state == .removals) {
                current_state = .additions;
                remaining_input = dash[1];
                const opt_add_whitespace = try char_parser.optionalManyWhitespace(remaining_input, arguments);
                remaining_input = opt_add_whitespace[1];
                if (remaining_input.len == 0) {
                    return error.InvalidStackEffect;
                }
            } else {
                // we are already in additions state, so this is an error
                return error.InvalidStackEffect;
            }
        }
    }
    std.debug.print("remaining_input: {s}\n", .{remaining_input});
    const rparen = char_parser.character(remaining_input, ')') catch return error.InvalidStackEffect;
    remaining_input = rparen[1];
    if (remaining_input.len > 0) {
        return error.InvalidStackEffect;
    }
    return .{ &[_]StackEffect{StackEffect{
        .removals = try removals.toOwnedSlice(),
        .additions = try additions.toOwnedSlice(),
    }}, remaining_input };
}

test "parseEffect" {
    const input = "@i8";
    const result = try parseEffect(input, .{ .allocator = std.testing.allocator });
    try std.testing.expectEqual(.{ &[_]Effect{.{ .data_stack, &Type{ .integer = .{ .size = 8, .sign = .unsigned, .alignment = .one } } }}, "" }, result);
}

test "parseStackEffect" {
    const input = "( @i8 -- @i16 )";
    var result = try parseStackEffect(input, .{ .allocator = std.testing.allocator });
    var seffect: StackEffect = undefined;
    seffect = result[0][0];
    defer seffect.deinit(std.testing.allocator);
    result[0][0].deinit(std.testing.allocator);

    var alloc_test_removal = std.testing.allocator.alloc(Effect, 1) catch unreachable;
    var alloc_test_addition = std.testing.allocator.alloc(Effect, 1) catch unreachable;
    defer std.testing.allocator.free(alloc_test_removal);
    defer std.testing.allocator.free(alloc_test_addition);
    alloc_test_removal[0] = .{ .data_stack, &Type{ .integer = .{ .size = 8, .sign = .unsigned, .alignment = .one } } };
    alloc_test_addition[0] = .{ .data_stack, &Type{ .integer = .{ .size = 16, .sign = .unsigned, .alignment = .two } } };
    const expected = StackEffect{
        .removals = alloc_test_removal,
        .additions = alloc_test_addition,
    };
    defer expected.deinit(std.testing.allocator);
    std.debug.print("result: {any}\n", .{result});
    try std.testing.expectEqual(.{
        &[_]StackEffect{expected},
        "",
    }, result);
}

const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const types = @import("types.zig");
const Type = types.Type;
//const core = @import("core");
const opcode = @import("../../core/opcode.zig");
//const opcode = core.opcode;
const Instruction = opcode.Instruction;
const parser = @import("../../parser/parser.zig");
const char_parser = @import("../../parser/char_parser.zig");
const type_parser = @import("type_parser.zig");
