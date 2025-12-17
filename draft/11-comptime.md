---
title: "Part 11: Comptime - Compile-Time Execution Deep Dive"
date: 2025-12-17
---

# Part 11: Comptime - Compile-Time Execution Deep Dive

In this article, we'll explore Zig's most powerful and unique feature: comptime. We've mentioned it throughout the series, but now we'll dive deep into HOW it actually works inside the compiler.

---

## Part 1: What is Comptime?

### The Basic Idea

Comptime means "compile time" - code that runs when your program is being compiled, not when it runs:

```zig
// This runs at RUNTIME (when you execute the program)
var x: u32 = 5;
x = x + 1;

// This runs at COMPTIME (when you compile)
const y = comptime blk: {
    var result: u32 = 0;
    for (0..10) |i| {
        result += i;
    }
    break :blk result;
};
// y is ALWAYS 45, computed during compilation
```

### Why is Comptime Special?

```
┌─────────────────────────────────────────────────────────────┐
│                  WHY COMPTIME MATTERS                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. ZERO RUNTIME COST                                        │
│     Computation happens at compile time                      │
│     Result is embedded in the binary                         │
│                                                              │
│  2. TYPE AS A VALUE                                          │
│     Types can be computed, passed as arguments               │
│     Enables generics without templates or type erasure       │
│                                                              │
│  3. CODE GENERATION                                          │
│     Generate code based on types or constants                │
│     No macros needed                                         │
│                                                              │
│  4. CONDITIONAL COMPILATION                                  │
│     if (comptime condition) { ... }                          │
│     Dead code is eliminated entirely                         │
│                                                              │
│  5. SAFETY CHECKS                                            │
│     Verify invariants at compile time                        │
│     Catch bugs before program runs                           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Comptime vs Other Languages

```
┌─────────────────────────────────────────────────────────────┐
│                    COMPARISON                                │
│                                                              │
│  C/C++ MACROS                                                │
│    #define MAX(a,b) ((a) > (b) ? (a) : (b))                  │
│    - Text substitution, not real code                        │
│    - No type checking                                        │
│    - Cryptic error messages                                  │
│                                                              │
│  C++ TEMPLATES                                               │
│    template<typename T> T max(T a, T b) { ... }              │
│    - Complex syntax                                          │
│    - SFINAE, concepts, etc.                                  │
│    - Error messages are notorious                            │
│                                                              │
│  JAVA GENERICS                                               │
│    <T> T max(T a, T b) { ... }                               │
│    - Type erasure (runtime overhead)                         │
│    - Limited (no primitive types)                            │
│                                                              │
│  ZIG COMPTIME                                                │
│    fn max(comptime T: type, a: T, b: T) T { ... }            │
│    - Same language, same rules                               │
│    - Full type information                                   │
│    - Clear error messages                                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Part 2: Where Comptime Lives in the Pipeline

### The Compilation Pipeline (Revisited)

```
┌─────────────────────────────────────────────────────────────┐
│              WHERE COMPTIME HAPPENS                          │
│                                                              │
│  Source → Tokens → AST → ZIR → Sema/AIR → Machine Code      │
│                           │      │                           │
│                           │      │                           │
│                           │      └─── COMPTIME RUNS HERE!    │
│                           │                                  │
│                           └─── Marks comptime blocks         │
│                                                              │
│  Comptime is evaluated during SEMANTIC ANALYSIS (Sema)       │
│  This is when we have type information but haven't           │
│  generated machine code yet.                                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### ZIR: Marking Comptime

From `Zir.zig`, there's a special instruction for comptime blocks:

```zig
// From Zir.zig:312
pub const Inst = struct {
    pub const Tag = enum {
        // ... other tags ...
        block_comptime,    // A comptime block
        // ...
    };
};
```

When AstGen sees `comptime { ... }`, it generates a `block_comptime` instruction:

```
┌─────────────────────────────────────────────────────────────┐
│                    ZIR FOR COMPTIME                          │
│                                                              │
│  Source:                                                     │
│    const x = comptime {                                      │
│        var sum: u32 = 0;                                     │
│        sum += 1;                                             │
│        sum += 2;                                             │
│        break sum;                                            │
│    };                                                        │
│                                                              │
│  ZIR:                                                        │
│    %1 = block_comptime {                                     │
│        %2 = int(0)                                           │
│        %3 = add(%2, int(1))                                  │
│        %4 = add(%3, int(2))                                  │
│        break(%4)                                             │
│    }                                                         │
│    %5 = decl_val("x", %1)                                    │
│                                                              │
│  The block_comptime tag tells Sema: "evaluate this now!"     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Sema: The Comptime Interpreter

