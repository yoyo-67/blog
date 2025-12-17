---
title: "Zig Compiler Internals Part 5: Semantic Analysis"
date: 2025-12-17
---

# Zig Compiler Internals Part 5: Semantic Analysis

*The heart of the compiler: type checking, comptime, and more*

---

## Introduction

**Sema** (Semantic Analysis) is the brain of the Zig compiler. While the parser checks that your code is grammatically correct, Sema checks that it actually *makes sense*.

Think of it this way:
- **Parser**: "This sentence has correct grammar"
- **Sema**: "This sentence actually means something coherent"

Before diving into how Sema works, let's understand **why** we need it.

---

## Part 1: Why Do We Need Semantic Analysis?

### Syntax vs Semantics

The parser only checks **syntax** (grammar). It doesn't understand **meaning**:

```
┌─────────────────────────────────────────────────────────────────────┐
│ SYNTAX vs SEMANTICS                                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ SYNTAX = Grammar rules                                              │
│ "Does this follow the language's structure?"                        │
│                                                                      │
│   const x = 5 + 3;     ✓ Valid syntax                              │
│   const x 5 + = 3      ✗ Invalid syntax (parser catches this)      │
│                                                                      │
│ ─────────────────────────────────────────────────────────────────── │
│                                                                      │
│ SEMANTICS = Meaning                                                 │
│ "Does this actually make sense?"                                    │
│                                                                      │
│   const x: u32 = "hello";    ✓ Valid syntax!                       │
│                               ✗ Invalid semantics (can't assign     │
│                                 string to integer)                  │
│                                                                      │
│   const y = a + b;           ✓ Valid syntax!                       │
│                               ✗ Invalid semantics (a and b don't   │
│                                 exist)                              │
│                                                                      │
│   const z = foo();           ✓ Valid syntax!                       │
│                               ✗ Invalid semantics (foo doesn't     │
│                                 exist, or returns wrong type)       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### What Sema Catches

Sema is responsible for catching ALL of these errors:

```
┌─────────────────────────────────────────────────────────────────────┐
│ ERRORS THAT SEMA CATCHES                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ 1. TYPE MISMATCHES                                                  │
│    ─────────────────                                                │
│    const x: u32 = "hello";      // Can't assign string to u32      │
│    const y: i8 = 1000;          // 1000 doesn't fit in i8          │
│    foo(5) where foo expects string  // Wrong argument type         │
│                                                                      │
│ 2. UNDEFINED REFERENCES                                             │
│    ─────────────────                                                │
│    const x = y + 1;             // y doesn't exist                 │
│    foo();                       // foo doesn't exist               │
│    obj.field                    // field doesn't exist             │
│                                                                      │
│ 3. INVALID OPERATIONS                                               │
│    ─────────────────                                                │
│    "hello" + "world"            // Can't add strings (use ++)      │
│    5 / 0                        // Division by zero (at comptime)  │
│    arr[100] where arr.len = 10  // Out of bounds (at comptime)     │
│                                                                      │
│ 4. CONTROL FLOW ERRORS                                              │
│    ─────────────────                                                │
│    fn foo() u32 { }             // Missing return value            │
│    break; (outside loop)        // Break not in loop               │
│    unreachable code             // Code after return               │
│                                                                      │
│ 5. COMPTIME ERRORS                                                  │
│    ─────────────────                                                │
│    comptime { while(true) {} }  // Infinite loop at compile time   │
│    @compileError("msg")         // Explicit error                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 2: What is Type Checking?

### The Core Idea

Every expression has a **type**. Type checking ensures types are used correctly:

```
┌─────────────────────────────────────────────────────────────────────┐
│ EVERY EXPRESSION HAS A TYPE                                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Expression              Type                                        │
│ ──────────────────      ─────────────────                          │
│ 42                      comptime_int (integer, size unknown)       │
│ 42.5                    comptime_float                              │
│ "hello"                 *const [5:0]u8                              │
│ true                    bool                                        │
│ x (where x: u32)        u32                                        │
│ arr[i]                  element type of arr                        │
│ foo()                   return type of foo                         │
│ a + b                   common type of a and b                     │
│ if (c) x else y         common type of x and y                     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### How Type Checking Works

Sema walks through each expression and verifies types match:

```
┌─────────────────────────────────────────────────────────────────────┐
│ EXAMPLE: const sum: u32 = a + b;                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Step 1: Look up 'a'                                                 │
│         → Found: a is u32                                           │
│                                                                      │
│ Step 2: Look up 'b'                                                 │
│         → Found: b is u32                                           │
│                                                                      │
│ Step 3: Check 'a + b'                                               │
│         → Can u32 be added to u32? YES                             │
│         → Result type: u32                                          │
│                                                                      │
│ Step 4: Check assignment                                            │
│         → Target type: u32 (from declaration)                       │
│         → Source type: u32 (from a + b)                            │
│         → Do they match? YES                                        │
│                                                                      │
│ Result: Type check PASSED ✓                                         │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ EXAMPLE: const sum: u32 = a + "hello";                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Step 1: Look up 'a'                                                 │
│         → Found: a is u32                                           │
│                                                                      │
│ Step 2: Look up "hello"                                             │
│         → Type: *const [5:0]u8 (string literal)                    │
│                                                                      │
│ Step 3: Check 'a + "hello"'                                         │
│         → Can u32 be added to string? NO!                          │
│         → ERROR: "invalid operands to + operator"                  │
│                                                                      │
│ Result: Type check FAILED ✗                                         │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Type Inference

