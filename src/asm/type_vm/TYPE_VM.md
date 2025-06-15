# Type Virtual Machine Specification

## Overview

The Type VM is a specialized component that helps ensure your programs handle data types correctly. Think of it as a safety checker that works alongside your main program to prevent type-related errors, like trying to use a number where text is expected.

### Key Benefits
- Catches type errors before they cause problems
- Makes it easier to work with complex data structures
- Helps prevent memory-related bugs
- Provides clear error messages when something goes wrong

### How to Read This Document

This specification is organized in layers, starting with the simplest concepts and building up to more complex ones:

1. **Basic Types**: Start here to understand the fundamental types like numbers and booleans
2. **Composite Types**: Learn how to combine basic types into more complex structures
3. **Type Safety**: Understand how the system prevents common programming errors
4. **Advanced Features**: Explore more sophisticated features like fixed-point numbers

Each section includes:
- Clear explanations of concepts
- Real-world examples
- Common use cases
- Safety considerations

If you're new to the system, we recommend reading sections in order. Experienced users can jump directly to relevant sections using the table of contents.

## Quick Start Examples

Here are some common scenarios to help you understand what the Type VM can do:

1. **Basic Number Handling**
   ```
   i16: -32,768 to 32,767 (whole numbers)
   sf8.8: -128.00 to 127.99 (numbers with decimals)
   ```

2. **Optional Values**
   ```
   opt(i16): A number that might not be there
   opt(Point2D): A coordinate that might be undefined
   ```

3. **Result Types**
   ```
   Result: { ok: i16, error: u8 }
   A value that's either a success (with data) or an error code
   ```

## Type System

### Type System Core

Think of types as containers that tell us what kind of data we can store and how to work with it. Let's look at the basic building blocks:

#### Number Type
Numbers are the most basic type of data. We support different sizes depending on your needs:

- **Small Numbers** (8-bit):
  - Signed: `-128 to 127` (like temperature readings)
  - Unsigned: `0 to 255` (like color values)

- **Larger Numbers** (16-bit):
  - Signed: `-32,768 to 32,767` (like altitude measurements)
  - Unsigned: `0 to 65,535` (like population counts)

Real-world example: A game's player stats might use:
- Health points: `u8` (0-255)
- Position: `i16` (-32,768 to 32,767)
- Score: `u16` (0-65,535)

#### Fixed-Point Type
For when you need decimal places but want to avoid floating-point complexity:

- **8.8 Format** (good for small measurements)
  - Think: temperature with 2 decimal places
  - Signed: `-128.00 to 127.99` in steps of `0.01`
  - Unsigned: `0.00 to 255.99` in steps of `0.01`
  - Perfect for: prices, temperatures, speeds

- **16.16 Format** (high precision)
  - Think: scientific measurements
  - Signed: `-32,768.0000 to 32,767.9999`
  - Unsigned: `0.0000 to 65,535.9999`
  - Perfect for: 3D coordinates, physics calculations

Real-world example: A weather station might use:
- Temperature: `sf8.8` (-128.00°C to 127.99°C)
- Wind speed: `uf8.8` (0.00 to 255.99 km/h)
- Pressure: `sf16.16` (high precision atmospheric pressure)

#### Special Types
Simple but essential types:

- `bool`: True/False values
  - Perfect for: flags, toggles, yes/no decisions
  - Examples: isPlayerAlive, hasKey, isGameOver

- `void`: Represents "nothing"
  - Used when a function doesn't return anything
  - Or when you need to explicitly indicate absence of data

### Composite Types

These are the building blocks for creating more complex data structures. Think of them as ways to combine simpler types into more useful forms.

#### Optional Type
Sometimes a value might not exist, and that's okay! Optional types make this explicit and safe.

Real-world examples:
1. User Profile
   - Middle name: `opt(string)` - not everyone has one
   - Phone number: `opt(string)` - might be unlisted
   - Last login: `opt(time)` - for new users

2. Game State
   - Current weapon: `opt(Weapon)` - might be unarmed
   - Target enemy: `opt(Enemy)` - might not be targeting anything
   - Power-up timer: `opt(u16)` - might not have an active power-up

How it works:
- Adds a single yes/no bit to track if value exists
- Maintains proper memory alignment
- Forces you to check if value exists before using it
- Can wrap any other type (even other optionals!)

#### Union Type
A union lets you have different types of data in the same space, but only one at a time. Think of it like a box that can hold different things, but only one thing at a time.

Real-world examples:
1. Message System
   ```
   Message:
     text: string        - for chat messages
     playerJoined: ID    - for player joining
     gameOver: Score     - for end of game
   ```

