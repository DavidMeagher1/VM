pub const ParseResult = parser.ParseResult(u8, u8);

const digits: []const u8 = &[_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' };
const white_space: []const u8 = &[_]u8{ ' ', '\t', '\n', '\r' };

pub fn character(input: []const u8, arguments: anytype) ParseResult {
    const char = expectType(u8, arguments);
    if (input.len == 0) {
        return error.UnexpectedEndOfInput;
    }
    if (input[0] != char) {
        return error.UnexpectedToken;
    }
    return .{ input[0..1], input[1..] };
}

pub fn digit(input: []const u8, arguments: anytype) ParseResult {
    const num = expectType(u8, arguments[0]);
    const base = expectType(u8, arguments[1]);
    // convert number to base from base 10 to base `base`
    if (base < 2 or base > 16) {
        return error.InvalidInput; // Base must be between 2 and 16
    }
    var num_char: u8 = 0;
    if (num < 10) {
        num_char = '0' + num;
    } else if (num < 16) {
        num_char = 'a' + (num - 10);
    } else {
        return error.InvalidInput; // Number must be between 0 and 15 for base 16
    }
    return character(input, num_char);
}

pub fn anyDigit(input: []const u8, arguments: anytype) ParseResult {
    const base = expectType(u8, arguments);
    if (base < 2 or base > 16) {
        return error.InvalidInput; // Base must be between 2 and 16
    }
    if (input.len == 0) {
        return error.UnexpectedEndOfInput;
    }
    const first_char = input[0];
    if (first_char > base - 1 + '0') {
        return error.UnexpectedToken;
    }
    const digit_index = mem.indexOf(u8, digits, &[_]u8{std.ascii.toLower(first_char)});
    if (digit_index == null) {
        return error.UnexpectedToken;
    }
    return .{ input[0..1], input[1..] };
}

pub const manyAnyDigit = parser.many(u8, u8, anyDigit);

pub fn uppercaseCharacter(input: []const u8, arguments: anytype) ParseResult {
    const char = expectType(u8, arguments);
    if (input.len == 0) {
        return error.UnexpectedEndOfInput;
    }
    if (input[0] != char and input[0] != std.ascii.toUpper(char)) {
        return error.UnexpectedToken;
    }
    return .{ &[_]u8{input[0]}, input[1..] };
}

pub fn lowercaseCharacter(input: []const u8, arguments: anytype) ParseResult {
    const char = expectType(u8, arguments);
    if (input.len == 0) {
        return error.UnexpectedEndOfInput;
    }
    if (input[0] != char and input[0] != std.ascii.toLower(char)) {
        return error.UnexpectedToken;
    }
    return .{ &[_]u8{input[0]}, input[1..] };
}

pub fn eitherLowerOrUppercaseCharacter(input: []const u8, arguments: anytype) ParseResult {
    const char = expectType(u8, arguments);
    if (input.len == 0) {
        return error.UnexpectedEndOfInput;
    }
    if (input[0] != char and (input[0] != std.ascii.toLower(char) or input[0] != std.ascii.toUpper(char))) {
        return error.UnexpectedToken;
    }
    return .{ &[_]u8{input[0]}, input[1..] };
}

pub fn anyCharacter(input: []const u8, arguments: anytype) ParseResult {
    _ = arguments; // Unused, but required for the function signature
    if (input.len == 0) {
        return error.UnexpectedEndOfInput;
    }
    return .{ &[_]u8{input[0]}, input[1..] };
}

pub fn eitherCharacter(input: []const u8, arguments: anytype) ParseResult {
    const characters = expectType([]const u8, arguments);
    if (input.len == 0) {
        return error.UnexpectedEndOfInput;
    }
    for (characters, 0..) |char, i| {
        if (input[0] == char) {
            return .{ characters[i .. i + 1], input[1..] };
        }
    }
    return error.UnexpectedToken;
}

pub fn whitespace(input: []const u8, arguments: anytype) ParseResult {
    _ = arguments; // Unused, but required for the function signature
    return eitherCharacter(input, white_space);
}

pub fn notWhitespace(input: []const u8, arguments: anytype) ParseResult {
    _ = arguments; // Unused, but required for the function signature
    if (input.len == 0) {
        return error.UnexpectedEndOfInput;
    }
    const whitespace_index = mem.indexOf(u8, white_space, input[0..1]);
    if (whitespace_index == null) {
        return .{ input[0..1], input[1..] };
    }
    return error.UnexpectedToken;
}

pub const manyWhitespace = parser.many(u8, u8, whitespace);
pub const manyNotWhitespace = parser.many(u8, u8, notWhitespace);
pub const optional_whitespace = parser.optional(u8, u8, whitespace);
pub const optionalManyWhitespace = parser.optional(u8, u8, manyWhitespace);

pub fn string(input: []const u8, arguments: anytype) ParseResult {
    const str = expectType([]const u8, arguments);
    if (input.len < str.len) {
        return error.UnexpectedEndOfInput;
    }
    if (!std.mem.startsWith(u8, input, str)) {
        return error.UnexpectedToken;
    }
    return .{ str, input[str.len..] };
}

pub fn trim(input: []const u8, arguments: anytype) ParseResult {
    const first_whitespace = try manyWhitespace(input, arguments);
    const inner_content = try manyNotWhitespace(first_whitespace[1], arguments);
    const last_whitespace = try manyWhitespace(inner_content[1], arguments);
    return .{ inner_content[0], last_whitespace[1] };
}

test "character" {
    const input = "a";
    const result = try character(input, 'a');
    try std.testing.expect(result[0][0] == 'a');
    try std.testing.expect(result[1].len == 0);
}

test "anyCharacter" {
    const input = "b";
    const result = try anyCharacter(input, {});
    try std.testing.expect(result[0][0] == 'b');
    try std.testing.expect(result[1].len == 0);
}

test "eitherCharacter" {
    const input = "c";
    const characters: []const u8 = &[_]u8{ 'a', 'b', 'c' };
    const result = try eitherCharacter(input, characters);
    try std.testing.expect(result[0][0] == 'c');
    try std.testing.expect(result[1].len == 0);
}

test "whitespace" {
    const input = " \t\n";
    const result = try whitespace(input, {});
    try std.testing.expect(result[0][0] == ' ');
    try std.testing.expect(result[1].len == 2);
}

test "manyWhitespace" {
    const input = " \t\n  ";
    const result = try manyWhitespace(input, {});
    try std.testing.expect(result[0].len == 5);
    try std.testing.expect(result[1].len == 0);
}

test "trim" {
    const input = "   hello   ";
    const result = try trim(input, {});
    try std.testing.expect(std.mem.eql(u8, result[0], "hello"));
    try std.testing.expect(result[1].len == 0);
}

test "digit" {
    const input = "5";
    const result = try digit(input, &[_]u8{ 5, 10 });
    std.debug.print("result: {s}\n", .{result[0]});
    try std.testing.expect(result[0][0] == '5');
    try std.testing.expect(result[1].len == 0);
}

test "anyDigit" {
    const input = "7";
    const result = try anyDigit(input, 10);
    try std.testing.expect(result[0][0] == '7');
    try std.testing.expect(result[1].len == 0);
}

test "manyAnyDigit" {
    const input = "123abc";
    const result = try manyAnyDigit(input, 10);
    try std.testing.expect(std.mem.eql(u8, result[0], "123"));
    try std.testing.expect(result[1].len == 3);
}

const std = @import("std");
const mem = std.mem;
const parser = @import("parser.zig");
const expectType = parser.expectType;