Sema (Semantic Analysis) is where the magic happens. When it encounters a `block_comptime`, it doesn't generate AIR - it EXECUTES the code:

```
┌─────────────────────────────────────────────────────────────┐
│              SEMA COMPTIME EXECUTION                         │
│                                                              │
│  Normal code path:                                           │
│    ZIR instruction → Sema → AIR instruction                  │
│                                                              │
│  Comptime code path:                                         │
│    ZIR instruction → Sema → EXECUTE → Value                  │
│                              │                               │
│                              └── No AIR generated!           │
│                                  Result is a constant.       │
│                                                              │
│  The result (Value) goes into the InternPool and can be      │
│  used elsewhere in compilation.                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Part 3: Comptime Values

### What Can Be a Comptime Value?

```
┌─────────────────────────────────────────────────────────────┐
│               COMPTIME VALUE TYPES                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  PRIMITIVE VALUES                                            │
│    comptime_int     - Arbitrary precision integer            │
│    comptime_float   - Arbitrary precision float              │
│    bool             - true/false                             │
│    void             - no value                               │
│                                                              │
│  TYPES (yes, types are values!)                              │
│    type             - u32, []const u8, MyStruct, etc.        │
│                                                              │
│  COMPOSITE VALUES                                            │
│    arrays           - [_]u8{1, 2, 3}                         │
│    structs          - .{ .x = 1, .y = 2 }                    │
│    slices           - "hello" (comptime known)               │
│    optionals        - null, or wrapped value                 │
│    error unions     - error.Foo, or wrapped value            │
│                                                              │
│  POINTERS (with restrictions)                                │
│    *const T         - pointer to comptime-known data         │
│    *T               - NOT allowed (would mutate at runtime)  │
│                                                              │
│  FUNCTIONS                                                   │
│    fn               - function pointers (comptime known)     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### comptime_int: Arbitrary Precision

```zig
// comptime_int has NO size limit
const huge = comptime {
    var x: comptime_int = 1;
    for (0..1000) |_| {
        x = x * 2;
    }
    break :blk x;
};
// huge = 2^1000, computed exactly!

// Only when assigned to a fixed type does it get checked
const byte: u8 = huge;  // ERROR: doesn't fit in u8
const big: u256 = huge; // OK if it fits
```

### How Types Are Values

```zig
// T is a comptime parameter of type `type`
fn ArrayList(comptime T: type) type {
    return struct {
        items: []T,
        capacity: usize,

        pub fn append(self: *@This(), item: T) void {
            // ...
        }
    };
}

// Usage:
const IntList = ArrayList(i32);    // Returns a TYPE
var list: IntList = undefined;      // Use that type
```

The call `ArrayList(i32)`:
1. `T` is bound to `i32` (a comptime value of type `type`)
2. The function body executes at comptime
3. Returns a new struct type (also a comptime value)
4. This type is cached in the InternPool

---

## Part 4: The Comptime Execution Model

### Comptime Memory

Comptime code can have "variables", but they exist only during compilation:

```
┌─────────────────────────────────────────────────────────────┐
│              COMPTIME MEMORY MODEL                           │
│                                                              │
│  Comptime variables live in COMPILER MEMORY (the arena)      │
│  NOT in the program's runtime memory                         │
│                                                              │
│  const x = comptime {                                        │
│      var temp: [1000]u8 = undefined;  // In compiler memory  │
│      for (&temp, 0..) |*byte, i| {                           │
│          byte.* = @intCast(i % 256);                         │
│      }                                                       │
│      break :blk temp;                                        │
│  };                                                          │
│                                                              │
│  // x is embedded in the binary as 1000 bytes of data        │
│  // The 'temp' variable never exists at runtime              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### What Comptime CANNOT Do

```
┌─────────────────────────────────────────────────────────────┐
│              COMPTIME RESTRICTIONS                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  NO RUNTIME VALUES                                           │
│    fn foo(x: u32) u32 {                                      │
│        return comptime x + 1;  // ERROR: x is not comptime   │
│    }                                                         │
│                                                              │
│  NO SIDE EFFECTS (mostly)                                    │
│    comptime {                                                │
│        std.debug.print("hi");  // ERROR: I/O not allowed     │
│    }                                                         │
│                                                              │
│  NO UNBOUNDED LOOPS                                          │
│    comptime {                                                │
│        while (true) {}  // ERROR: would hang compiler        │
│    }                                                         │
│    // Compiler has a loop iteration limit                    │
│                                                              │
│  NO RUNTIME MEMORY                                           │
│    comptime {                                                │
│        var ptr = malloc(100);  // ERROR: no allocator        │
│    }                                                         │
│    // Use comptime allocator or fixed arrays                 │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Comptime Control Flow