Sometimes you don't specify the type - Sema figures it out:

```
┌─────────────────────────────────────────────────────────────────────┐
│ TYPE INFERENCE                                                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ EXPLICIT typing (you specify the type):                             │
│                                                                      │
│   const x: u32 = 42;    // You said it's u32                       │
│                                                                      │
│ INFERRED typing (Sema figures it out):                              │
│                                                                      │
│   const x = @as(u32, 42);   // Sema sees @as, knows it's u32       │
│   const y = foo();          // Sema looks at foo's return type     │
│   const z = a + b;          // Sema finds common type of a and b   │
│                                                                      │
│ How inference works:                                                │
│                                                                      │
│   const result = if (condition) value1 else value2;                │
│                                                                      │
│   1. Analyze value1 → type T1                                      │
│   2. Analyze value2 → type T2                                      │
│   3. Find "peer type" of T1 and T2                                 │
│      (smallest type that can hold both)                            │
│   4. result has that peer type                                     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 3: What is Comptime?

### The Revolutionary Idea

Zig can run code **at compile time**. This is called "comptime":

```
┌─────────────────────────────────────────────────────────────────────┐
│ RUNTIME vs COMPTIME                                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ RUNTIME: Code runs when you execute the program                     │
│                                                                      │
│   fn add(a: u32, b: u32) u32 {                                     │
│       return a + b;  // Computed when program runs                 │
│   }                                                                  │
│                                                                      │
│   pub fn main() void {                                              │
│       const x = add(5, 3);  // 8 computed at runtime               │
│   }                                                                  │
│                                                                      │
│ ─────────────────────────────────────────────────────────────────── │
│                                                                      │
│ COMPTIME: Code runs during compilation                              │
│                                                                      │
│   fn add(a: u32, b: u32) u32 {                                     │
│       return a + b;                                                 │
│   }                                                                  │
│                                                                      │
│   pub fn main() void {                                              │
│       const x = comptime add(5, 3);  // 8 computed by COMPILER     │
│   }                                                                  │
│                                                                      │
│   The compiled program just has "const x = 8" - no add() call!     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### What Can Run at Comptime?

```
┌─────────────────────────────────────────────────────────────────────┐
│ COMPTIME CAPABILITIES                                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ ✓ CAN do at comptime:                                              │
│   ─────────────────────                                             │
│   • Arithmetic: comptime { 5 + 3 }                                 │
│   • Function calls: comptime { factorial(10) }                     │
│   • Loops: comptime { for (items) |item| ... }                     │
│   • Conditionals: comptime { if (x) a else b }                     │
│   • String operations: comptime { "hello" ++ " world" }            │
│   • Type manipulation: comptime { @TypeOf(x) }                     │
│   • Building data structures: comptime { makeArray() }             │
│                                                                      │
│ ✗ CANNOT do at comptime:                                           │
│   ─────────────────────                                             │
│   • Read files from disk                                            │
│   • Network operations                                              │
│   • User input                                                      │
│   • Anything that depends on runtime state                         │
│   • Call external C functions                                       │
│   • Access runtime memory addresses                                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### How Sema Evaluates Comptime

When Sema sees comptime code, it actually **executes** it:

```
┌─────────────────────────────────────────────────────────────────────┐
│ COMPTIME EVALUATION EXAMPLE                                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Source code:                                                        │
│                                                                      │
│   const factorial = comptime blk: {                                │
│       var result: u64 = 1;                                         │
│       var i: u64 = 1;                                              │
│       while (i <= 10) : (i += 1) {                                 │
│           result *= i;                                              │
│       }                                                              │
│       break :blk result;                                           │
│   };                                                                 │
│                                                                      │
│ What Sema does:                                                     │
│                                                                      │
│   1. Sees "comptime" block                                         │
│   2. EXECUTES the code (like an interpreter):                      │
│      - result = 1, i = 1                                           │
│      - Loop: result = 1, i = 2                                     │
│      - Loop: result = 2, i = 3                                     │
│      - Loop: result = 6, i = 4                                     │
│      - ... continues ...                                            │
│      - Loop: result = 3628800, i = 11                              │
│      - Loop ends (11 > 10)                                         │
│   3. Returns value: 3628800                                        │
│                                                                      │
│ What ends up in the compiled program:                              │
│                                                                      │
│   const factorial = 3628800;   // Just the result!                 │
│                                                                      │
│ No loop, no multiplication - just the precomputed answer.          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Branch Quota: Preventing Infinite Loops

