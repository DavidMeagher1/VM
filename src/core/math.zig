// fixed point operations

//     fx_add, // adds the top two values of the selected stack with a fixed point addition

pub const FXError = error{
    DivisionByZero,
    UnsupportedType,
};

pub fn fx_add(comptime T: type, a: T, b: T) T {
    return a + b;
}

pub fn fx_sub(comptime T: type, a: T, b: T) T {
    return a - b;
}

pub fn fx_mul(comptime T: type, a: T, b: T) FXError!T {
    const scale = switch (@typeInfo(T)) {
        .Int, .ComptimeInt => switch (@sizeOf(T)) {
            2 => 1 << 8, // 8.8 fixed point for 16-bit ints
            4 => 1 << 16, // 16.16 fixed point for 32-bit ints
            else => return FXError.UnsupportedType,
        },
        else => return FXError.UnsupportedType,
    };
    return @divTrunc(a * b, scale);
}

pub fn fx_div(comptime T: type, a: T, b: T) FXError!T {
    const scale = switch (@typeInfo(T)) {
        .Int, .ComptimeInt => switch (@sizeOf(T)) {
            2 => 1 << 8, // 8.8 fixed point for 16-bit ints
            4 => 1 << 16, // 16.16 fixed point for 32-bit ints
            else => return FXError.UnsupportedType,
        },
        else => return FXError.UnsupportedType,
    };
    if (b == 0) return FXError.DivisionByZero;
    return @divTrunc(a * scale, b);
}