The compiler literally interprets your code:

```zig
const result = comptime {
    var x: u32 = 0;

    // This loop ACTUALLY RUNS during compilation
    for (0..100) |i| {
        if (i % 2 == 0) {
            x += @intCast(i);
        }
    }

    // Conditionals work too
    if (x > 1000) {
        break :blk x;
    } else {
        break :blk x * 2;
    }
};
```

The compiler:
1. Creates a comptime variable `x = 0`
2. Iterates 100 times, updating `x`
3. Evaluates the condition
4. Returns the appropriate value
5. `result` becomes a compile-time constant

---

## Part 5: Type Functions (Generics)

### How Generics Work

Zig doesn't have "generics" as a special feature. It has functions that return types:

```zig
// This is just a function that happens to return a type
fn Vector(comptime len: usize, comptime T: type) type {
    return struct {
        data: [len]T,

        const Self = @This();

        pub fn dot(a: Self, b: Self) T {
            var result: T = 0;
            for (a.data, b.data) |x, y| {
                result += x * y;
            }
            return result;
        }
    };
}

// Create specific types
const Vec3f = Vector(3, f32);
const Vec4i = Vector(4, i32);
```

### Type Caching in InternPool

```
┌─────────────────────────────────────────────────────────────┐
│              TYPE CACHING                                    │
│                                                              │
│  Problem: What if you call Vector(3, f32) multiple times?    │
│                                                              │
│  const a: Vector(3, f32) = ...;                              │
│  const b: Vector(3, f32) = ...;                              │
│  // Are these the same type?                                 │
│                                                              │
│  Solution: InternPool (from Article 5)                       │
│                                                              │
│  1. First call to Vector(3, f32):                            │
│     - Execute function body                                  │
│     - Create new struct type                                 │
│     - Store in InternPool with key (Vector, 3, f32)         │
│     - Return InternPool index                                │
│                                                              │
│  2. Second call to Vector(3, f32):                           │
│     - Look up (Vector, 3, f32) in InternPool                │
│     - Already exists! Return same index                      │
│     - No re-execution needed                                 │
│                                                              │
│  Result: a and b have the SAME type (same InternPool ID)     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### @This() and Self

Inside a type function, `@This()` returns the type being defined:

```zig
fn MyType(comptime T: type) type {
    return struct {
        value: T,

        // @This() refers to this struct
        const Self = @This();

        pub fn clone(self: Self) Self {
            return .{ .value = self.value };
        }
    };
}
```

This works because when Sema evaluates the struct body, it knows what type it's building.

---

## Part 6: Comptime Parameters

### Every Generic is a Comptime Parameter

```zig
// This function has TWO comptime parameters
fn binarySearch(
    comptime T: type,           // The element type
    comptime compareFn: fn(T, T) i32,  // Comparison function
    items: []const T,           // Runtime slice
    target: T,                  // Runtime value
) ?usize {
    // ...
}
```

When you call `binarySearch(i32, std.sort.asc(i32), mySlice, 42)`:
1. `T = i32` is substituted everywhere
2. `compareFn = std.sort.asc(i32)` is inlined
3. A SPECIALIZED version of the function is generated
4. No runtime overhead for the generic machinery

### inline fn vs comptime

```zig
// inline fn: body is inlined at call site, but args can be runtime
inline fn add(a: u32, b: u32) u32 {
    return a + b;
}

// comptime parameter: argument MUST be known at compile time
fn comptimeAdd(comptime a: u32, comptime b: u32) u32 {
    return a + b;  // This addition happens at compile time
}

// Usage
const x = add(runtime_val, 5);        // OK, runtime
const y = comptimeAdd(3, 5);          // OK, comptime (y = 8)
const z = comptimeAdd(runtime_val, 5); // ERROR: not comptime
```

---

## Part 7: Comptime Conditionals

### if (comptime condition)

```zig
fn process(comptime T: type, value: T) T {
    if (@typeInfo(T) == .int) {
        // This branch is ONLY compiled for integer types
        return value * 2;
    } else if (@typeInfo(T) == .float) {
        // This branch is ONLY compiled for float types
        return value * 2.0;
    } else {
        @compileError("Unsupported type");
    }
}
```

Key insight: The branches that don't match are **completely eliminated**. They don't exist in the final binary.

### Conditional Type Selection

```zig
fn OptionalStorage(comptime T: type) type {
    // Small types: store inline with a flag
    if (@sizeOf(T) <= 8) {
        return struct {
            value: T,
            has_value: bool,
        };
    }
    // Large types: store as pointer
    else {
        return struct {
            ptr: ?*T,
        };
    }
}
```

The type returned depends on the input type's size - evaluated at compile time.

---

## Part 8: @typeInfo and Reflection

### Inspecting Types at Comptime

```zig
const std = @import("std");