What if comptime code has an infinite loop? Sema has protection:

```
┌─────────────────────────────────────────────────────────────────────┐
│ BRANCH QUOTA                                                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ The problem:                                                        │
│                                                                      │
│   const x = comptime blk: {                                        │
│       while (true) {}    // Infinite loop!                         │
│       break :blk 0;      // Never reached                          │
│   };                                                                 │
│                                                                      │
│   Without protection, the compiler would hang forever.             │
│                                                                      │
│ The solution: Branch Quota                                          │
│                                                                      │
│   Sema counts every branch (loop iteration, if, etc.)              │
│   Default limit: 1000 branches                                      │
│                                                                      │
│   comptime {                                                        │
│       var i: u32 = 0;                                              │
│       while (i < 2000) : (i += 1) {  // 2000 iterations            │
│           // ...                                                    │
│       }                                                              │
│   }                                                                  │
│                                                                      │
│   Result:                                                           │
│   error: evaluation exceeded 1000 backwards branches               │
│   note: use @setEvalBranchQuota() to raise limit                   │
│                                                                      │
│ To allow more iterations:                                           │
│                                                                      │
│   comptime {                                                        │
│       @setEvalBranchQuota(10000);  // Raise limit                  │
│       // ... now can do 10000 branches                             │
│   }                                                                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 4: What is Type Coercion?

### The Problem: Types Don't Always Match

Sometimes you have a value of one type but need another type:

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE COERCION PROBLEM                                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ fn takesU64(x: u64) void { ... }                                   │
│                                                                      │
│ const value: u32 = 42;                                             │
│ takesU64(value);   // ERROR? value is u32, function wants u64!    │
│                                                                      │
│ Should this be an error?                                            │
│                                                                      │
│ • Strict view: YES! Types must match exactly.                      │
│ • Practical view: NO! u32 fits perfectly in u64, it's safe.       │
│                                                                      │
│ Zig takes the practical view with SAFE coercions.                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Safe vs Unsafe Coercions

```
┌─────────────────────────────────────────────────────────────────────┐
│ COERCION RULES                                                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ SAFE (Implicit - Sema does automatically):                         │
│ ────────────────────────────────────────────                        │
│                                                                      │
│   u32 → u64         ✓ Widening (32 bits → 64 bits, no data loss)  │
│   i16 → i32         ✓ Widening                                     │
│   u8  → u32         ✓ Widening                                     │
│   *T  → *const T    ✓ Adding const (more restrictive)             │
│   T   → ?T          ✓ Value to optional                            │
│   *[N]T → []T       ✓ Array pointer to slice                       │
│                                                                      │
│ UNSAFE (Must be explicit - you need @intCast, etc.):               │
│ ─────────────────────────────────────────────────────               │
│                                                                      │
│   u64 → u32         ✗ Narrowing (might lose data!)                 │
│   i32 → u32         ✗ Signed to unsigned (negative becomes huge!) │
│   f64 → u32         ✗ Float to int (loses decimal)                │
│   *const T → *T     ✗ Removing const (dangerous!)                  │
│                                                                      │
│ For unsafe conversions, you must be explicit:                      │
│                                                                      │
│   const big: u64 = 1000;                                           │
│   const small: u32 = @intCast(big);  // You're taking responsibility
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### How Sema Does Coercion

