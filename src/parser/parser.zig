// parser combinators

pub const ParseError = error{
    InvalidInput,
    UnexpectedEndOfInput,
    UnexpectedToken,
    CustomError,
};

pub fn ParseResult(comptime T: type, comptime R: type) type {
    if (R != void) {
        return anyerror!struct { []const R, []const T };
    }
    return anyerror![]T;
}

pub fn Parser(comptime T: type, comptime R: type) type {
    return fn (input: []const T, arguments: anytype) ParseResult(T, R);
}

pub fn expectType(comptime T: type, argument: anytype) T {
    const ArgumentType = @TypeOf(argument);
    const argument_info = @typeInfo(ArgumentType);
    const t_info = @typeInfo(T);
    if (argument_info == .comptime_int and t_info == .int) {
        return @as(T, argument);
    }
    if (ArgumentType != T) {
        const message: []const u8 = "ERROR: Expected argument of type " ++ @typeName(T) ++ ", got " ++ @typeName(ArgumentType);
        @panic(message);
    }
    return @as(T, argument);
}

pub fn either(
    comptime T: type,
    comptime R: type,
    left: Parser(T, R),
    right: Parser(T, R),
) Parser(T, R) {
    return struct {
        pub fn _P(input: []const T, arguments: anytype) ParseResult(T, R) {
            const result1 = left(input, arguments) catch {
                const result2 = try right(input, arguments);
                return result2;
            };
            return result1;
        }
    }._P;
}

pub fn optional(
    comptime T: type,
    comptime R: type,
    parser: Parser(T, R),
) Parser(T, R) {
    return struct {
        pub fn _P(input: []const T, arguments: anytype) ParseResult(T, R) {
            const parse_result = parser(input, arguments) catch {
                return .{ &[_]R{}, input };
            };
            return parse_result;
        }
    }._P;
}

pub fn choice(
    comptime T: type,
    comptime R: type,
    parsers: [*]const *const Parser(T, R),
    comptime len: usize,
) Parser(T, R) {
    return struct {
        pub fn _P(input: []const T, arguments: anytype) ParseResult(T, R) {
            var result: ParseResult(T, R) = undefined;
            inline for (0..len) |i| {
                const parser: *const Parser(T, R) = parsers[i];
                const parse_result = parser(input, arguments);
                if (!meta.isError(parse_result)) {
                    result = parse_result;
                    return result;
                }
            }
            std.debug.print("No parser matched input: {s}\n", .{input});
            std.debug.print("result: {any}\n", .{result});
            return error.InvalidInput;
        }
    }._P;
}

pub fn sequence(
    comptime T: type,
    comptime R: type,
    parsers: []*const Parser(T, R),
) Parser(T, R) {
    return struct {
        pub fn _P(input: []const T, arguments: anytype) ParseResult(T, R) {
            var result: []T = &[_]T{};
            var current_input = input;
            var i: usize = 0;
            while (i < parsers.len) : (i += 1) {
                const parser = parsers[i];
                const parse_result = try parser(current_input, arguments);
                if (result.len == 0) {
                    result = parse_result[0][0..];
                } else {
                    result = input[0 .. parse_result[0].len + result.len];
                }
                current_input = input[parse_result[0].len..];
            }

            return .{ result, current_input };
        }
    }._P;
}

pub fn many(
    comptime T: type,
    comptime R: type,
    parser: Parser(T, R),
) Parser(T, R) {
    return struct {
        pub fn _P(input: []const T, arguments: anytype) ParseResult(T, R) {
            var result: []const T = &[_]T{};
            var current_input: []const T = input;
            if (result.len == 0) {
                const parse_result = parser(current_input, arguments) catch {
                    return .{ result, current_input };
                };
                result = parse_result[0][0..];
                current_input = current_input[parse_result[0].len..];
            }
            while (current_input.len > 0) {
                const parse_result = parser(current_input, arguments) catch {
                    return .{ result, current_input };
                };
                if (parse_result[0].len == 0) {
                    break; // No more matches
                }
                result = input[0 .. parse_result[0].len + result.len];
                current_input = current_input[parse_result[0].len..];
            }
            std.debug.print("result: {s}\n", .{result});
            return .{ result, current_input };
        }
    }._P;
}

const std = @import("std");
const mem = std.mem;
const meta = std.meta;