fn printFields(comptime T: type) void {
    const info = @typeInfo(T);

    switch (info) {
        .@"struct" => |s| {
            inline for (s.fields) |field| {
                std.debug.print("Field: {s}, Type: {}\n", .{
                    field.name,
                    field.type,
                });
            }
        },
        else => @compileError("Expected struct"),
    }
}

const Point = struct {
    x: f32,
    y: f32,
    z: f32,
};

// At compile time, this prints:
// Field: x, Type: f32
// Field: y, Type: f32
// Field: z, Type: f32
comptime {
    printFields(Point);
}
```

### Building Types from TypeInfo

```zig
// Create a type with doubled field sizes
fn DoubleFields(comptime T: type) type {
    const info = @typeInfo(T).@"struct";

    // Build new fields array at comptime
    var new_fields: [info.fields.len]std.builtin.Type.StructField = undefined;

    inline for (info.fields, 0..) |field, i| {
        new_fields[i] = .{
            .name = field.name,
            .type = [2]field.type,  // Array of 2 instead of single
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };
    }

    // Return a new struct type
    return @Type(.{
        .@"struct" = .{
            .fields = &new_fields,
            .decls = &.{},
            .layout = .auto,
            .is_tuple = false,
        },
    });
}
```

---

## Part 9: Comptime Execution Internals

### How Sema Interprets Code

```
┌─────────────────────────────────────────────────────────────┐
│              SEMA COMPTIME INTERPRETER                       │
│                                                              │
│  When Sema encounters comptime code:                         │
│                                                              │
│  1. CREATE COMPTIME SCOPE                                    │
│     - Allocate comptime variables in arena                   │
│     - Track which values are comptime-known                  │
│                                                              │
│  2. EVALUATE INSTRUCTIONS                                    │
│     For each ZIR instruction in the comptime block:          │
│     - Execute the operation                                  │
│     - Store result as a comptime Value                       │
│     - Handle control flow (loops, branches)                  │
│                                                              │
│  3. HANDLE OPERATIONS                                        │
│     add(%a, %b):                                             │
│       - Get comptime value of %a                             │
│       - Get comptime value of %b                             │
│       - Compute sum                                          │
│       - Return new comptime value                            │
│                                                              │
│  4. RETURN RESULT                                            │
│     - Final value goes into InternPool                       │
│     - Used as a constant in further compilation              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Comptime Values in InternPool

From Article 5, the InternPool stores all compile-time values:

```
┌─────────────────────────────────────────────────────────────┐
│              COMPTIME VALUES IN INTERNPOOL                   │
│                                                              │
│  InternPool stores:                                          │
│                                                              │
│  TYPES                                                       │
│    u32, i64, []const u8, MyStruct, fn(i32) void             │
│                                                              │
│  COMPTIME VALUES                                             │
│    42 (comptime_int)                                         │
│    3.14 (comptime_float)                                     │
│    "hello" (comptime string)                                 │
│    .{ .x = 1, .y = 2 } (comptime struct)                    │
│                                                              │
│  FUNCTION INSTANCES                                          │
│    add(i32) - specialized for i32                            │
│    add(f64) - specialized for f64                            │
│                                                              │
│  Each entry has a unique ID. Same value = same ID.           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Loop Limits

To prevent infinite compilation, there's a limit:

```zig
comptime {
    var i: u32 = 0;
    while (i < 1_000_000) : (i += 1) {
        // ...
    }
}
// This might hit the evaluation limit!
```

The compiler has a configurable limit on comptime operations. If your code exceeds it:

```
error: evaluation exceeded 1000000 backwards branches
note: use @setEvalBranchQuota() to raise the limit
```

You can increase it:

```zig
comptime {
    @setEvalBranchQuota(10_000_000);
    // Now you get more iterations
}
```

---

## Part 10: Practical Comptime Patterns

### Pattern 1: Lookup Tables

```zig
// Generate a lookup table at compile time
const sin_table = comptime blk: {
    var table: [256]f32 = undefined;
    for (&table, 0..) |*entry, i| {
        const angle = @as(f32, @floatFromInt(i)) / 256.0 * std.math.pi * 2;
        entry.* = @sin(angle);
    }
    break :blk table;
};

