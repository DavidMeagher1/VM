// just a reminder of how bits work
// 8  , 7 , 6 , 5 , 4, 3, 2, 1
// 128, 64, 32, 16, 8, 4, 2, 1

pub const TypeIndex = u32;
pub const TypeList = ArrayList(Type);

pub const FieldInfo = struct {
    name: []const u8,
    type_index: TypeIndex,
};

pub const UnionFieldInfo = struct {
    name: []const u8,
    type_index: TypeIndex,
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
    type: struct { // acts as an alias for a type
        name: []const u8, // a reference to a type name owned by the registry
        index: TypeIndex,
    },
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
        name: ?[]const u8, // a reference to a struct name owned by the registry
        fields: []const FieldInfo,
        size: u32, // this size is the sum of the sizes of the fields
    },
    @"union": struct {
        name: ?[]const u8, // a reference to a union name owned by the registry
        fields: []const UnionFieldInfo,
        size: u32, // this size is the sum of the sizes of the fields
    },
    @"enum": struct {
        name: ?[]const u8, // a reference to an enum name owned by the registry
        tags: []EnumFieldInfo, // the values of the enum max of 255
    },
    optional: union(enum) {
        child: TypeIndex,
    },

    pub fn size(self: Type, reg: *Registry) !u32 {
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
                const child = try reg.get_type_by_index(self.array.child);
                const child_size = try child.size(reg);
                return self.array.size * child_size;
            },
            .@"struct" => {
                var s: u32 = 0;
                for (self.@"struct".fields) |field| {
                    const field_type = try reg.get_type_by_index(field.type_index);
                    const field_size = try field_type.size(reg);
                    s += field_size;
                }
                return s;
            },
            .@"union" => {
                var s: u32 = 0;
                for (self.@"union".fields) |field| {
                    const field_type = try reg.get_type_by_index(field.type_index);
                    const field_size = try field_type.size(reg);
                    s += field_size;
                }
                return s;
            },
            .@"enum" => {
                return 1; // enums are always 1 byte
            },
            .optional => {
                const child = try reg.get_type_by_index(self.optional.child);
                return child.size(reg);
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
            .@"enum" => {
                return true;
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

    pub fn toString(self: Type, reg: *Registry, allocator: Allocator) ![]const u8 {
        const tag = meta.activeTag(self);
        switch (tag) {
            .any => {
                const str = "any";
                const result = try allocator.alloc(u8, str.len);
                @memcpy(result, str);
                return result;
            },
            .void => {
                const str = "void";
                const result = try allocator.alloc(u8, str.len);
                @memcpy(result, str);
                return result;
            },
            .null => {
                const str = "null";
                const result = try allocator.alloc(u8, str.len);
                @memcpy(result, str);
                return result;
            },
            .bool => {
                const str = "bool";
                const result = try allocator.alloc(u8, str.len);
                @memcpy(result, str);
                return result;
            },
            .type => {
                const str = self.type.name;
                const result = try allocator.alloc(u8, 4);
                @memcpy(result, str);
                return result;
            },
            .comptime_int => {
                const str = "comptime_int";
                const result = try allocator.alloc(u8, str.len);
                @memcpy(result, str);
                return result;
            },
            .comptime_fixed => {
                const str = "comptime_fixed";
                const result = try allocator.alloc(u8, str.len);
                @memcpy(result, str);
                return result;
            },
            .integer => {
                const sign = if (self.integer.sign == Sign.signed) "i" else "u";
                const result = try std.fmt.allocPrint(allocator, "{s}{x}", .{ sign, self.integer.size });
                return result;
            },
            .fixed => {
                const sign = if (self.fixed.sign == Sign.signed) "i" else "u";
                const result = std.fmt.allocPrint(allocator, "{s}f{x}.{x}", .{ sign, self.fixed.integer_size, self.fixed.fraction_size });
                return result;
            },
            .pointer => {
                const kind = if (self.pointer.kind == PtrKind.one) "*" else "[*]";
                const child: Type = reg.get_type_by_index(self.pointer.child) catch return Error.InvalidTypeError;
                const child_str = try child.toString(reg, allocator);
                defer allocator.free(child_str);
                const result = try std.fmt.allocPrint(allocator, "{s}{s}", .{ kind, child_str });
                return result;
            },
            .array => {
                const child = reg.get_type_by_index(self.array.child) catch return Error.InvalidTypeError;
                const child_str = try child.toString(reg, allocator);
                defer allocator.free(child_str);
                const result = try std.fmt.allocPrint(allocator, "[{x}]{s}", .{ self.array.size, child_str });
                return result;
            },
            .@"struct" => {
                const str = self.@"struct".name orelse "struct"; // TODO: add generation for anonymous struct names
                const result = try allocator.alloc(u8, str.len);
                @memcpy(result, str);
                return result;
            },
            .@"union" => {
                const str = self.@"union".name orelse "union"; // TODO: add generation for anonymous union names
                const result = try allocator.alloc(u8, str.len);
                @memcpy(result, str);
                return result;
            },
            .@"enum" => {
                const str = self.@"enum".name orelse "enum"; // TODO: add generation for anonymous enum names
                const result = try allocator.alloc(u8, str.len);
                @memcpy(result, str);
                return result;
            },
            .optional => {
                const index = try reg.get_type_by_index(self.optional.child);
                const child_str = try index.toString(reg, allocator);
                defer allocator.free(child_str);
                const result = try std.fmt.allocPrint(allocator, "?{s}", .{child_str});
                return result;
            },
        }
    }

    pub fn fromString(
        token: []const u8,
        reg: *Registry, // may need to register the type eg i8 i7 and so on
        allocator: Allocator,
    ) ?Type {
        // check for empty string
        if (token.len == 0) {
            return null;
        }
        // trim whitespace
        const trimmed = std.mem.trim(u8, token, " \t\n\r");
        // check if token is a pointer
        var processed: u32 = 0;
        switch (trimmed[0]) {
            '[' => {
                // might be an array or a pointer to many
                // get the index of the next ']'
                const end = std.mem.indexOf(u8, trimmed, "]") orelse return null;
                const inner_token = std.mem.trim(u8, trimmed[1..end], " \t\n\r");
                const arr_size: ?u32 = std.fmt.parseUnsigned(u32, inner_token, 16) catch null;
                if (arr_size) |s| {
                    processed += @intCast(end + 1);
                    const child_type: Type = Type.fromString(trimmed[processed..], reg, allocator) orelse return null;
                    const name = child_type.toString(reg, allocator) catch return null;
                    defer allocator.free(name);
                    const index = reg.get_type_index(name) catch return null;
                    const t = Type{
                        .array = .{
                            .child = index,
                            .size = s,
                        },
                    };
                    return t;
                } else {
                    if (inner_token[0] == '*') {
                        // this is a pointer to many
                        processed += @intCast(end + 1);
                        const child_type = Type.fromString(trimmed[processed..], reg, allocator) orelse {
                            return null;
                        };
                        const name = child_type.toString(reg, allocator) catch {
                            return null;
                        };
                        defer allocator.free(name);
                        const index = reg.get_type_index(name) catch return null;
                        const t = Type{
                            .pointer = .{
                                .kind = PtrKind.many,
                                .child = index,
                            },
                        };
                        return t;
                    }
                    return null;
                }
            },
            '*' => {
                // this is a pointer to one
                processed += 1;
                const child_type: Type = Type.fromString(trimmed[processed..], reg, allocator) orelse return null;
                const name = child_type.toString(reg, allocator) catch return null;
                defer allocator.free(name);
                const index = reg.get_type_index(name) catch return null;
                const t = Type{
                    .pointer = .{
                        .kind = PtrKind.one,
                        .child = index,
                    },
                };
                return t;
            },
            'i' => {
                processed += 1;
                if (trimmed[processed] == 'f') {
                    // signed fixed point
                    processed += 1;
                    const integer_size: ?u5 = std.fmt.parseUnsigned(u5, trimmed[processed..], 16) catch null;
                    if (integer_size) |i| {
                        processed += 1;
                        const fraction_size: ?u5 = std.fmt.parseUnsigned(u5, trimmed[processed..], 16) catch null;
                        if (fraction_size) |f| {
                            const t = Type{
                                .fixed = .{
                                    .sign = Sign.signed,
                                    .integer_size = i,
                                    .fraction_size = f,
                                    .alignment = Alignment.nearestAlignment(i + f),
                                },
                            };
                            //check if type is already registered
                            const name = t.toString(reg, allocator) catch return null;
                            defer allocator.free(name);
                            _ = reg.get_type_index(name) catch {
                                // register the type
                                _ = reg.register_type(t, name) catch return null;
                            };
                            return t;
                        }
                    }
                } else {
                    // signed integer
                    const data_size: ?u6 = std.fmt.parseUnsigned(u6, trimmed[processed..], 16) catch null;
                    if (data_size) |s| {
                        const t = Type{
                            .integer = .{
                                .sign = Sign.signed,
                                .size = s,
                                .alignment = Alignment.nearestAlignment(s),
                            },
                        };
                        //check if type is already registered
                        const name = t.toString(reg, allocator) catch return null;
                        defer allocator.free(name);
                        _ = reg.get_type_index(name) catch {
                            // register the type
                            _ = reg.register_type(t, name) catch return null;
                        };
                        return t;
                    }
                }
            },
            'u' => {
                processed += 1;
                if (trimmed[processed] == 'f') {
                    // unsigned fixed point
                    processed += 1;
                    const integer_size: ?u5 = std.fmt.parseUnsigned(u5, trimmed[processed..], 16) catch null;
                    if (integer_size) |i| {
                        processed += 1;
                        const fraction_size: ?u5 = std.fmt.parseUnsigned(u5, trimmed[processed..], 16) catch null;
                        if (fraction_size) |f| {
                            const t = Type{
                                .fixed = .{
                                    .sign = Sign.unsigned,
                                    .integer_size = i,
                                    .fraction_size = f,
                                    .alignment = Alignment.nearestAlignment(i + f),
                                },
                            };
                            //check if type is already registered
                            const name = t.toString(reg, allocator) catch return null;
                            defer allocator.free(name);
                            _ = reg.get_type_index(name) catch {
                                // register the type
                                _ = reg.register_type(t, name) catch return null;
                            };
                            return t;
                        }
                    }
                } else {
                    // unsigned integer
                    const data_size: ?u6 = std.fmt.parseUnsigned(u6, trimmed[processed..], 16) catch null;
                    if (data_size) |s| {
                        const t = Type{
                            .integer = .{
                                .sign = Sign.unsigned,
                                .size = s,
                                .alignment = Alignment.nearestAlignment(s),
                            },
                        };
                        //check if type is already registered
                        const name = t.toString(reg, allocator) catch return null;
                        defer allocator.free(name);
                        _ = reg.get_type_index(name) catch {
                            // register the type
                            _ = reg.register_type(t, name) catch return null;
                        };
                        return t;
                    }
                }
            },
            '?' => {
                // optional type
                processed += 1;
                const inner_token = std.mem.trim(u8, trimmed[processed..], " \t\n\r");
                const inner_type: Type = Type.fromString(inner_token, reg, allocator) orelse {
                    return null;
                };
                const name = inner_type.toString(reg, allocator) catch return null;
                const index = reg.get_type_index(name) catch return null;
                return Type{
                    .optional = .{
                        .child = index,
                    },
                };
            },
            else => {
                // this is for named types
                const t = reg.get_type(trimmed) catch return null;
                return t;
            },
        }
        return null;
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
const std = @import("std");
const Allocator = std.mem.Allocator;
const meta = std.meta;
const ArrayList = std.ArrayList;
const Registry = @import("registry.zig");
