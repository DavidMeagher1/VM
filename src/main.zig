const std = @import("std");
const core = @import("core");
const CPU = core.CPU;
const Instruction = core.opcode.Instruction;
const hardware = core.hardware;
const Hardware = hardware.Hardware;

const Test = struct {
    const Error = error{
        TestError,
    };
    pub fn update(self: *Test, memory: *core.Memory.MemoryFrame) !void {
        _ = self;
        // print memory
        if (memory.data.len == 0) {
            return error.TestError;
        }
        if (memory.data[0x00] == 0xAF) {
            std.debug.print("got a signal\n----------------------\n", .{});
            // set the memory to 0
            memory.data[0] = 0;
        }
    }
};

const TestHardware = Hardware(
    Test,
    Test.Error,
    Test.update,
);

pub fn main() !void {
    const GPA = std.heap.GeneralPurposeAllocator(.{});
    var gpa = GPA.init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var h = try TestHardware.init(Test{});
    var cpu = try CPU.init(.{}, allocator);
    defer cpu.deinit();

    const code = [_]u8{
        // push 0xAF
        (Instruction{
            .extension = 0,
            .width = 0,
            .stack = 0,
            .baseOpcode = core.opcode.StandardOpcode.push,
        }).toByte(),
        0xAF, // push 0xAF
        // push address 0x00,0x10
        (Instruction{
            .extension = 0,
            .width = 0,
            .stack = 0,
            .baseOpcode = core.opcode.StandardOpcode.push,
        }).toByte(),
        0x20, // push 0x00
        (Instruction{
            .extension = 0,
            .width = 0,
            .stack = 0,
            .baseOpcode = core.opcode.StandardOpcode.push,
        }).toByte(),
        0x00, // push 0x10
        //push 1
        (Instruction{
            .extension = 0,
            .width = 0,
            .stack = 0,
            .baseOpcode = core.opcode.StandardOpcode.push,
        }).toByte(),
        0x01, // push 1
        //store
        (Instruction{
            .extension = 0,
            .width = 0,
            .stack = 0,
            .baseOpcode = core.opcode.StandardOpcode.store,
        }).toByte(),
        // push 0x00
        (Instruction{
            .extension = 0,
            .width = 0,
            .stack = 0,
            .baseOpcode = core.opcode.StandardOpcode.push,
        }).toByte(),
        0x01, // push 0x00
        // halt
        (Instruction{
            .extension = 0,
            .width = 0,
            .stack = 0,
            .baseOpcode = core.opcode.StandardOpcode.halt,
        }).toByte(),
    };
    // describe the code
    // push 0xAF
    // push 0x00
    // push 0x10
    // push 1
    // store

    _ = try cpu.memory.write(0, &code);
    cpu.registers.pc = 0;

    h.memory = try cpu.memory.getFrame(0x20, 0xA);
    var result: u8 = 0;
    while (result == 0) {
        result = try cpu.execute();
        try h.update();
    }
    // print cpu memory as string
    std.debug.print("CPU Memory: {any}", .{cpu.memory.data[0..0x20]});
}

// create a test function to test the CPU
test "CPU Test" {
    const GPA = std.heap.GeneralPurposeAllocator(.{});
    var gpa = GPA.init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = try CPU.init(.{}, allocator);
    defer vm.deinit();

    // Example usage of the CPU
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
    _ = try vm.memory.write(0, &code);
    vm.registers.pc = 0;
    var result: u8 = 0;
    while (result == 0) {
        result = try vm.execute();
    }
    try std.testing.expectEqual(result, 8);
}
