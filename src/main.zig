const std = @import("std");
const core = @import("core");
const VM = core.VM;
const Instruction = core.opcode.Instruction;
pub fn main() !void {
    const GPA = std.heap.GeneralPurposeAllocator(.{});
    var gpa = GPA.init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = try VM.init(.{}, allocator);
    defer vm.deinit();

    // Example usage of the VM
    // first a list of bytecodes
    const code = [_]u8{
        (Instruction{
            .extension = 0,
            .width = 0,
            .stack = 0,
            .baseOpcode = core.opcode.StandardOpcode.push,
        }).toByte(),
        0x05, // push 5,
        (Instruction{
            .extension = 0,
            .width = 0,
            .stack = 0,
            .baseOpcode = core.opcode.StandardOpcode.push,
        }).toByte(),
        0x03, // push 3,
        (Instruction{
            .extension = 0,
            .width = 0,
            .stack = 0,
            .baseOpcode = core.opcode.StandardOpcode.add,
        }).toByte(), // add 5 and 3,
        (Instruction{
            .extension = 0,
            .width = 0,
            .stack = 0,
            .baseOpcode = core.opcode.StandardOpcode.halt,
        }).toByte(),
    }; // add 5 and 3 then halt exit code should be 8
    // load the bytecode into the VM
    _ = try vm.memory.write(0, &code);
    // run the VM
    const result = try vm.run(0);
    std.debug.print("Result: {}\n", .{result});
}