2. Game Items
   ```
   Item:
     weapon: Weapon      - for swords, bows, etc.
     potion: Potion      - for health, mana potions
     key: KeyType        - for opening doors
   ```

Safety Features:
- Knows which type is currently stored
- Prevents accessing wrong type
- Manages memory efficiently
- Makes state machines easy to implement

#### Common Patterns

1. Result Types (Success/Error handling)
   ```
   SaveResult:
     ok: SaveData       - when save succeeds
     error: ErrorCode   - when something goes wrong
   ```

2. State Machines
   ```
   PlayerState:
     idle: IdleInfo     - standing still
     walking: WalkInfo  - moving around
     jumping: JumpInfo  - in the air
   ```

3. Message Systems
   ```
   NetworkMessage:
     chat: ChatData     - player chat
     move: MoveData     - player movement
     action: ActionData - player actions
   ```

### Pointer Types

Pointers are ways to reference data stored somewhere else in memory. Think of them like a remote control - they let you interact with something from a distance.

#### Types of Pointers

1. Single-Item Pointer (`ptr.one`)
   - Points to just one thing
   - Like a bookmark in a book
   - Example uses:
     - Current player in a game
     - Selected menu item
     - Active tool in an editor

2. Multi-Item Pointer (`ptr.many`)
   - Points to a sequence of items
   - Like a bookmark that marks several pages
   - Example uses:
     - List of players in a game
     - Inventory items
     - Message history

#### Real-World Examples

1. Game Entity System
   ```
   // Single entity reference
   currentTarget: ptr.one(Enemy)    // The enemy player is targeting
   
   // List of entities
   nearbyEnemies: ptr.many(Enemy)   // All enemies in range
   ```

2. UI System
   ```
   // Single element
   selectedButton: ptr.one(Button)   // Currently focused button
   
   // Multiple elements
   menuItems: ptr.many(MenuItem)     // All items in a menu
   ```

3. Resource Management
   ```
   // Single resource
   currentLevel: ptr.one(Level)      // The level being played
   
   // Multiple resources
   loadedTextures: ptr.many(Texture) // All loaded textures
   ```

#### Safety Features

1. Null Safety
   - Must check if pointer is valid
   - Can't use a null pointer
   - Example: Checking current target
     ```
     if (hasTarget) {
         // Safe to use currentTarget
     }
     ```

2. Bounds Checking
   - Can't read past array ends
   - Automatically tracks array length
   - Example: Processing enemies
     ```
     for (enemies.items) |enemy| {
         // Safely process each enemy
     }
     ```

3. Type Safety
   - Can't mix different pointer types
   - Can't treat single items as arrays
   - Helps prevent common bugs

### Composite Types
- `array`: Array of a single element type
- `struct`: Named collection of fields
- `union`: Tagged union of multiple types

## Working with Types

### Type Registry: The Type System's Library

Think of the type registry as a library that keeps track of all the types in your program. Just like a library catalogs books, the type registry catalogs types.

#### How It Works

1. Built-in Types
   - Comes with basic types pre-registered
   - Like a library's reference section
   - Examples:
     ```
     bool   - for true/false values
     i8     - for small numbers (-128 to 127)
     u8     - for small positive numbers (0 to 255)
     i16    - for larger numbers
     ```

2. Custom Types
   - Add your own types as needed
   - Like adding new books to the library
   - Examples:
     ```
     Player  - for player data
     Item    - for game items
     Monster - for enemy types
     ```

3. Type Lookup
   - Fast type finding by name or ID
   - Like a library's catalog system
   - Example: Looking up a type
     ```
     Player type needed:
     1. Look up "Player" in registry
     2. Get all Player type information
     3. Use for validation/operations
     ```

### Type Operations: Working with Types

Just like you can do math with numbers, you can do operations with types:

1. Stack Operations
   ```
   push Player    - Add Player type to stack
   pop           - Remove top type from stack
   dup           - Duplicate top type
   swap          - Swap top two types
   ```

2. Type Checking
   Examples:
   ```
   check Player  - Is this a Player?
   check Item    - Is this an Item?
   equals        - Are these the same type?
   ```

3. Common Operations
   ```
   getSize      - How big is this type?
   isOptional   - Can this be empty?
   canConvert   - Can we change to another type?
   ```

### Error Handling: When Things Go Wrong

The system provides helpful error messages when something isn't right:

1. Type Mismatches
   ```
   Expected: Player
   Found: Monster
   Hint: Make sure you're using the right type
   ```

2. Invalid Operations
   ```
   Can't convert Item to Player
   Hint: These types are not compatible
   ```

