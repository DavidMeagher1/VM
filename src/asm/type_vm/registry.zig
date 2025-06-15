// this is a type registry for the VM

pub const TypeMap = StringHashMap(TypeIndex);

pub const Error = error{
    TypeAlreadyRegistered,
    TypeNotFound,
};

registered_types: TypeList,
registered_types_map: TypeMap,

pub fn init(allocator: Allocator) !Registry {
    return Registry{
        .registered_types = TypeList.init(allocator),
        .registered_types_map = TypeMap.init(allocator),
    };
}

pub fn deinit(self: *Registry) void {
    self.registered_types.deinit();
    self.registered_types_map.deinit();
}

pub fn register_type(self: *Registry, type_: Type, name: []const u8) !TypeIndex {
    const index: u32 = @intCast(self.registered_types.items.len);
    _ = self.get_type(name) catch {
        try self.registered_types_map.put(name, index);
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

const std = @import("std");
const StringHashMap = std.StringHashMap;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
pub const TypeIndex = types.TypeIndex;
pub const Type = types.Type;
pub const TypeList = types.TypeList;
const Registry = @This();