```
┌─────────────────────────────────────────────────────────────────────┐
│ COERCION WALKTHROUGH                                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Code: fn foo(x: u64) void { ... }                                  │
│       const val: u32 = 42;                                         │
│       foo(val);                                                     │
│                                                                      │
│ Step 1: Sema analyzes foo(val)                                     │
│         → Parameter type expected: u64                              │
│         → Argument type provided: u32                               │
│                                                                      │
│ Step 2: Types don't match! Try coercion.                           │
│         → Is u32 → u64 safe?                                       │
│         → u32 is 32 bits, u64 is 64 bits                          │
│         → 32 < 64, so this is widening                             │
│         → YES, safe to coerce!                                     │
│                                                                      │
│ Step 3: Insert coercion                                            │
│         → Original: foo(val)                                       │
│         → With coercion: foo(@intCast(val))  // Compiler adds this│
│                                                                      │
│ Step 4: Generate AIR                                               │
│         → AIR includes the widening instruction                    │
│                                                                      │
│ The programmer writes: foo(val)                                    │
│ The compiler generates: load val, widen to u64, call foo          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Peer Type Resolution

When Sema needs to find a common type:

```
┌─────────────────────────────────────────────────────────────────────┐
│ PEER TYPE RESOLUTION                                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Problem: What type is the result of `if (cond) a else b`?          │
│                                                                      │
│ Example 1:                                                          │
│   const a: u8 = 10;                                                │
│   const b: u16 = 20;                                               │
│   const result = if (cond) a else b;                               │
│                                                                      │
│   → a is u8, b is u16                                              │
│   → Peer type = u16 (can hold both u8 and u16 values)             │
│   → result is u16                                                   │
│                                                                      │
│ Example 2:                                                          │
│   const a: i32 = -5;                                               │
│   const b: u32 = 10;                                               │
│   const result = if (cond) a else b;                               │
│                                                                      │
│   → a is i32 (signed), b is u32 (unsigned)                        │
│   → Peer type = i64 (can hold both i32 range and u32 range)       │
│   → result is i64                                                   │
│                                                                      │
│ Example 3:                                                          │
│   const a: u32 = 10;                                               │
│   const b: []const u8 = "hello";                                   │
│   const result = if (cond) a else b;                               │
│                                                                      │
│   → a is u32, b is string                                          │
│   → NO peer type exists!                                           │
│   → ERROR: incompatible types                                      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 5: What Are Generics?

### The Problem: Code Duplication

Without generics, you'd write the same code multiple times:

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE CODE DUPLICATION PROBLEM                                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Without generics:                                                   │
│                                                                      │
│   fn maxU32(a: u32, b: u32) u32 {                                  │
│       return if (a > b) a else b;                                  │
│   }                                                                  │
│                                                                      │
│   fn maxI32(a: i32, b: i32) i32 {                                  │
│       return if (a > b) a else b;                                  │
│   }                                                                  │
│                                                                      │
│   fn maxU64(a: u64, b: u64) u64 {                                  │
│       return if (a > b) a else b;                                  │
│   }                                                                  │
│                                                                      │
│   fn maxF32(a: f32, b: f32) f32 {                                  │
│       return if (a > b) a else b;                                  │
│   }                                                                  │
│                                                                      │
│   // Same logic repeated for EVERY type!                           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### The Solution: Generic Functions

Write it once, use it with any type:

```
┌─────────────────────────────────────────────────────────────────────┐
│ GENERIC SOLUTION                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ With generics (Zig style):                                          │
│                                                                      │
│   fn max(comptime T: type, a: T, b: T) T {                         │
│       return if (a > b) a else b;                                  │
│   }                                                                  │
│                                                                      │
│ Usage:                                                               │
│                                                                      │
│   max(u32, 5, 10)      → returns 10 (u32)                          │
│   max(i32, -5, 3)      → returns 3 (i32)                           │
│   max(f64, 1.5, 2.5)   → returns 2.5 (f64)                         │
│                                                                      │
│ One function, infinite types!                                       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### How Sema Handles Generics (Instantiation)

```
┌─────────────────────────────────────────────────────────────────────┐
│ GENERIC INSTANTIATION                                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ When you call: max(u32, 5, 10)                                     │
│                                                                      │
│ Step 1: Sema sees the call                                         │
│         → Function: max                                             │
│         → First argument: u32 (this is a TYPE, not a value)        │
│         → Second argument: 5                                        │
│         → Third argument: 10                                        │
│                                                                      │
│ Step 2: Sema creates a "specialized" version                       │
│         → Take the generic function body                           │
│         → Replace every "T" with "u32"                             │
│         → Type-check this specialized version                      │
│                                                                      │
│ Step 3: The specialized function                                   │
│                                                                      │
│   // What Sema actually analyzes:                                  │
│   fn max_u32(a: u32, b: u32) u32 {                                 │
│       return if (a > b) a else b;                                  │
│   }                                                                  │
│                                                                      │
│ Step 4: Cache the instantiation                                    │
│         → If max(u32, ...) is called again, reuse this version    │
│         → Don't re-analyze!                                        │
│                                                                      │
│ If you also call max(f64, 1.5, 2.5):                              │
│         → Sema creates ANOTHER specialized version for f64        │
│         → Now there are TWO versions in the compiled code          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Generics Can Fail Per-Instantiation