3. Stack Problems
   ```
   Stack empty: Can't pop
   Hint: Make sure there's data on the stack
   ```

## Type Definitions

### Type IDs
- Each type has a unique ID for reference
- Built-in types are registered first but not specially reserved
- New types can be registered at any time
- IDs are assigned sequentially

### Type Registry

The type registry is a centralized system for managing and looking up type information.

#### Registry Structure
- Dynamic list of type entries, each containing:
  - Unique numeric ID (assigned sequentially)
  - Type name (for lookup)
  - Type definition (metadata and structure)
  - Size and alignment information
- Hash map for fast name-based lookups
- Memory management through allocator interface

#### Core Operations
1. Type Registration
   - Validate type definition
   - Assign unique ID
   - Store type metadata
   - Add to name lookup map
   - Return type ID for reference

2. Type Lookup
   - By ID: O(1) array index lookup
   - By name: O(1) hash map lookup
   - Returns type entry with all metadata

3. Type Creation Helpers
   - Create struct types with field definitions
   - Create union types with variant definitions
   - Create pointer types (one/many variants)
   - Create optional type wrappers

#### Type Management
1. Initialization
   - Create empty registry
   - Register built-in types first
   - Initialize name lookup map

2. Type Registration Flow
   - Validate type definition
   - Calculate memory layout
   - Generate unique ID
   - Store type information
   - Update lookup maps

3. Memory Management
   - All type names and metadata owned by registry
   - Clean deallocation of all resources
   - No memory leaks on shutdown

4. Error Handling
   - Duplicate type name detection
   - Invalid type reference handling
   - Out of memory conditions
   - Type validation failures

### Type Registration Process

#### Initial Registry Setup

1. Built-in Type Registration
   - Create registry with allocator
   - Register void type (size 0, align 1)
   - Register bool type (size 1, align 1)
   - Register basic integer types:
     - i8/u8 (size 1, align 1)
     - i16/u16 (size 2, align 2)
   - Register fixed-point types:
     - sf8.8/uf8.8 (size 2, align 2)
     - sf16.16/uf16.16 (size 4, align 4)

2. User Type Registration Flow

   a) Struct Type Creation
      - Specify struct name
      - Define fields with types and names
      - Calculate field offsets automatically
      - Store in registry with new ID

   b) Union Type Creation
      - Specify union name
      - Define variants with types and names
      - Calculate shared storage layout
      - Add tag byte handling
      - Store in registry with new ID

   c) Pointer Type Creation
      - Specify target type
      - Choose category (one/many)
      - Generate type with platform size
      - Store in registry with new ID

   d) Optional Type Creation
      - Specify value type
      - Add presence flag metadata
      - Preserve wrapped type alignment
      - Store in registry with new ID

3. Type System Features
   - Dynamic registration at runtime
   - Unlimited type definitions
   - Efficient lookup by ID or name
   - Allocator-based memory management
   - Helper functions for common patterns
   - Type compatibility validation
   - Complete cleanup on shutdown

### Type Definition Format

#### Core Type Definitions

1. Basic Types
   - Numbers: Bit width, alignment, signedness
   - Fixed-point: Integer/fractional bits, alignment, signedness
   - Special: bool (1 bit), void (0 bits)

2. Struct Types
   - Name of the struct type
   - Array of field definitions:
     - Field name
     - Field type reference
     - Field offset in bytes
   - Total size and alignment

3. Union Types
   - Name of the union type
   - Array of variant definitions:
     - Variant name
     - Variant type reference
     - Data offset (shared storage)
   - Tag byte for active variant
   - Size of largest variant + tag

4. Pointer Types
   - Target type reference
   - Category (one/many)
   - Size of pointer
   - Alignment requirement

5. Optional Types
   - Value type reference
   - Presence flag (1 bit)
   - Alignment of wrapped type

#### Layout and Packing

1. Memory Layout Rules
   - Power-of-2 alignment
   - No padding in basic types
   - Field padding in structs
   - Tag byte + largest variant in unions

2. Size Calculation
   - Basic types: specified bits
   - Structs: sum of aligned fields
   - Unions: tag + max variant size
   - Pointers: platform pointer size
   - Optional: wrapped type + flag bit

3. Alignment Requirements
   - Basic types: natural alignment
   - Structs: largest field alignment
   - Unions: largest variant alignment
   - Pointers: platform pointer alignment
   - Optional: wrapped type alignment

#### Type Definition Process

1. Validation Steps
   - Check type name uniqueness
   - Verify referenced types exist
   - Validate field/variant names
   - Check alignment constraints
   - Verify size limits

2. Registration Flow
   - Parse type definition
   - Validate constraints
   - Calculate layout
   - Assign type ID
   - Store in registry