// Usage: instant lookup, no computation at runtime
fn fastSin(index: u8) f32 {
    return sin_table[index];
}
```

### Pattern 2: Format Strings

```zig
fn formatNumber(comptime fmt: []const u8, value: anytype) []const u8 {
    // Parse format string at compile time
    comptime {
        if (fmt.len == 0) @compileError("Empty format string");
        // Validate format...
    }

    // Generate optimized formatting code
    // based on comptime-known format
    // ...
}
```

### Pattern 3: Compile-Time Assertions

```zig
fn ensureAlignment(comptime T: type, comptime required: usize) void {
    if (@alignOf(T) < required) {
        @compileError(std.fmt.comptimePrint(
            "Type {} has alignment {} but {} required",
            .{ T, @alignOf(T), required },
        ));
    }
}

const MyData = struct {
    x: u64,
    y: u32,
};

comptime {
    ensureAlignment(MyData, 8);  // OK
    ensureAlignment(MyData, 16); // Compile error!
}
```

### Pattern 4: Interface Checking

```zig
fn isIterator(comptime T: type) bool {
    return @hasDecl(T, "next") and
           @hasDecl(T, "Item");
}

fn iterate(iter: anytype) void {
    comptime {
        if (!isIterator(@TypeOf(iter))) {
            @compileError("Expected an iterator type");
        }
    }
    while (iter.next()) |item| {
        // ...
    }
}
```

---

## Part 11: The Complete Picture

### How Comptime Connects Everything

```
┌─────────────────────────────────────────────────────────────┐
│              COMPTIME IN THE FULL PIPELINE                   │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  SOURCE CODE                                         │    │
│  │  const T = comptime getType();                       │    │
│  │  fn generic(comptime X: type) type { ... }           │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                  │
│                           ▼                                  │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  AST/ZIR (Articles 3-4)                              │    │
│  │  - `comptime` keyword → block_comptime instruction   │    │
│  │  - Comptime params marked in function signatures     │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                  │
│                           ▼                                  │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  SEMA (Article 5) - THE COMPTIME ENGINE              │    │
│  │                                                      │    │
│  │  When it sees block_comptime:                        │    │
│  │  1. Enter comptime evaluation mode                   │    │
│  │  2. Interpret ZIR instructions directly              │    │
│  │  3. Compute result value                             │    │
│  │  4. Store in InternPool                              │    │
│  │  5. Continue with constant value                     │    │
│  │                                                      │    │
│  │  Type functions:                                     │    │
│  │  1. Substitute comptime args                         │    │
│  │  2. Evaluate function body                           │    │
│  │  3. Cache result type in InternPool                  │    │
│  │                                                      │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                  │
│                           ▼                                  │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  AIR (Article 6)                                     │    │
│  │  - Comptime blocks → NO AIR (just constants)         │    │
│  │  - Generic functions → specialized AIR per instance  │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                  │
│                           ▼                                  │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  MACHINE CODE (Article 7)                            │    │
│  │  - Comptime results embedded as data                 │    │
│  │  - Each generic instance → separate machine code     │    │
│  │  - Dead branches eliminated entirely                 │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### The Magic Revealed

```
┌─────────────────────────────────────────────────────────────┐
│                  THE COMPTIME SECRET                         │
│                                                              │
│  There's no magic. Comptime is just:                         │
│                                                              │
│  1. The compiler has an INTERPRETER                          │
│     (Sema can execute Zig code)                              │
│                                                              │
│  2. Types are first-class VALUES                             │
│     (stored in InternPool like any other value)              │
│                                                              │
│  3. Functions can be CALLED at compile time                  │
│     (with comptime arguments)                                │
│                                                              │
│  4. Results are CACHED                                       │
│     (InternPool deduplicates types and values)               │
│                                                              │
│  The same language, same semantics, just evaluated           │
│  at a different time (compile vs run).                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Summary

Comptime is Zig's most powerful feature, and now you understand how it works:

1. **ZIR Marking** - `comptime` blocks become `block_comptime` instructions

2. **Sema Interpreter** - Sema literally executes your code during compilation

3. **Values in InternPool** - Comptime results are stored and deduplicated

4. **Type Functions** - Functions returning `type` are just functions evaluated at comptime

5. **Caching** - Same comptime call with same args returns cached result

6. **No Runtime Cost** - Comptime computation is done once, results embedded in binary

7. **Dead Code Elimination** - Comptime branches that don't match are removed entirely

The beauty of comptime is that it's not a separate language feature - it's the same Zig code, just running at a different time. This unified model is what makes Zig's metaprogramming so elegant and error messages so clear.

---

*This article completes our exploration of comptime. Combined with the previous articles, you now have a comprehensive understanding of how the Zig compiler works, from source code to executable, including its powerful compile-time execution capabilities.*
