// just a reminder of how bits work
// 8  , 7 , 6 , 5 , 4, 3, 2, 1
// 128, 64, 32, 16, 8, 4, 2, 1

pub const TypeIndex = u32;
pub const TypeList = ArrayList(Type);

pub const FieldInfo = struct {
    name: []const u8,
    type: *const Type,
};

pub const UnionFieldInfo = struct {
    name: []const u8,
    type: *const Type,
};

pub const EnumFieldInfo = struct {
    name: []const u8,
    value: u8,
};

pub const Sign = enum {
    signed,
    unsigned,
};

pub const PtrKind = enum {
    one,
    many,
};

pub const StackEffect = @import("effectParser.zig").StackEffect;

pub const Word = struct {
    calling_convection: void, // TODO: implement calling convection
    stack_effect: StackEffect,
};

pub const Alignment = enum {
    one,
    two,
    four,

    pub fn nearestAlignment(bits: u6) Alignment {
        // this should round up to the nearest alignment
        if (bits == 0) return Alignment.one;
        if (bits <= 8) return Alignment.one;
        if (bits <= 16) return Alignment.two;
        if (bits <= 32) return Alignment.four;
        return Alignment.four; // this should never happen
    }
};

pub const Error = error{
    InvalidConversionError,
    InvalidCastError,
    ConversionSignError,
    ConversionSizeError,
    ConversionPointerKindError,
    AlignmentError,
    InvalidTypeError,
};

