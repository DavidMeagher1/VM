# Virtual Machine Architecture Specification

## Overview
This is a stack-based virtual machine with a custom bytecode instruction set. The VM has:
- Two stacks: a data stack (working stack) and a return stack
- 16-bit addressable memory (65,536 bytes maximum)
- Support for 8-bit and 16-bit operations
- Fixed-point arithmetic support
- Basic register set including program counter (PC) and status register
- Support for subroutines and interrupts

## Instruction Format
Each instruction is encoded in 1 or 2 bytes with the following bit layout:
```
Single byte:  E W S O O O O O
Two bytes:    E W S O O O O O - O O O O O O O O

E = Extension bit (0 for single byte, 1 for two bytes)
W = Width bit (typically 0 for 8-bit, 1 for 16-bit operations)
S = Stack select bit (0 for working stack, 1 for return stack)
O = Opcode bits
```

## Instruction Set

### Special Operations (Opcode 0)
- `illegal`: Halts the VM (used for detecting uninitialized memory)
- `noop`: No operation
- `ret`: Return from subroutine
- `rti`: Return from interrupt

### Stack Operations
- `push`: Push immediate value onto selected stack
- `pop`: Pop value from selected stack
- `dup`: Duplicate top value of selected stack
- `swap`: Swap top two values of selected stack
- `over`: Duplicate second value on selected stack
- `push_reg`: Push register value onto selected stack
- `pop_reg`: Pop value from selected stack into register
- `load`: Load n values from memory into selected stack
- `store`: Store n values from selected stack into memory
- `flip`: Move value between working and return stack

### Arithmetic Operations
Basic integer operations:
- `add`: Add top two values
- `sub`: Subtract top two values
- `mul`: Multiply top two values
- `div`: Divide top two values

Fixed-point operations:
- `fx_add`: Fixed-point addition
- `fx_sub`: Fixed-point subtraction
- `fx_mul`: Fixed-point multiplication
- `fx_div`: Fixed-point division

### Bitwise Operations
- `and`: Bitwise AND
- `or`: Bitwise OR
- `xor`: Bitwise XOR
- `not`: Bitwise NOT
- `shl`: Shift left
- `shr`: Shift right

### Control Flow Operations
- `cmp`: Compare top two values with multiple comparison types:
  - Equal
  - NotEqual
  - LessThan
  - GreaterThan
  - LessThanOrEqual
  - GreaterThanOrEqual
- `jmp`: Jump to address (absolute or relative)
- `jnz`: Conditional jump if top value is not zero
- `call`: Subroutine call with options:
  - Direct/Indirect addressing (W bit)
  - Local/Foreign function (S bit)

### System Operations
- `trap`: System call to host system
- `halt`: Exit VM with status code
- `int`: Software interrupt

## Memory Model
- 16-bit address space (0-65535)
- Byte-addressable
- Supports 8-bit and 16-bit operations
- Memory access through `load` and `store` instructions

## Stack Model
Both working and return stacks:
- Configurable maximum size (default 1024 bytes)
- Support 8-bit and 16-bit operations
- Used for:
  - Working stack: General computation
  - Return stack: Subroutine call management

## Hardware Interface
The VM supports virtual hardware devices that operate through memory frames.

### Memory Frame Model
- Hardware devices are assigned specific memory frames
- A memory frame is a contiguous section of VM memory
- Frames are allocated using start address and size
- Multiple devices can operate on different memory frames

### Hardware Implementation
Hardware devices are implemented using a generic interface:
```zig
const Hardware = fn(
    DeviceType: type,
    ErrorType: type,
    updateFn: fn(*DeviceType, *MemoryFrame) ErrorType!void,
) type;
```

Each hardware device must provide:
1. A device type struct with any needed state
2. An error set for device-specific errors
3. An update function that processes the memory frame

### Update Cycle
- Hardware devices are updated after each VM instruction
- Devices can read from and write to their memory frame
- Communication between VM and hardware is through memory modification
- Devices can signal events by writing to specific memory addresses

### Example Usage
A simple hardware device that responds to memory signals:
```zig
const Test = struct {
    const Error = error{ TestError };
    
    pub fn update(self: *Test, memory: *MemoryFrame) !void {
        if (memory.data[0] == 0xAF) {
            // React to signal
            memory.data[0] = 0;
        }
    }
};

// Create hardware instance
var hardware = try Hardware(Test, Test.Error, Test.update).init(Test{});
hardware.memory = try cpu.memory.getFrame(0x20, 0x0A);
```

## Error Handling
The VM handles several error conditions:
- Illegal instructions
- Stack overflow/underflow
- Invalid memory access
- Division by zero
- Hardware-specific errors
- Memory frame access violations