3. Safety Rules
   - No recursive types (except via pointers)
   - Unique field/variant names
   - Valid alignment values
   - Size within platform limits

## Type Stack Operations

### Stack Manipulation
- `push_type T`: Push type T onto the stack
- `pop_type`: Remove and return top type from stack
- `dup_type`: Duplicate top type on stack
- `swap_type`: Swap top two types on stack

### Type Checking
- `check_type T`: Verify top of stack is type T
- `equals_type`: Check if two types are equal

### Type State
- Track current type of stack elements
- Basic type validation for operations

## Error Handling

### Type Errors
- Type mismatch errors
- Invalid operation errors
- Stack underflow/overflow errors

### Error Reporting
- Clear error messages with type context
- Source location information
- Suggested fixes when possible

## Implementation Notes

### Memory Layout
- Simple type enum for basic types
- Array and struct types with element/field information

### Integration
- Basic type checking during bytecode execution
- Runtime type validation for stack operations

## Fixed-Point Operations

### Arithmetic
- Addition and subtraction operate directly on the binary representation
- Multiplication requires shifting:
  1. Multiply the full numbers as integers
  2. Shift right by the number of fractional bits (8 or 16)
- Division requires shifting:
  1. Shift left the numerator by the number of fractional bits (8 or 16)
  2. Divide by the denominator

### Type Rules
- Operations between same fixed-point types maintain that type and signedness
- Mixed signed/unsigned fixed-point operations:
  - Result is signed if either operand is signed
  - Range checking is performed for unsigned results
- Mixed operations between integers and fixed-point:
  - Integer is first converted to fixed-point matching the target's signedness
  - Result is in the fixed-point format
- Converting between different fixed-point formats:
  - 8.8 to 16.16: shift left 8 bits
  - 16.16 to 8.8: shift right 8 bits (with rounding)
  - Signed to unsigned: check for negative values
  - Unsigned to signed: range check against signed maximum

### Error Cases
- Overflow checking in arithmetic operations
- Range validation when converting between types
- Division by zero detection

## Fixed-Point Numbers: Working with Decimals

Fixed-point numbers let you work with decimal values without the complexity of floating-point math. They're perfect for games, financial calculations, and many other uses.

### Real-World Examples

1. Game Physics
   ```
   Position: sf16.16
   - Precise enough for smooth movement
   - Range: -32768.0000 to 32767.9999
   - Perfect for: character positions, camera movement
   
   Velocity: sf8.8
   - Good for speed calculations
   - Range: -128.00 to 127.99
   - Perfect for: movement speed, animation rates
   ```

2. Financial Calculations
   ```
   Price: uf8.8
   - Two decimal places for cents
   - Range: 0.00 to 255.99
   - Perfect for: item prices, small transactions
   
   Balance: sf16.16
   - Four decimal places for precise math
   - Range: -32768.0000 to 32767.9999
   - Perfect for: account balances, interest calculations
   ```

3. Sensor Readings
   ```
   Temperature: sf8.8
   - Two decimal places
   - Range: -128.00°C to 127.99°C
   - Perfect for: environmental monitoring
   
   Pressure: uf16.16
   - High precision positive values
   - Range: 0.0000 to 65535.9999
   - Perfect for: pressure sensors, altitude readings
   ```

### How Operations Work

1. Basic Math
   ```
   Addition/Subtraction: Just like regular numbers
   pos = pos + velocity  // 100.5 + 0.5 = 101.0
   
   Multiplication: Needs scaling
   speed = speed * 2    // 1.5 * 2 = 3.0
   
   Division: Needs scaling
   share = total / 2    // 100.0 / 2 = 50.0
   ```

2. Type Conversion Examples
   ```
   Integer to Fixed:
   5 → 5.0000 (shift left)
   
   Fixed to Integer:
   5.7500 → 5 (shift right, rounds down)
   
   Between Fixed Types:
   sf8.8 to sf16.16 (more precision)
   sf16.16 to sf8.8 (less precision, must check range)
   ```

### Safety Features

1. Overflow Protection
   ```
   speed += acceleration
   // Checks if result still fits in type
   // Prevents wraparound errors
   ```

2. Range Validation
   ```
   Converting 1000.0 to sf8.8
   // Error: Value too large for type
   // Maximum is 127.99
   ```

3. Sign Handling
   ```
   Converting -1.5 to unsigned
   // Error: Negative value in unsigned type
   // Use signed type instead
   ```

This approach to decimal numbers gives you:
- Predictable precision (always same number of decimal places)
- Fast calculations (all integer math under the hood)
- No floating-point errors
- Clear range limits
- Type safety