```
┌─────────────────────────────────────────────────────────────────────┐
│ PER-INSTANTIATION ERRORS                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ fn max(comptime T: type, a: T, b: T) T {                           │
│     return if (a > b) a else b;   // Uses > operator               │
│ }                                                                    │
│                                                                      │
│ max(u32, 5, 10)      ✓ Works! u32 supports >                       │
│ max(f64, 1.5, 2.5)   ✓ Works! f64 supports >                       │
│ max(bool, true, false) ✗ ERROR! bool doesn't support >            │
│                                                                      │
│ The error only happens when you TRY to use it with bool.           │
│ The generic function itself is fine.                                │
│                                                                      │
│ Error message:                                                      │
│   error: operator > not defined for type 'bool'                    │
│    --> src/main.zig:2:23                                           │
│     |                                                               │
│   2 |     return if (a > b) a else b;                              │
│     |                   ^                                           │
│   note: called from here:                                          │
│    --> src/main.zig:6:5                                            │
│     |                                                               │
│   6 |     max(bool, true, false)                                   │
│     |     ^^^                                                       │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 6: Safety Checks

### What Are Safety Checks?

Zig inserts checks to catch bugs at runtime:

```
┌─────────────────────────────────────────────────────────────────────┐
│ SAFETY CHECKS                                                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ You write:                                                          │
│                                                                      │
│   fn getElement(arr: []u32, index: usize) u32 {                    │
│       return arr[index];                                            │
│   }                                                                  │
│                                                                      │
│ What Sema generates (in safe mode):                                │
│                                                                      │
│   fn getElement(arr: []u32, index: usize) u32 {                    │
│       // Safety check inserted by Sema:                            │
│       if (index >= arr.len) {                                      │
│           @panic("index out of bounds");                           │
│       }                                                              │
│       return arr[index];                                            │
│   }                                                                  │
│                                                                      │
│ This catches bugs that would otherwise cause memory corruption!    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Types of Safety Checks

```
┌─────────────────────────────────────────────────────────────────────┐
│ SAFETY CHECK TYPES                                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ 1. BOUNDS CHECKS (array/slice access)                              │
│    ─────────────────────────────────────                           │
│    arr[i]           → Check: i < arr.len                           │
│    slice[5..10]     → Check: 10 <= slice.len                       │
│                                                                      │
│ 2. NULL CHECKS (optional unwrapping)                               │
│    ─────────────────────────────────────                           │
│    optional.?       → Check: optional != null                      │
│    ptr.*            → Check: ptr is valid                          │
│                                                                      │
│ 3. OVERFLOW CHECKS (arithmetic)                                    │
│    ─────────────────────────────────────                           │
│    a + b            → Check: result fits in type                   │
│    a * b            → Check: no overflow                           │
│    a - b            → Check: no underflow (for unsigned)           │
│                                                                      │
│ 4. ALIGNMENT CHECKS (pointer casting)                              │
│    ─────────────────────────────────────                           │
│    @ptrCast(ptr)    → Check: alignment is correct                  │
│                                                                      │
│ 5. UNREACHABLE CHECKS                                              │
│    ─────────────────────────────────────                           │
│    unreachable      → Panic if reached                             │
│    else => unreachable (in switch)                                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Safe Mode vs Release Mode

```
┌─────────────────────────────────────────────────────────────────────┐
│ BUILD MODES                                                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Debug (default):                                                    │
│   ✓ All safety checks enabled                                      │
│   ✓ No optimizations                                               │
│   → Catches bugs, slow                                              │
│                                                                      │
│ ReleaseSafe:                                                        │
│   ✓ All safety checks enabled                                      │
│   ✓ Optimizations enabled                                          │
│   → Catches bugs, medium speed                                      │
│                                                                      │
│ ReleaseFast:                                                        │
│   ✗ Safety checks DISABLED                                         │
│   ✓ Maximum optimizations                                          │
│   → Maximum speed, but undefined behavior if bugs exist            │
│                                                                      │
│ ReleaseSmall:                                                       │
│   ✗ Safety checks DISABLED                                         │
│   ✓ Optimizations for size                                         │
│   → Smallest binary, same risks as ReleaseFast                    │
│                                                                      │
│ You can also control per-scope:                                    │
│                                                                      │
│   @setRuntimeSafety(false);  // Disable for this scope             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 7: The InternPool

