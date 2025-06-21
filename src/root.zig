// include and re export all modules
pub const opcode = @import("core/opcode.zig");
pub const stack = @import("core/stack.zig");
pub const CPU = @import("core/cpu.zig");
pub const Memory = @import("core/memory.zig");
pub const hardware = @import("core/hardware.zig");
pub const Instruction = opcode.Instruction;
pub const parser = @import("parser/parser.zig");
pub const char_parser = @import("parser/char_parser.zig");
pub const effectParser = @import("asm/type_vm/effectParser.zig");

const std = @import("std");
const testing = std.testing;
test {
    testing.refAllDecls(effectParser);
}
