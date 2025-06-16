# Type Virtual Machine Specification

## Overview
The Type VM is a specialized virtual machine designed for type validation and manipulation during compilation or interpretation. It implements a dual-stack architecture with comprehensive type checking capabilities and a rich set of primitive and complex types.

## Architecture

### Stack System
The VM implements a dual-stack architecture:

1. **Data Stack**
   - Primary stack for type operations
   - Supports standard stack operations (push, pop, dup, swap, over)
   - Automatic stack growth
   - Built-in overflow and underflow protection

2. **Return Stack**
   - Secondary stack for control flow and temporary storage
   - Shares same operations as data stack
   - Used for function calls and return addresses

### Memory Model
- Linear memory space
- Type-aware memory operations
- Support for loading and storing typed data
- Alignment-aware memory access

## Type System

### Primitive Types

#### Basic Types
- `void`: Represents absence of a type
- `null`: Null type
- `bool`: Boolean type
- `comptime_int`: Compile-time known integer
- `comptime_fixed`: Compile-time known fixed-point number

#### Integer Types
```
struct {
    sign: Sign,      // signed or unsigned
    size: u5,        // 1-32 bits
    alignment: Alignment
}
```
- Configurable bit width (1-32 bits)
- Sign selection (signed/unsigned)
- Automatic alignment (1, 2, or 4 bytes)

#### Fixed-Point Types
```
struct {
    sign: Sign,
    integer_size: u4,    // 1-16 bits
    fraction_size: u4,   // 1-16 bits
    alignment: Alignment
}
```
- Separate integer and fraction components
- Built-in scaling factor support
- Configurable precision
- Automatic alignment

### Complex Types

#### Pointers
```
struct {
    kind: PtrKind,   // one or many
    child: TypeIndex
}
```
- Single pointer (`one`)
- Multiple pointer (`many`)
- Type-safe with child type tracking

#### Arrays
```
struct {
    child: TypeIndex,
    size: u32
}
```
- Fixed-size arrays
- Up to 2^32 - 1 elements
- Type-safe element access
- 1-byte alignment

#### Structs
```
struct {
    name: ?[]const u8,
    fields: []const FieldInfo,
    size: u32
}
```
- Named or anonymous structures
- Multiple typed fields
- Automatic size calculation
- Field information tracking

## Instruction Set

### Stack Operations
- `push`: Push type onto stack
- `pop`: Remove top type
- `dup`: Duplicate top type
- `swap`: Exchange top two types
- `over`: Copy second item to top
- `push_reg`/`pop_reg`: Register operations
- `load`/`store`: Memory operations
- `flip`: Move between stacks

### Arithmetic Operations
- `add`, `sub`, `mul`, `div`: Integer operations
- `fx_add`, `fx_sub`, `fx_mul`, `fx_div`: Fixed-point operations

### Bitwise Operations
- `and`, `or`, `xor`, `not`: Logical operations
- `shl`, `shr`: Shift operations

### Control Flow
- `jmp`: Unconditional jump
- `jnz`: Conditional jump
- `call`: Function call (supports FFI)
- `ret`: Return from function
- `trap`: System trap
- `hault`: Stop execution
- `int`: Interrupt

## Stack Effect Validation

The VM includes sophisticated stack effect validation:

### Effect Tracking
- Tracks additions and removals for both stacks
- Handles both known and variable-size effects
- Supports mixed effects (known + variable)

### Validation Rules
1. **Known Effects**
   - Fixed number of items added/removed
   - Predictable stack behavior

2. **Variadic Effects**
   - Dynamic stack changes
   - Used for variable-length operations

3. **Mixed Effects**
   - Combination of known and variadic
   - Used for complex operations

### FFI Support
- Special handling for foreign function calls
- Immediate and non-immediate call modes
- Return address management

## Stack Effect Notation and Validation

### Stack Effect Types
The Type VM uses a sophisticated system to track and validate stack effects using three types of effects:

1. **Known Effects** (`known`)
   ```zig
   KnownOrVar{ .known = u32 }
   ```
   - Represents a fixed number of stack items
   - Used for operations with predictable stack behavior
   - Example: `push` adds exactly one item (known(1))

