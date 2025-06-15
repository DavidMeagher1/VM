// just a reminder of how bits work
// 8  , 7 , 6 , 5 , 4, 3, 2, 1
// 128, 64, 32, 16, 8, 4, 2, 1

pub const TypeIndex = u32;
const TypeList = ArrayList(Type);

pub const FieldInfo = struct {
    name: []const u8,
    type_index: TypeIndex,
};

pub const UnionFieldInfo = struct {
    name: []const u8,
    type_index: TypeIndex,
};

pub const Sign = enum {
    signed,
    unsigned,
};

pub const PtrKind = enum {
    one,
    many,
};

pub const Alignment = enum {
    one,
    two,
    four,
};

pub const Error = error{
    InvalidConversionError,
    InvalidCastError,
    ConversionSignError,
    ConversionSizeError,
    ConversionPointerKindError,
    AlignmentError,
};

pub const Type = union(enum) {
    void: void,
    null: void,
    bool: void,
    type: TypeIndex,
    comptime_int: void,
    comptime_fixed: void,
    integer: struct {
        sign: Sign,
        size: u5, // the max number is 31 so the actual size is size + 1
        alignment: Alignment, // 0 = 1 byte, 1 = 2 bytes, 2 = 4 bytes
    },
    fixed: struct {
        sign: Sign,
        integer_size: u4, // the max number is 15 so the actual size is size + 1
        fraction_size: u4, // the max number is 15 so the actual size is size + 1
        alignment: Alignment, // 0 = 1 byte, 1 = 2 bytes, 2 = 4 bytes

        pub fn getScalingFactor(self: Type) u32 {
            return 1 << self.fraction_size;
        }
    },

    pointer: struct {
        kind: PtrKind, // one or many
        child: TypeIndex,

        pub fn getChild(self: Pointer, registry: Registry) !TypeIndex {
            return try registry.get_type_by_index(self.child);
        }
    },
    array: struct {
        child: TypeIndex,
        size: u32, // the max number is 2^32 - 1
        // arrays alignment is always 1 byte
    },
    @"struct": struct {
        fields: []const FieldInfo,
        size: u32, // this size is the sum of the sizes of the fields
    },
    @"union": struct {
        fields: []const UnionFieldInfo,
        size: u32, // this size is the sum of the sizes of the fields
    },
    optional: union(enum) {
        null: void,
        some: struct { TypeIndex, u32 },

        pub fn unwrap(self: *Type, registry: Registry) !Type {
            if (self.optional == .null) {
                return Type{ .null = {} };
            }
            return registry.get_type_by_index(self.optional.some[0]);
        }
    },

    pub fn size(self: *Type) u32 {
        switch (meta.activeTag(self)) {
            .void => {
                return 0;
            },
            .null => {
                return 0;
            },
            .bool => {
                return 1;
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
            .integer => |i| {
                return i.size + 1 / 8;
            },
            .fixed => |f| {
                return (f.integer_size + f.fraction_size + 1) / 8;
            },
            .pointer => {
                return 2; // pointers are always 2 bytes
            },
            .array => |a| {
                return a.size * a.child.size();
            },
            .@"struct" => |s| {
                return s.size;
            },
            .@"union" => |u| {
                return u.size;
            },
            .optional => |o| {
                if (o == .none) {
                    return 0;
                }
                return o.some[1];
            },
        }
    }

    pub fn alignment(self: *Type) u32 {
        switch (meta.activeTag(self)) {
            .void => {
                return 0;
            },
            .null => {
                return 0;
            },
            .bool => {
                return 1;
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
            .integer => |i| {
                return i.alignment;
            },
            .fixed => |f| {
                return f.alignment;
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
            .optional => |o| {
                if (o == .none) {
                    return 0;
                }
                return o.some[1];
            },
        }
    }

    pub fn isEqual(self: Type, other: Type) bool {
        if (meta.activeTag(self) != meta.activeTag(other)) {
            return false;
        }
        switch (meta.activeTag(self)) {
            .integer => |i| {
                return i.sign == other.integer.sign and
                    i.size == other.integer.size and
                    i.alignment == other.integer.alignment;
            },
            .fixed => |f| {
                return f.sign == other.fixed.sign and
                    f.integer_size == other.fixed.integer_size and
                    f.fraction_size == other.fixed.fraction_size and
                    f.alignment == other.fixed.alignment;
            },
            .pointer => |p| {
                return p.kind == other.pointer.kind and
                    p.child == other.pointer.child;
            },
            .array => |a| {
                return a.child == other.array.child and
                    a.size == other.array.size;
            },
            .@"struct" => |s| {
                return s.size == other.@"struct".size;
            },
            .@"union" => |u| {
                return u.size == other.@"union".size;
            },
            .optional => |o| {
                if (o == .none) {
                    return true;
                }
                return o.some[0] == other.optional.some[0];
            },
        }
    }

    pub fn isSmaller(self: Type, other: Type) bool {
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
        }
    }

    pub fn promote(self: Type, target: Type) !Type {
        if (self.isEqual(target)) return self;
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
        if (self.isEqual(target)) return self;
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

        return Error.InvalidConversionError;
    }

    pub fn cast(self: Type, target: Type) !Type {
        if (self.isEqual(target)) return self;
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
};

pub fn Struct(field_info: []const FieldInfo, registry: Registry) !Type {
    var true_size: u32 = 0;
    for (field_info) |field| {
        const field_size = try registry.get_type_by_index(field.type_index).size();
        true_size += field_size;
    }
    return Type{
        .@"struct"{
            .fields = field_info,
            .size = true_size,
        },
    };
}

pub fn Union(field_info: []const UnionFieldInfo, registry: Registry) !Type {
    var true_size: u32 = 0;
    for (field_info) |field| {
        const field_size = try registry.get_type_by_index(field.type_index).size();
        true_size += field_size;
    }
    return Type{
        .@"union"{
            .fields = field_info,
            .size = true_size,
        },
    };
}

pub fn Optional(type_index: TypeIndex, registry: Registry) !Type {
    const type_ = try registry.get_type_by_index(type_index);
    return Type{
        .optional = .{
            .none = {},
            .some = .{ type_index, type_.size() },
        },
    };
}

pub fn Pointer(kind: u1, type_index: TypeIndex) Type {
    return Type{
        .pointer = Pointer{
            .kind = kind,
            .child = type_index,
        },
    };
}

// the following types are used because they have no configuration
pub const t_void = Type{ .void = {} };
pub const t_null = Type{ .null = {} };
pub const t_bool = Type{ .bool = {} };
pub const t_type = Type{ .type = {} };
pub const t_comptime_int = Type{ .comptime_int = {} };
pub const t_comptime_fixed = Type{ .comptime_fixed = {} };

const std = @import("std");
const meta = std.meta;
const ArrayList = std.ArrayList;
const Registry = @import("registry.zig");