### The Problem: Duplicate Types

Types are compared frequently. Without optimization:

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE DUPLICATE TYPE PROBLEM                                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Code:                                                                │
│   const a: u32 = 5;                                                │
│   const b: u32 = 10;                                               │
│   const c: u32 = a + b;                                            │
│                                                                      │
│ Without interning (wasteful):                                       │
│                                                                      │
│   a.type = Type{ .tag = .int, .bits = 32, .signed = false }       │
│   b.type = Type{ .tag = .int, .bits = 32, .signed = false }       │
│   c.type = Type{ .tag = .int, .bits = 32, .signed = false }       │
│                                                                      │
│   Three separate allocations for THE SAME type!                    │
│                                                                      │
│ To compare types:                                                   │
│   a.type == b.type?                                                │
│   → Must compare every field: tag, bits, signed...                 │
│   → Slow!                                                           │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### The Solution: Intern Pool

Store each unique type/value ONCE, refer to it by index:

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE INTERN POOL SOLUTION                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ InternPool (shared storage):                                        │
│                                                                      │
│   ┌───────┬────────────────────────────────────────────────────┐   │
│   │ Index │ Value                                               │   │
│   ├───────┼────────────────────────────────────────────────────┤   │
│   │   0   │ Type{ .tag = .void }                               │   │
│   │   1   │ Type{ .tag = .bool }                               │   │
│   │   2   │ Type{ .tag = .int, .bits = 8, .signed = false }   │   │  // u8
│   │   3   │ Type{ .tag = .int, .bits = 16, .signed = false }  │   │  // u16
│   │   4   │ Type{ .tag = .int, .bits = 32, .signed = false }  │   │  // u32
│   │   5   │ Type{ .tag = .int, .bits = 32, .signed = true }   │   │  // i32
│   │  ...  │ ...                                                 │   │
│   └───────┴────────────────────────────────────────────────────┘   │
│                                                                      │
│ Now variables just store the INDEX:                                 │
│                                                                      │
│   a.type = 4   // Points to u32 in the pool                        │
│   b.type = 4   // Points to SAME u32                               │
│   c.type = 4   // Points to SAME u32                               │
│                                                                      │
│ To compare types:                                                   │
│   a.type == b.type?                                                │
│   → 4 == 4?                                                        │
│   → YES! (just compare two integers)                               │
│   → FAST!                                                           │
│                                                                      │
│ Benefits:                                                            │
│   • Type comparison is just integer comparison (O(1))              │
│   • Memory saved by not duplicating identical types                │
│   • Cache-friendly (types stored contiguously)                     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Values Are Interned Too

```
┌─────────────────────────────────────────────────────────────────────┐
│ VALUE INTERNING                                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Comptime values are also interned:                                  │
│                                                                      │
│   const x = 42;                                                     │
│   const y = 42;                                                     │
│   const z = 42;                                                     │
│                                                                      │
│ InternPool:                                                         │
│   ┌───────┬────────────────────────────────────────────────────┐   │
│   │  100  │ Value{ .int = 42, .type = comptime_int }           │   │
│   └───────┴────────────────────────────────────────────────────┘   │
│                                                                      │
│   x.value = 100                                                     │
│   y.value = 100   // Same index!                                   │
│   z.value = 100   // Same index!                                   │
│                                                                      │
│ String literals too:                                                │
│                                                                      │
│   const a = "hello";                                               │
│   const b = "hello";                                               │
│                                                                      │
│   Both point to the SAME interned string!                          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 8: From ZIR to AIR

### The Transformation

Sema transforms untyped ZIR into typed AIR:

```
┌─────────────────────────────────────────────────────────────────────┐
│ ZIR → AIR TRANSFORMATION                                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ ZIR (input to Sema):                                               │
│   Untyped, doesn't know sizes, doesn't know validity               │
│                                                                      │
│   %1 = param(0)              // Some parameter                     │
│   %2 = param(1)              // Another parameter                  │
│   %3 = add(%1, %2)           // Add them (somehow?)                │
│   %4 = ret(%3)               // Return something                   │
│                                                                      │
│                        ↓ SEMA ↓                                     │
│                                                                      │
│ AIR (output from Sema):                                            │
│   Fully typed, sized, validated                                     │
│                                                                      │
│   %1 = arg(0, type=u32)      // Parameter 0 is u32                │
│   %2 = arg(1, type=u32)      // Parameter 1 is u32                │
│   %3 = add_u32(%1, %2)       // Add two u32s, result is u32       │
│   %4 = ret_u32(%3)           // Return a u32                       │
│                                                                      │
│ The AIR knows:                                                      │
│   ✓ Exact types of everything                                      │
│   ✓ Exact sizes in bytes                                           │
│   ✓ Which specific machine operations to use                       │
│   ✓ All operations have been validated                             │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Complete Example