2. **Variadic Effects** (`variadic`)
   ```zig
   KnownOrVar{ .variadic = void }
   ```
   - Represents a variable number of stack items
   - Used for operations where stack effect depends on runtime values
   - Example: `load` operation can add variable number of items

3. **Mixed Effects** (`mixed`)
   ```zig
   KnownOrVar{ .mixed = union { known: u32, variadic: void } }
   ```
   - Combines known and variable effects
   - Used for complex operations with both fixed and variable components
   - Example: `store` removes N+2 items (N values + pointer + length)

### Stack Effect Examples

#### Basic Operations
```
push:  ( -- x )           // data_stack_additions = known(1)
pop:   ( x -- )          // data_stack_removals = known(1)
dup:   ( x -- x x )      // data_stack_additions = known(1)
swap:  ( x y -- y x )    // data_stack_additions = known(0) (no net change)
over:  ( x y -- x y x )  // data_stack_additions = known(0) (no net change)
```

#### Memory Operations
```
load:  ( ptr len -- x1 x2 ... xn )  // data_stack_removals = known(2)
                                    // data_stack_additions = variadic
store: ( x1 x2 ... xn ptr len -- )  // data_stack_removals = mixed(1)
```

#### Arithmetic Operations
```
add:    ( x y -- z )     // data_stack_removals = known(2)
                         // data_stack_additions = known(1)
fx_mul: ( x y -- z )     // data_stack_removals = known(2)
                         // data_stack_additions = known(1)
```

#### Control Flow Operations
```
jnz:  ( cond -- )       // data_stack_removals = known(1)
call: ( -- )            // return_stack_additions = known(1)
                        // data_stack_removals depends on call type:
                        //   immediate: known(0)
                        //   non-immediate: known(1)
```

### Validation Process

The stack effect validation occurs through the following steps:

1. **Effect Determination**
   ```zig
   pub fn getStackSizeEffect(instruction: Instruction) StackSizeEffect {
       const selector = if (instruction.stack == 0) 
           StackSelector.data_stack 
           else StackSelector.return_stack;
       // ...
   }
   ```
   - Each instruction's effect is determined based on its opcode and stack selector
   - Effects are tracked separately for data and return stacks

2. **Effect Tracking**
   ```zig
   StackSizeEffect {
       data_stack_additions: KnownOrVar,
       data_stack_removals: KnownOrVar,
       return_stack_additions: KnownOrVar,
       return_stack_removals: KnownOrVar,
   }
   ```
   - Tracks additions and removals for both stacks
   - Each effect can be known, variadic, or mixed

3. **Special Cases**
   - **FFI Calls**: Different validation for immediate vs non-immediate calls
   - **Stack Transfers**: Operations like `flip` affect both stacks simultaneously
   - **Memory Operations**: Variable stack effects based on runtime values

### Real-World Examples

1. **Array Load Operation**
   ```
   // Loading 3 elements from memory
   push_ptr   ( -- ptr )
   push 3     ( ptr -- ptr 3 )
   load       ( ptr 3 -- x1 x2 x3 )
   ```

2. **Fixed-Point Calculation**
   ```
   // Computing (a + b) * c
   fx_add     ( a b -- sum )
   fx_mul     ( sum c -- result )
   ```

3. **Conditional Jump**
   ```
   // if (a > b) jump
   cmp        ( a b -- flag )
   jnz        ( flag -- )
   ```

The validation system ensures type safety and stack consistency while allowing for complex operations with variable effects. It prevents stack underflow/overflow conditions and maintains the integrity of both data and return stacks throughout program execution.

## Use Cases

1. **Compilation Pipeline**
   - Type checking during compilation
   - Type inference
   - Code generation validation

2. **Static Analysis**
   - Type compatibility verification
   - Stack effect validation
   - Memory safety checks

3. **Runtime Type System**
   - Dynamic type checking
   - Type-safe memory operations
   - FFI boundary validation

4. **Language Implementation**
   - Type system modeling
   - Semantic analysis
   - Bytecode validation
