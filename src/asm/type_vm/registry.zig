// this is a type registry for the VM

pub const TypeMap = StringHashMap(TypeIndex);

pub const Error = error{
    TypeAlreadyRegistered,
    TypeNotFound,
};

pub const void_index: TypeIndex = 0;
pub const pointer_void_index: TypeIndex = 1;
pub const many_pointer_void_index: TypeIndex = 2;
pub const any_index: TypeIndex = 3;
pub const pointer_any_index: TypeIndex = 4;
pub const many_pointer_any_index: TypeIndex = 5;
pub const bool_index: TypeIndex = 6;
pub const null_index: TypeIndex = 7;
pub const undefined_index: TypeIndex = 8;
pub const comptime_int_index: TypeIndex = 10;
pub const comptime_fixed_index: TypeIndex = 11;
pub const u8_index: TypeIndex = 12;

registered_types: TypeList,
registered_types_map: TypeMap,
allocator: Allocator,

pub fn init(allocator: Allocator) !Registry {
    var result = Registry{
        .registered_types = TypeList.init(allocator),
        .registered_types_map = TypeMap.init(allocator),
        .allocator = allocator,
    };
    result.registerBaseTypes() catch {
        result.deinit();
        return error.OutOfMemory;
    };
    return result;
}

pub fn registerBaseTypes(self: *Registry) !void {
    // register base types
    _ = try self.register_type(Type{ .void = undefined }, "void");
    _ = try self.register_type(Type{ .pointer = .{
        .kind = .one,
        .child = void_index,
    } }, "*void");
    _ = try self.register_type(Type{ .pointer = .{
        .kind = .many,
        .child = void_index,
    } }, "[*]void");
    _ = try self.register_type(Type{ .any = undefined }, "any");
    _ = try self.register_type(Type{ .pointer = .{
        .kind = .one,
        .child = any_index,
    } }, "*any");
    _ = try self.register_type(Type{ .pointer = .{
        .kind = .many,
        .child = any_index,
    } }, "[*]any");
    _ = try self.register_type(Type{ .bool = undefined }, "bool");
    _ = try self.register_type(Type{ .null = undefined }, "null");
    _ = try self.register_type(Type{ .undefined = undefined }, "undefined");
    _ = try self.register_type(Type{ .comptime_int = undefined }, "comptime_int");
    _ = try self.register_type(Type{ .comptime_fixed = undefined }, "comptime_fixed");
    _ = try self.register_type(Type{ .integer = .{
        .sign = .unsigned,
        .size = 8,
        .alignment = .one,
    } }, "u8");
    return;
}

pub fn deinit(self: *Registry) void {
    self.registered_types.deinit();
    self.registered_types_map.deinit();
}

pub fn register_type(self: *Registry, type_: Type, name: []const u8) !TypeIndex {
    // take ownership of name
    const owned_name = try self.allocator.dupe(u8, name);
    const index: u32 = @intCast(self.registered_types.items.len);
    _ = self.get_type(owned_name) catch {
        try self.registered_types_map.put(owned_name, index);
        try self.registered_types.append(type_);
        return @intCast(index);
    };
    return Error.TypeAlreadyRegistered;
}

pub fn get_type_index(self: *Registry, name: []const u8) !TypeIndex {
    const index = self.registered_types_map.get(name) orelse return Error.TypeNotFound;
    return @intCast(index);
}

pub fn get_type(self: *Registry, name: []const u8) !Type {
    const index = try self.get_type_index(name);
    return self.registered_types.items[index];
}

pub fn get_type_by_index(self: *Registry, index: TypeIndex) !Type {
    if (index >= self.registered_types.items.len) {
        return Error.TypeNotFound;
    }
    return self.registered_types.items[index];
}

pub fn get_type_and_index(self: *Registry, name: []const u8) !struct { TypeIndex, Type } {
    const index = try self.get_type_index(name);
    const type_ = self.registered_types.items[index];
    return .{
        index,
        type_,
    };
}

const std = @import("std");
const StringHashMap = std.StringHashMap;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
pub const TypeIndex = types.TypeIndex;
pub const Type = types.Type;
pub const TypeList = types.TypeList;
const Registry = @This();
