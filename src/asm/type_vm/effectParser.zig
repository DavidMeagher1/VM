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

pub const StackEffect = struct {
    removals: []Type,
    additions: []Type,
    size_effect: StackSizeEffect,
};

pub fn getStackEffectTokens(
    effect: []const u8,
) !mem.TokenIterator(u8, .scalar) {
    // remove the brackets
    if (effect.len < 2) {
        return Error.InvalidStackEffect;
    }
    if (effect[0] != '(' or effect[effect.len - 1] != ')') {
        return Error.InvalidStackEffect;
    }
    const trimmed = effect[1 .. effect.len - 1];
    // check for empty string
    if (trimmed.len == 0) {
        return Error.InvalidStackEffect;
    }
    const tokens = mem.tokenizeScalar(u8, trimmed, ' ');
    return tokens;
}

// then parsing a token into a type
pub fn parseType(allocator: Allocator, token: []const u8, reg: *Registry) !struct { StackSelector, Type } {
    var stack_slector: StackSelector = undefined;
    var processed: u32 = 0;
    // check for empty string
    if (token.len == 0) {
        return Error.InvalidStackEffectToken;
    }
    // trim whitespace
    const trimmed = mem.trim(u8, token, " \t\n\r");
    // first check the stack selector
    switch (trimmed[0]) {
        '@' => {
            stack_slector = StackSelector.data_stack;
        },
        '#' => {
            stack_slector = StackSelector.return_stack;
        },
        else => {
            return Error.InvalidStackEffectToken;
        },
    }
    processed += 1;
    // check for the type
    const t = Type.fromString(trimmed[processed..], reg, allocator) orelse {
        return Error.InvalidStackEffectType;
    };
    return .{ stack_slector, t };
}

pub fn parseStackEffect(
    allocator: Allocator,
    effect: []const u8,
    reg: *Registry,
) !StackEffect {
    var tokens = try getStackEffectTokens(effect);
    var data_stack_additions: u32 = 0;
    var data_stack_removals: u32 = 0;
    var return_stack_additions: u32 = 0;
    var return_stack_removals: u32 = 0;

    var removal_types: ArrayList(Type) = ArrayList(Type).init(allocator);
    var addition_types: ArrayList(Type) = ArrayList(Type).init(allocator);
    defer addition_types.deinit();
    defer removal_types.deinit();

    const State = enum {
        removals,
        additions,
    };
    var state = State.removals;
    while (tokens.next()) |token| {
        if (token.len == 0) {
            continue;
        }
        if (std.mem.eql(u8, token, "--") or std.mem.eql(u8, token, "->")) {
            if (state == State.removals) {
                state = State.additions;
            } else {
                return Error.InvalidStackEffect;
            }
            continue;
        }
        const t_info = try parseType(allocator, token, reg);
        // check for the stack selector
        switch (state) {
            .removals => {
                try removal_types.append(t_info[1]);
            },
            .additions => {
                try addition_types.append(t_info[1]);
            },
        }
        switch (t_info[0]) {
            .data_stack => {
                if (state == .removals) {
                    data_stack_removals += 1;
                } else {
                    data_stack_additions += 1;
                }
            },
            .return_stack => {
                if (state == .removals) {
                    return_stack_removals += 1;
                } else {
                    return_stack_additions += 1;
                }
            },
        }
    }
    const removals = try removal_types.toOwnedSlice();
    const additions = try addition_types.toOwnedSlice();
    return StackEffect{
        .removals = removals,
        .additions = additions,
        .size_effect = StackSizeEffect{
            .data_stack_additions = validator.known(data_stack_additions),
            .data_stack_removals = validator.known(data_stack_removals),
            .return_stack_additions = validator.known(return_stack_additions),
            .return_stack_removals = validator.known(return_stack_removals),
        },
    };
}

// lets make a test for the parser
test "parseStackEffect" {
    const allocator = std.heap.page_allocator;
    var reg = try Registry.init(allocator);
    defer reg.deinit();
    const effect = "(@ia @i8 -- #i8)";
    _ = try reg.register_type(
        Type{ .integer = .{
            .sign = .signed,
            .size = 7,
            .alignment = .one,
        } },
        "i8",
    );
    _ = try reg.register_type(
        Type{ .integer = .{
            .sign = .signed,
            .size = 15,
            .alignment = .two,
        } },
        "i10",
    );
    _ = try reg.register_type(
        Type{ .integer = .{
            .sign = .signed,
            .size = 31,
            .alignment = .four,
        } },
        "i20",
    );
    const parsed = try parseStackEffect(allocator, effect, &reg);
    std.debug.print("Parsed stack effect: {any}\n", .{parsed});
    // print the types
    for (parsed.removals) |t| {
        std.debug.print("Removal type: {s}\n", .{try t.toString(&reg, allocator)});
        std.debug.print("Removal type size: {d}\n", .{t.integer.size});
    }

    for (parsed.additions) |t| {
        std.debug.print("Addition type: {s}\n", .{try t.toString(&reg, allocator)});
        std.debug.print("Addition type size: {d}\n", .{t.integer.size});
    }
}

const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const types = @import("types.zig");
const Type = types.Type;
const validator = @import("validator.zig");
const StackSizeEffect = validator.StackSizeEffect;
const StackSelector = validator.StackSelector;
const Registry = @import("registry.zig");
