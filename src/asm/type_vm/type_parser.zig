pub const Parser = parser.Parser(u8, Type);
pub const ParseResult = parser.ParseResult(u8, Type);

pub fn parseAny(input: []const u8, arguments: anytype) ParseResult {
    _ = arguments; // Unused, but required for the function signature
    const any_string: []const u8 = "any";
    const res = char_parser.string(input, any_string) catch {
        return error.InvalidType;
    };
    return .{ &[_]Type{.{ .any = undefined }}, res[1] };
}

pub fn parseVoid(input: []const u8, arguments: anytype) ParseResult {
    _ = arguments; // Unused, but required for the function signature
    const void_string: []const u8 = "void";
    const res = char_parser.string(input, void_string) catch {
        return error.InvalidType;
    };
    return .{ &[_]Type{.{ .void = undefined }}, res[1] };
}

pub fn parseNull(input: []const u8, arguments: anytype) ParseResult {
    _ = arguments; // Unused, but required for the function signature
    const null_string: []const u8 = "null";
    const res = char_parser.string(input, null_string) catch {
        return error.InvalidType;
    };
    return .{ &[_]Type{.{ .null = undefined }}, res[1] };
}

pub fn parseBool(input: []const u8, arguments: anytype) ParseResult {
    _ = arguments; // Unused, but required for the function signature
    const bool_string: []const u8 = "bool";
    const res = char_parser.string(input, bool_string) catch {
        return error.InvalidType;
    };
    return .{ &[_]Type{.{ .bool = undefined }}, res[1] };
}

pub fn parseTypeType(input: []const u8, arguments: anytype) ParseResult {
    _ = arguments; // Unused, but required for the function signature
    const type_string: []const u8 = "type";
    const res = char_parser.string(input, type_string) catch {
        return error.InvalidType;
    };
    return .{ &[_]Type{.{ .type = undefined }}, res[1] };
}

pub fn parseComptimeInt(input: []const u8, arguments: anytype) ParseResult {
    _ = arguments; // Unused, but required for the function signature
    const comptime_int_string: []const u8 = "comptime_int";
    const res = char_parser.string(input, comptime_int_string) catch {
        return error.InvalidType;
    };
    return .{ &[_]Type{.{ .comptime_int = undefined }}, res[1] };
}

pub fn parseComtimeFixed(input: []const u8, arguments: anytype) ParseResult {
    _ = arguments; // Unused, but required for the function signature
    const comptime_fixed_string: []const u8 = "comptime_fixed";
    const res = char_parser.string(input, comptime_fixed_string) catch {
        return error.InvalidType;
    };
    return .{ &[_]Type{.{ .comptime_fixed = undefined }}, res[1] };
}

pub fn parseInteger(input: []const u8, arguments: anytype) ParseResult {
    _ = arguments; // Unused, but required for the function signature
    const sign_chars: []const u8 = "ui";
    const sign_char = try char_parser.eitherCharacter(input, sign_chars);
    const bit_chars = try char_parser.manyAnyDigit(sign_char[1], 16);
    std.debug.print("bit_chars: {s}\n", .{bit_chars[0]});
    const sign: types.Sign = if (sign_char[0][0] == 'u') .unsigned else .signed;
    const bits = std.fmt.parseInt(u5, bit_chars[0], 16) catch |err| {
        if (err == std.fmt.ParseIntError.InvalidCharacter) {
            std.debug.print("Invalid bits: {s}\n", .{bit_chars[0]});
            return error.InvalidInteger;
        }
        return err;
    };
    return .{ &[_]Type{.{ .integer = .{ .sign = sign, .size = bits, .alignment = types.Alignment.nearestAlignment(bits) } }}, bit_chars[1] };
}

pub fn parseFixed(input: []const u8, arguments: anytype) ParseResult {
    _ = arguments; // Unused, but required for the function signature
    const sign_chars: []const u8 = "ui";
    const sign_char = try char_parser.eitherCharacter(input, sign_chars);
    const int_bit_chars = try char_parser.manyAnyDigit(sign_char[1], 16);
    const period = try char_parser.character(int_bit_chars[1], '.');
    const fract_bit_chars = try char_parser.manyAnyDigit(period[1], 16);
    const sign: types.Sign = if (sign_char[0][0] == 'u') .unsigned else .signed;
    const int_bits = std.fmt.parseInt(u5, int_bit_chars[0], 16) catch |err| {
        if (err == std.fmt.ParseIntError.InvalidCharacter) {
            return error.InvalidFixed;
        }
        return err;
    };
    const fract_bits = std.fmt.parseInt(u5, fract_bit_chars[0], 16) catch |err| {
        if (err == std.fmt.ParseIntError.InvalidCharacter) {
            return error.InvalidFixed;
        }
        return err;
    };
    return .{ &[_]Type{.{ .fixed = .{ .sign = sign, .integer_size = int_bits, .fraction_size = fract_bits, .alignment = .four } }}, fract_bit_chars[1] };
}

pub fn parsePointer(input: []const u8, arguments: anytype) ParseResult {
    const a = try char_parser.eitherCharacter(input, @as([]const u8, "[*"));
    var kind: types.PtrKind = undefined;
    var ninput: []const u8 = undefined;
    if (a[0][0] == '[') {
        const b = try char_parser.character(a[1], "*");
        const c = try char_parser.character(b[1], ']');
        ninput = c[1];
        kind = .many;
    } else {
        ninput = a[1];
        kind = .one;
    }
    const b = try parseType(ninput, arguments);
    return .{ &[_]Type{.{ .pointer = .{ .kind = kind, .child = &b[0][0] } }}, b[1] };
}

pub fn parseArray(input: []const u8, arguments: anytype) ParseResult {
    const a = try char_parser.character(input, '[');
    const b = try char_parser.manyAnyDigit(a[1], 16);
    const c = try char_parser.character(b[1], ']');
    const size = std.fmt.parseInt(u32, c[0], 16) catch |err| {
        if (err == std.fmt.ParseIntError.InvalidCharacter) {
            return error.InvalidArraySize;
        }
        return err;
    };
    const d = try parseType(c[1], arguments);
    return .{ &[_]Type{.{ .array = .{ .size = size, .child = &d[0][0] } }}, d[1] };
}

pub fn parseType(input: []const u8, arguments: anytype) ParseResult {
    const type_fns = &[_]*const Parser{
        &parseAny,
        &parseVoid,
        &parseNull,
        &parseBool,
        &parseTypeType,
        &parseComptimeInt,
        &parseComtimeFixed,
        &parseInteger,
        &parseFixed,
        &parsePointer,
        &parseArray,
    };
    return parser.choice(
        u8,
        Type,
        type_fns,
        type_fns.len,
    )(input, arguments);
}

const std = @import("std");
const mem = std.mem;
const types = @import("./types.zig");
const Type = types.Type;
const parser = @import("../../parser/parser.zig");
const char_parser = @import("../../parser/char_parser.zig");