```
┌─────────────────────────────────────────────────────────────────────┐
│ COMPLETE SEMA WALKTHROUGH                                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Source code:                                                        │
│                                                                      │
│   fn add(a: u32, b: u32) u32 {                                     │
│       return a + b;                                                 │
│   }                                                                  │
│                                                                      │
│ ─────────────────────────────────────────────────────────────────── │
│                                                                      │
│ ZIR (from AstGen):                                                  │
│                                                                      │
│   %0 = func_decl("add", ...)                                       │
│   %1 = block {                                                      │
│       %2 = param(0)                                                │
│       %3 = param(1)                                                │
│       %4 = add(%2, %3)                                             │
│       %5 = ret(%4)                                                 │
│   }                                                                  │
│                                                                      │
│ ─────────────────────────────────────────────────────────────────── │
│                                                                      │
│ Sema processing:                                                    │
│                                                                      │
│ Step 1: Analyze function signature                                  │
│         → Parameter "a": look up type annotation "u32"             │
│         → Resolve "u32": it's the 32-bit unsigned integer type    │
│         → Parameter "b": same, it's u32                            │
│         → Return type: look up "u32", same type                    │
│         → Create function type: fn(u32, u32) u32                   │
│                                                                      │
│ Step 2: Analyze %2 = param(0)                                      │
│         → This is the first parameter                               │
│         → From step 1, we know it's type u32                       │
│         → AIR: %2 has type u32                                     │
│                                                                      │
│ Step 3: Analyze %3 = param(1)                                      │
│         → Second parameter, type u32                                │
│         → AIR: %3 has type u32                                     │
│                                                                      │
│ Step 4: Analyze %4 = add(%2, %3)                                   │
│         → Left operand: %2 is u32                                  │
│         → Right operand: %3 is u32                                 │
│         → Can u32 be added to u32? YES                            │
│         → Result type: u32                                         │
│         → AIR: %4 = add(u32, %2, %3), type = u32                  │
│                                                                      │
│ Step 5: Analyze %5 = ret(%4)                                       │
│         → Return value: %4 is u32                                  │
│         → Expected return type: u32 (from function signature)      │
│         → Do they match? YES                                       │
│         → AIR: %5 = ret(%4)                                        │
│                                                                      │
│ Step 6: All checks passed!                                         │
│         → Generate AIR for this function                           │
│                                                                      │
│ ─────────────────────────────────────────────────────────────────── │
│                                                                      │
│ AIR output:                                                         │
│                                                                      │
│   function "add": fn(u32, u32) u32 {                               │
│       %0 = arg(0)          // type: u32                            │
│       %1 = arg(1)          // type: u32                            │
│       %2 = add(%0, %1)     // type: u32                            │
│       ret %2                                                        │
│   }                                                                  │
│                                                                      │
│ Ready for code generation!                                          │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 9: Error Messages

### Good Error Messages Are Critical

Sema produces detailed, helpful error messages:

```
┌─────────────────────────────────────────────────────────────────────┐
│ ERROR MESSAGE QUALITY                                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ BAD error (unhelpful):                                              │
│                                                                      │
│   error: type mismatch                                              │
│                                                                      │
│   (What types? Where? What did I do wrong?)                        │
│                                                                      │
│ ─────────────────────────────────────────────────────────────────── │
│                                                                      │
│ GOOD error (Zig style):                                             │
│                                                                      │
│   error: expected type 'u32', found 'i32'                          │
│    --> src/main.zig:10:15                                          │
│     |                                                               │
│   9 |  fn foo(x: u32) void {}                                      │
│     |            --- expected due to this parameter type           │
│  10 |  foo(my_signed_value);                                       │
│     |      ^^^^^^^^^^^^^^^ expected 'u32', found 'i32'             │
│     |                                                               │
│   note: signed-to-unsigned conversion is not implicit              │
│   note: consider using @intCast if this is intentional             │
│                                                                      │
│ This tells you:                                                     │
│   ✓ Exactly what's wrong                                           │
│   ✓ Exactly where it is                                            │
│   ✓ Why the expected type is what it is                            │
│   ✓ How to fix it                                                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### How Sema Tracks Source Locations