pub const Type = union(enum) {
    any: void, // can become any other type, used for the type checker
    void: void,
    null: void,
    bool: void,
    undefined: void,
    type: void,
    comptime_int: void,
    comptime_fixed: void,
    integer: struct {
        sign: Sign,
        size: u6, // the max number is 31 so the actual size is size + 1
        alignment: Alignment, // 0 = 1 byte, 1 = 2 bytes, 2 = 4 bytes
    },
    fixed: struct {
        sign: Sign,
        integer_size: u5, // the max number is 15 so the actual size is size + 1
        fraction_size: u5, // the max number is 15 so the actual size is size + 1
        alignment: Alignment, // 0 = 1 byte, 1 = 2 bytes, 2 = 4 bytes

        pub fn getScalingFactor(self: Type) u32 {
            return 1 << self.fraction_size;
        }
    },

    pointer: struct {
        kind: PtrKind, // one or many, or any
        child: *const Type,
    },
    array: struct {
        child: *const Type,
        size: u32, // the max number is 2^32 - 1
        // arrays alignment is always 1 byte
    },
    @"struct": struct {
        fields: []const FieldInfo,
        is_tuple: bool = false,
    },
    @"union": struct {
        fields: []const UnionFieldInfo,
    },
    @"enum": struct {
        tags: []EnumFieldInfo, // the values of the enum max of 255
    },
    optional: union(enum) {
        child: *const Type,
    },
    word: Word,

    pub fn size(self: Type) !u32 {
        switch (meta.activeTag(self)) {
            .any => {
                return 0; // any type has no size
            },
            .void => {
                return 0;
            },
            .null => {
                return 0;
            },
            .bool => {
                return 1;
            },
            .undefined => {
                return 0;
            },
            .type => {
                return 4; // type index is always 4 bytes
            },
            .comptime_int => {
                return 2; // comptime int is always 2 bytes
            },
            .comptime_fixed => {
                return 4; // comptime fixed is always 4 bytes
            },
            .integer => {
                if (self.integer.size > 32) {
                    return Error.InvalidTypeError;
                }
                return self.integer.size / 8;
            },
            .fixed => {
                if (self.fixed.integer_size > 16 or self.fixed.fraction_size > 16) {
                    return Error.InvalidTypeError;
                }
                return (self.fixed.integer_size + self.fixed.fraction_size) / 8;
            },
            .pointer => {
                return 2; // pointers are always 2 bytes
            },
            .array => {
                const child_size = self.child.size();
                return self.array.size * child_size;
            },
            .@"struct" => {
                var s: u32 = 0;
                for (self.@"struct".fields) |field| {
                    s += try field.type.size();
                }
                return s;
            },
            .@"union" => {
                var s: u32 = 0;
                for (self.@"union".fields) |field| {
                    s += try field.type.size();
                }
                return s;
            },
            .@"enum" => {
                return 1; // enums are always 1 byte
            },
            .optional => {
                return self.child.size() + 1; // optional types have an extra byte for the nullability flag
            },
            .word => {
                return 0; // words have no size
            },
        }
    }

    pub fn alignment(self: *Type) u32 {
        switch (meta.activeTag(self)) {
            .any => {
                return 0; // any type has no alignment
            },
            .void => {
                return 0;
            },
            .null => {
                return 0;
            },
            .bool => {
                return 1;
            },
            .undefined => {
                return 0;
            },
            .type => {
                return 4; // type index is always 4 bytes
            },
            .comptime_int => {
                return 2; // comptime int is always 2 bytes
            },
            .comptime_fixed => {
                return 4; // comptime fixed is always 4 bytes
            },
            .integer => {
                return self.integer.alignment;
            },
            .fixed => {
                return self.fixed.alignment;
            },
            .pointer => {
                return 1; // pointers are always 1 byte
            },
            .array => {
                return 1; // arrays are always 1 byte
            },
            .@"struct" => {
                return 1; // structs are always 1 byte
            },
            .@"union" => {
                return 1; // unions are always 1 byte
            },
            .@"enum" => {
                return 1; // enums are always 1 byte
            },
            .optional => {
                return 0; // TODO: fix size and alignment
            },
            .word => {
                return 0; // words have no alignment
            },
        }
    }

    pub fn isEqual(self: Type, other: Type) bool {
        if (meta.activeTag(self) == .any or meta.activeTag(other) == .any) {
            return true; // any type is equal to any type
        }
        if (meta.activeTag(self) != meta.activeTag(other)) {
            return false;
        }
        switch (meta.activeTag(self)) {
            .integer => {
                return self.integer.sign == other.integer.sign and
                    self.integer.size == other.integer.size and
                    self.integer.alignment == other.integer.alignment;
            },
            .fixed => {
                return self.fixed.sign == other.fixed.sign and
                    self.fixed.integer_size == other.fixed.integer_size and
                    self.fixed.fraction_size == other.fixed.fraction_size and
                    self.fixed.alignment == other.fixed.alignment;
            },
            .pointer => {
                return self.pointer.kind == other.pointer.kind and
                    self.pointer.child == other.pointer.child;
            },
            .array => {
                return self.array.child == other.array.child and
                    self.array.size == other.array.size;
            },
            .@"struct" => {
                return false;
            },
            .@"union" => {
                return false;
            },
            .@"enum" => {
                return true;
            },
            .optional => {
                return self.optional.child.isEqual(other.optional.child.*);
            },
            .word => {
                return true;
            },
            else => {
                return true; // void, null, bool, type, comptime_int, comptime_fixed
            },
        }
    }

    pub fn isSmaller(self: Type, other: Type) bool {
        if (meta.activeTag(self) == .any or meta.activeTag(other) == .any) {
            return false; // any type is not smaller than any type
        }
        if (meta.activeTag(self) != meta.activeTag(other)) {
            return self.size() < other.size();
        }
        switch (meta.activeTag(self)) {
            .integer => |i| {
                return i.size < other.integer.size;
            },
            .fixed => |f| {
                return f.integer_size < other.fixed.integer_size;
            },
            .pointer => |p| {
                return p.kind < other.pointer.kind;
            },
            .array => |a| {
                return a.size < other.array.size;
            },
            .@"struct" => |s| {
                return s.size < other.@"struct".size;
            },
            .@"union" => |u| {
                return u.size < other.@"union".size;
            },
            .optional => |o| {
                if (o == .none) {
                    return other.optional != .none;
                }
                return o.some[0] < other.optional.some[0];
            },
            else => {
                return false;
            },
        }
    }

    pub fn promote(self: Type, target: Type) !Type {
        if (self.isEqual(target)) return target;
        const self_tag = meta.activeTag(self);
        const target_tag = meta.activeTag(target);
        // special case for comptime_int and comptime_fixed
        if (self_tag == .comptime_int and target_tag == .comptime_fixed) {
            return target;
        }

        if (self_tag == .comptime_fixed and target_tag == .comptime_int) {
            return target;
        }

        // comptime_int to integer
        if (self_tag == .comptime_int and target_tag == .integer) {
            return target;
        }

        // comptime_fixed to fixed
        if (self_tag == .comptime_fixed and target_tag == .fixed) {
            return target;
        }

        if (self.alignment() != target.alignment()) {
            return Error.AlignmentError;
        }

        if (self_tag == target_tag and self.isSmaller(target)) {
            return target;
        }

        return Error.InvalidConversionError;
    }

    pub fn convert(self: Type, target: Type) !Type {
        if (self.isEqual(target)) return target;
        const self_tag = meta.activeTag(self);
        const target_tag = meta.activeTag(target);
        // special case for comptime_int and comptime_fixed
        if (self_tag == .comptime_int and target_tag == .comptime_fixed) {
            return target;
        }
        if (self_tag == .comptime_fixed and target_tag == .comptime_int) {
            return target;
        }
        if (self.alignment() != target.alignment()) {
            return Error.AlignmentError;
        }
        // integer to integer
        if (self_tag == .integer and target_tag == .integer) {
            if (self.integer.sign == target.integer.sign) {
                return target;
            } else {
                return Error.ConversionSignError;
            }
        }
        // fixed to fixed
        if (self_tag == .fixed and target_tag == .fixed) {
            if (self.fixed.sign == target.fixed.sign) {
                if (self.size() == target.size()) {
                    return target;
                } else {
                    return Error.ConversionSizeError;
                }
            } else {
                return Error.ConversionSignError;
            }
        }

        // pointer to pointer
        if (self_tag == .pointer and target_tag == .pointer) {
            if (self.pointer.kind == target.pointer.kind) {
                return target;
            } else {
                return Error.ConversionPointerKindError;
            }
        }

        // pointer to integer
        if (self_tag == .pointer and target_tag == .integer) {
            return Type{
                .integer = .{
                    .sign = .unsigned,
                    .size = 2, // pointers are always 2 bytes
                    .alignment = 1, // pointers are always 1 byte
                },
            };
        }

        // integer to pointer
        if (self_tag == .integer and target_tag == .pointer) {
            return target;
        }

        // integer to fixed
        if (self_tag == .integer and target_tag == .fixed) {
            if (self.integer.sign == target.fixed.sign) {
                if (self.size() == target.size()) {
                    return target;
                } else {
                    return Error.ConversionSizeError;
                }
            } else {
                return Error.ConversionSignError;
            }
        }

        // fixed to integer
        if (self_tag == .fixed and target_tag == .integer) {
            if (self.fixed.sign == target.integer.sign) {
                if (self.size() == target.size()) {
                    return target;
                } else {
                    return Error.ConversionSizeError;
                }
            } else {
                return Error.ConversionSignError;
            }
        }

        // enum to integer
        if (self_tag == .@"enum" and target_tag == .integer) {
            return Type{
                .integer = .{
                    .sign = .unsigned,
                    .size = 8, // enums are always 1 bytes
                    .alignment = 1, // enums are always 1 byte
                },
            };
        }

        // integer to enum
        if (self_tag == .integer and target_tag == .@"enum") {
            return Type{
                .@"enum" = .{
                    .name = null,
                    .tags = null,
                },
            };
        }

        return Error.InvalidConversionError;
    }

    pub fn cast(self: Type, target: Type) !Type {
        if (self.isEqual(target)) return target;
        const self_tag = meta.activeTag(self);
        const target_tag = meta.activeTag(target);

        // special case for comptime_int and comptime_fixed
        if (self_tag == .comptime_int and target_tag == .comptime_fixed) {
            return target;
        }
        if (self_tag == .comptime_fixed and target_tag == .comptime_int) {
            return target;
        }
        // comptime_int to integer
        if (self_tag == .comptime_int and target_tag == .integer) {
            return target;
        }
        // comptime_fixed to fixed
        if (self_tag == .comptime_fixed and target_tag == .fixed) {
            return target;
        }

        if (self.alignment() != target.alignment()) {
            return Error.AlignmentError;
        }
        // integer to integer
        if (self_tag == .integer and target_tag == .integer) {
            return target;
        }
        // fixed to fixed
        if (self_tag == .fixed and target_tag == .fixed) {
            return target;
        }

        return Error.InvalidCastError;
    }

    pub fn alignCast(self: Type, ali: Alignment) !Type {
        if (self.alignment() == ali) return self;
        const tag = meta.activeTag(self);
        switch (tag) {
            .integer => |i| {
                return Type{
                    .integer = .{
                        .sign = i.sign,
                        .size = i.size,
                        .alignment = ali,
                    },
                };
            },
            .fixed => |f| {
                return Type{
                    .fixed = .{
                        .sign = f.sign,
                        .integer_size = f.integer_size,
                        .fraction_size = f.fraction_size,
                        .alignment = ali,
                    },
                };
            },
        }

        return Error.AlignmentError;
    }

    pub fn canMath(self: Type, target: Type) bool {
        const self_tag = meta.activeTag(self);
        const target_tag = meta.activeTag(target);
        // special cases for comptime_int and comptime_fixed
        if (self_tag == .comptime_int and target_tag == .comptime_fixed) {
            return true;
        }
        if (self_tag == .comptime_fixed and target_tag == .comptime_int) {
            return true;
        }
        // comptime_int to integer
        if (self_tag == .comptime_int and target_tag == .integer) {
            return true;
        }
        // integer to comptime_int
        if (self_tag == .integer and target_tag == .comptime_int) {
            return true;
        }
        // comptime_fixed to fixed
        if (self_tag == .comptime_fixed and target_tag == .fixed) {
            return true;
        }
        // fixed to comptime_fixed
        if (self_tag == .fixed and target_tag == .comptime_fixed) {
            return true;
        }
        //comptime_int to pointer
        if (self_tag == .comptime_int and target_tag == .pointer) {
            return target.pointer.kind == .many;
        }
        // pointer to comptime_int
        if (self_tag == .pointer and target_tag == .comptime_int) {
            return self.pointer.kind == .many;
        }

        if (self.alignment() != target.alignment()) {
            return false;
        }

        // integer to integer
        if (self_tag == .integer and self.isEqual(target)) {
            return true;
        }
        // fixed to fixed
        if (self_tag == .fixed and self.isEqual(target)) {
            return true;
        }
        // pointer to integer
        if (self_tag == .pointer and target_tag == .integer and self.pointer.kind == .many) {
            return true;
        }
        // integer to pointer
        if (self_tag == .integer and target_tag == .pointer and target.pointer.kind == .many) {
            return true;
        }
        return false;
    }

    pub fn canShift(self: Type, target: Type) bool {
        const self_tag = meta.activeTag(self);
        const target_tag = meta.activeTag(target);

        // special cases for comptime_int
        if (self_tag == .comptime_int and target_tag == .comptime_int) {
            return true;
        }
        if (self_tag == .comptime_int and target_tag == .integer) {
            return true;
        }
        if (self_tag == .integer and target_tag == .comptime_int) {
            return true;
        }
        // special cases for comptime_int and pointer
        if (self_tag == .comptime_int and target_tag == .pointer) {
            return target.pointer.kind == .many;
        }
        if (self_tag == .pointer and target_tag == .comptime_int) {
            return self.pointer.kind == .many;
        }

        if (self.alignment() != target.alignment()) {
            return false;
        }
        // integer to integer
        if (self_tag == .integer and target_tag == .integer) {
            if (target.integer.size == @log2(self.integer.size)) {
                return true;
            }
            return false;
        }
        // pointer to integer
        if (self_tag == .pointer and target_tag == .integer and self.pointer.kind == .many) {
            if (target.integer.size == @log2(16)) {
                return true;
            }
            return false;
        }
        // integer to pointer
        if (self_tag == .integer and target_tag == .pointer and target.pointer.kind == .many) {
            if (self.integer.size == @log2(16)) {
                return true;
            }
            return false;
        }
        return false;
    }

    pub fn canLogic(self: Type, target: Type) bool {
        const self_tag = meta.activeTag(self);
        const target_tag = meta.activeTag(target);
        // special cases for comptime_int
        if (self_tag == .comptime_int and target_tag == .comptime_int) {
            return true;
        }
        if (self_tag == .comptime_int and target_tag == .integer) {
            return true;
        }
        if (self_tag == .integer and target_tag == .comptime_int) {
            return true;
        }
        if (self.alignment() != target.alignment()) {
            return false;
        }
        // integer to integer
        if (self_tag == .integer and target_tag == .integer) {
            if (self.integer.size == target.integer.size) {
                return true;
            }
            return false;
        }
        return false;
    }

    pub fn canCompare(self: Type, target: Type) bool {
        const self_tag = meta.activeTag(self);
        const target_tag = meta.activeTag(target);
        // special cases for comptime_int
        if (self_tag == .comptime_int and target_tag == .comptime_int) {
            return true;
        }
        if (self_tag == .comptime_int and target_tag == .integer) {
            return true;
        }
        if (self_tag == .integer and target_tag == .comptime_int) {
            return true;
        }
        // special cases for comptime_fixed
        if (self_tag == .comptime_fixed and target_tag == .comptime_fixed) {
            return true;
        }
        if (self_tag == .comptime_fixed and target_tag == .fixed) {
            return true;
        }
        if (self_tag == .fixed and target_tag == .comptime_fixed) {
            return true;
        }
        // special cases for comptime_int and pointer
        if (self_tag == .comptime_int and target_tag == .pointer) {
            return target.pointer.kind == .many;
        }
        if (self_tag == .pointer and target_tag == .comptime_int) {
            return self.pointer.kind == .many;
        }

        if (self.alignment() != target.alignment()) {
            return false;
        }
        // integer to integer
        if (self_tag == .integer and target_tag == .integer) {
            return true;
        }
        // fixed to fixed
        if (self_tag == .fixed and target_tag == .fixed) {
            return true;
        }

        // pointer to pointer
        if (self_tag == .pointer and target_tag == .pointer) {
            return true;
        }
        // pointer to integer
        if (self_tag == .pointer and target_tag == .integer and self.pointer.kind == .many) {
            return true;
        }
        // integer to pointer
        if (self_tag == .integer and target_tag == .pointer and target.pointer.kind == .many) {
            return true;
        }

        return false;
    }

    pub fn toString(self: Type, allocator: Allocator) ![]const u8 {
        _ = self;
        _ = allocator;
        return "Type".*; // placeholder, should return a string representation of the type
    }

    pub fn fromString(
        token: []const u8,
        allocator: Allocator,
    ) ?Type {
        _ = token;
        _ = allocator;
        return null; // placeholder, should parse a string representation of the type
    }
};

// the following types are used because they have no configuration
const std = @import("std");
const Allocator = std.mem.Allocator;
const meta = std.meta;
const ArrayList = std.ArrayList;