```
┌─────────────────────────────────────────────────────────────────────┐
│ SOURCE LOCATION CHAIN                                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Every AIR instruction traces back to source:                       │
│                                                                      │
│   AIR instruction                                                   │
│        ↓                                                            │
│   ZIR instruction (has src_node)                                   │
│        ↓                                                            │
│   AST node (has main_token)                                        │
│        ↓                                                            │
│   Token (has start position)                                       │
│        ↓                                                            │
│   Source file + line + column                                      │
│                                                                      │
│ When an error occurs, Sema walks this chain to build the message.  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Part 10: The Big Picture

### Where Sema Fits

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE COMPILATION PIPELINE                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                      SOURCE CODE                             │  │
│   │         fn add(a: u32, b: u32) u32 { return a+b; }          │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            │                                        │
│                            ▼                                        │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                       TOKENIZER                              │  │
│   │  Breaks into tokens                                          │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            │                                        │
│                            ▼                                        │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                        PARSER                                │  │
│   │  Builds AST (checks syntax)                                  │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            │                                        │
│                            ▼                                        │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                        ASTGEN                                │  │
│   │  Converts to ZIR (untyped instructions)                     │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            │                                        │
│                            ▼                                        │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                         SEMA                  ◄── YOU ARE HERE│
│   │                                                              │  │
│   │  • Type checking & inference                                 │  │
│   │  • Comptime evaluation                                       │  │
│   │  • Generic instantiation                                     │  │
│   │  • Coercion insertion                                        │  │
│   │  • Safety check generation                                   │  │
│   │  • Error detection & reporting                               │  │
│   │                                                              │  │
│   │  Input: ZIR (untyped)                                       │  │
│   │  Output: AIR (fully typed)                                  │  │
│   └────────────────────────┬────────────────────────────────────┘  │
│                            │                                        │
│                            ▼                                        │
│   ┌─────────────────────────────────────────────────────────────┐  │
│   │                       CODEGEN                                │  │
│   │  Generates machine code from AIR                            │  │
│   └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Summary: What Sema Does

```
┌─────────────────────────────────────────────────────────────────────┐
│ SEMA KEY POINTS                                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ 1. TYPE CHECKING                                                    │
│    Verifies every operation uses compatible types                  │
│    Catches type mismatches before runtime                          │
│                                                                      │
│ 2. TYPE INFERENCE                                                   │
│    Figures out types you didn't explicitly specify                 │
│    Uses context to determine the right type                        │
│                                                                      │
│ 3. COMPTIME EVALUATION                                              │
│    Actually executes compile-time code                             │
│    Replaces comptime expressions with their results                │
│                                                                      │
│ 4. GENERIC INSTANTIATION                                            │
│    Creates specialized versions of generic functions               │
│    Type-checks each instantiation separately                       │
│                                                                      │
│ 5. COERCION                                                         │
│    Automatically converts between compatible types                 │
│    Inserts necessary conversion instructions                       │
│                                                                      │
│ 6. SAFETY CHECKS                                                    │
│    Inserts runtime checks for bounds, overflow, null, etc.        │
│    Can be disabled for maximum performance                         │
│                                                                      │
│ 7. INTERNING                                                        │
│    Deduplicates types and values                                   │
│    Makes type comparison fast (just compare indices)               │
│                                                                      │
│ 8. ERROR REPORTING                                                  │
│    Produces detailed, actionable error messages                    │
│    Points to exact source locations                                │
│                                                                      │
│ OUTPUT: AIR (Analyzed Intermediate Representation)                 │
│   → Fully typed                                                    │
│   → All operations validated                                       │
│   → Ready for code generation                                      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Conclusion

Sema is the heart of the Zig compiler. It's where:

- **Types are verified** - ensuring your code is type-safe
- **Comptime runs** - executing code at compile time for metaprogramming
- **Generics work** - creating specialized versions for each type combination
- **Safety is inserted** - catching bugs before they cause damage
- **Errors are reported** - with helpful, precise messages

At 37,763 lines, Sema is by far the largest component of the compiler, and for good reason - semantic analysis is where the real intelligence lives.

The output of Sema is **AIR** (Analyzed Intermediate Representation), which is fully typed and validated. In the next article, we'll explore AIR and how it gets turned into actual machine code.

---

**Previous**: [Part 4: ZIR Generation](./04-zir-generation.md)
**Next**: [Part 6: AIR and Code Generation](./06-air-codegen.md)

**Series Index**:
1. [Bootstrap Process](./01-bootstrap-process.md)
2. [Tokenizer](./02-tokenizer.md)
3. [Parser and AST](./03-parser-ast.md)
4. [ZIR Generation](./04-zir-generation.md)
5. **Semantic Analysis** (this article)
6. [AIR and Code Generation](./06-air-codegen.md)
7. [Linking](./07-linking.md)
