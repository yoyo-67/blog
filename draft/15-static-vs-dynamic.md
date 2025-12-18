---
title: "Zig Compiler Internals Part 15: Static vs Dynamic Languages"
date: 2025-12-18
---

# Zig Compiler Internals Part 15: Static vs Dynamic Languages

*How does type checking at compile time vs runtime change everything about compiler design?*

---

## Introduction

One of the most fundamental decisions in programming language design is when to check types: at compile time or at runtime. This choice ripples through every aspect of compiler architecture, from parsing to code generation.

In this article, we'll explore:
- What makes a language "static" or "dynamic" from a compiler perspective
- How compiler architectures differ between the two approaches
- How types are represented in memory at runtime
- The performance implications of each approach
- Gradual typing as a middle ground
- How Zig approaches static typing with comptime flexibility

Understanding this distinction is essential for compiler writers, as it fundamentally shapes how you build every stage of your compiler.

---

## Part 1: What Makes a Language Static or Dynamic?

### The Core Distinction

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    STATIC vs DYNAMIC: THE CORE QUESTION                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   When is the type of a value determined?                                    │
│                                                                              │
│   STATIC TYPING                      DYNAMIC TYPING                          │
│   ──────────────                     ──────────────                          │
│   Types checked at COMPILE TIME      Types checked at RUNTIME                │
│   Before the program runs            While the program runs                  │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                                                                     │   │
│   │   COMPILE TIME                      RUNTIME                         │   │
│   │        │                                │                           │   │
│   │        ▼                                ▼                           │   │
│   │   ┌─────────┐                      ┌─────────┐                      │   │
│   │   │  Type   │                      │  Type   │                      │   │
│   │   │ Checker │                      │ Checker │                      │   │
│   │   └─────────┘                      └─────────┘                      │   │
│   │        │                                │                           │   │
│   │   Static Typing                    Dynamic Typing                   │   │
│   │   (Zig, C, Rust)                   (Python, JS, Ruby)               │   │
│   │                                                                     │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Static Typing Example

```zig
// Zig - Statically Typed
fn add(a: i32, b: i32) i32 {
    return a + b;
}

// This is caught at COMPILE TIME:
// const result = add("hello", 5);  // Error: expected i32, got []const u8
```

The compiler knows `a` and `b` must be `i32`. If you pass a string, you get a compile-time error before the program ever runs.

### Dynamic Typing Example

```python
# Python - Dynamically Typed
def add(a, b):
    return a + b

# This runs fine:
result1 = add(3, 5)      # 8
result2 = add("hi", "!") # "hi!"

# This crashes at RUNTIME:
result3 = add("hi", 5)   # TypeError: can only concatenate str (not "int") to str
```

Python doesn't know the types of `a` and `b` until the function is called. Type errors become runtime exceptions.

### The Type Checking Spectrum

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    THE TYPE CHECKING SPECTRUM                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ◄─────────────────────────────────────────────────────────────────────►   │
│                                                                              │
│   FULLY STATIC            GRADUAL              FULLY DYNAMIC                 │
│                                                                              │
│   ┌─────────┐         ┌─────────────┐         ┌─────────────┐               │
│   │ Zig     │         │ TypeScript  │         │ Python      │               │
│   │ C       │         │ Python+mypy │         │ JavaScript  │               │
│   │ Rust    │         │ Dart        │         │ Ruby        │               │
│   │ Java    │         │ C# dynamic  │         │ Lua         │               │
│   │ Haskell │         │ Typed Racket│         │ Lisp        │               │
│   └─────────┘         └─────────────┘         └─────────────┘               │
│                                                                              │
│   All types known       Mix of static         Types only known              │
│   before runtime        and dynamic           at runtime                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Key Differences Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    STATIC vs DYNAMIC SUMMARY                                 │
├────────────────────┬───────────────────────┬─────────────────────────────────┤
│ Aspect             │ Static Typing         │ Dynamic Typing                  │
├────────────────────┼───────────────────────┼─────────────────────────────────┤
│ Type checking      │ Compile time          │ Runtime                         │
│ Type errors        │ Compile errors        │ Runtime exceptions              │
│ Variable types     │ Fixed at declaration  │ Can change anytime              │
│ Type annotations   │ Required/inferred     │ Optional (often none)           │
│ Type info at run   │ Erased                │ Preserved                       │
│ Performance        │ Generally faster      │ Overhead from checks            │
│ Flexibility        │ Less flexible         │ More flexible                   │
│ IDE support        │ Better (types known)  │ Limited (types unknown)         │
└────────────────────┴───────────────────────┴─────────────────────────────────┘
```

---

## Part 2: Compiler Architecture Differences

The static vs dynamic choice fundamentally shapes compiler architecture:

### Static Language Compiler Pipeline

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    STATIC LANGUAGE COMPILER                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Source Code                                                                │
│       │                                                                      │
│       ▼                                                                      │
│   ┌─────────────────┐                                                       │
│   │     LEXER       │  Tokenize                                             │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐                                                       │
│   │     PARSER      │  Build AST with type annotations                      │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐                                                       │
│   │  TYPE CHECKER   │  ◄── HEAVY WORK HERE                                  │
│   │     (Sema)      │  Resolve all types, check constraints                 │
│   └────────┬────────┘  Catch errors BEFORE running                          │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐                                                       │
│   │   TYPED IR      │  Types attached to every operation                    │
│   │   (AIR/LLVM)    │  add_i32, mul_f64, etc.                               │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐                                                       │
│   │    CODEGEN      │  Generate optimized machine code                      │
│   │                 │  Types guide optimizations                            │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ▼                                                                 │
│   Native Binary (no type info, no runtime checks)                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Dynamic Language Compiler Pipeline

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    DYNAMIC LANGUAGE COMPILER                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Source Code                                                                │
│       │                                                                      │
│       ▼                                                                      │
│   ┌─────────────────┐                                                       │
│   │     LEXER       │  Tokenize                                             │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐                                                       │
│   │     PARSER      │  Build AST (no type annotations)                      │
│   └────────┬────────┘  Variables are just names                             │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐                                                       │
│   │ BYTECODE GEN    │  ◄── LIGHTER THAN STATIC                              │
│   │                 │  No type checking, just structure                     │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐                                                       │
│   │ UNTYPED IR      │  Generic operations                                   │
│   │ (Bytecode)      │  ADD (works on any type)                              │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ▼                                                                 │
│   ┌──────────────────────────────────────────────────────────────┐          │
│   │                      RUNTIME                                 │          │
│   │  ┌─────────────────┐                                        │          │
│   │  │   INTERPRETER   │  Execute bytecode                      │          │
│   │  │   or JIT        │  Check types at each operation         │          │
│   │  └─────────────────┘                                        │          │
│   │          │                                                   │          │
│   │          ▼                                                   │          │
│   │  ┌─────────────────┐                                        │          │
│   │  │  TYPE DISPATCH  │  ◄── HEAVY WORK HERE                   │          │
│   │  │                 │  What type is this value?              │          │
│   │  │                 │  Which add() to call?                  │          │
│   │  └─────────────────┘                                        │          │
│   └──────────────────────────────────────────────────────────────┘          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Where the Work Happens

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    COMPILE TIME vs RUNTIME WORK                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   STATIC LANGUAGES                  DYNAMIC LANGUAGES                        │
│   ────────────────                  ─────────────────                        │
│                                                                              │
│   Compile Time:                     Compile Time:                            │
│   ┌───────────────────────┐        ┌───────────────────────┐                │
│   │ ████████████████████ │ Heavy  │ ██████               │ Light           │
│   │ • Parse               │        │ • Parse              │                 │
│   │ • Type check          │        │ • Generate bytecode  │                 │
│   │ • Optimize            │        │                      │                 │
│   │ • Generate native     │        │                      │                 │
│   └───────────────────────┘        └───────────────────────┘                │
│                                                                              │
│   Runtime:                          Runtime:                                 │
│   ┌───────────────────────┐        ┌───────────────────────┐                │
│   │ ██                   │ Light  │ ████████████████████ │ Heavy           │
│   │ • Execute native code│        │ • Interpret bytecode │                 │
│   │                      │        │ • Type check each op │                 │
│   │                      │        │ • Dynamic dispatch   │                 │
│   │                      │        │ • Possible JIT       │                 │
│   └───────────────────────┘        └───────────────────────┘                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Information Available at Each Stage

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    INFORMATION FLOW                                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Static Compiler:                                                           │
│   ────────────────                                                           │
│   Parser → "x is declared as i32"                                            │
│   Sema   → "x + y is i32 + i32 = i32"                                       │
│   IR     → "add_i32(%0, %1)"                                                │
│   Binary → (raw addition instruction, no type info)                          │
│                                                                              │
│   Dynamic Compiler:                                                          │
│   ─────────────────                                                          │
│   Parser → "x is a variable"                                                 │
│   IR     → "ADD(x, y)"  (type unknown)                                      │
│   Runtime→ "x is currently 5 (int), y is currently 3 (int)"                 │
│          → "call int_add(5, 3)"                                             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 3: Type Representation

How do static and dynamic languages represent values in memory?

### Static Language: Types Erased

In static languages, type information exists only at compile time:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    STATIC TYPE REPRESENTATION                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Zig Code:                                                                  │
│   const x: i32 = 42;                                                         │
│   const y: f64 = 3.14;                                                       │
│                                                                              │
│   Memory at Runtime:                                                         │
│                                                                              │
│   x (i32):                         y (f64):                                  │
│   ┌────────────────────────┐      ┌────────────────────────────────────────┐│
│   │ 0x0000002A (42)        │      │ 0x40091EB851EB851F (3.14)              ││
│   └────────────────────────┘      └────────────────────────────────────────┘│
│   4 bytes, raw value              8 bytes, raw value                        │
│                                                                              │
│   NO type tag!                    NO type tag!                               │
│   Compiler KNOWS the type         At runtime, it's just bytes               │
│                                                                              │
│   This is why:                                                               │
│   • You can't ask "what type is x?" at runtime                              │
│   • Memory is compact (no overhead)                                          │
│   • Operations are direct (no dispatch)                                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Dynamic Language: Types Preserved

In dynamic languages, every value carries type information:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    DYNAMIC TYPE REPRESENTATION                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Python Code:                                                               │
│   x = 42                                                                     │
│   y = 3.14                                                                   │
│                                                                              │
│   Memory at Runtime (simplified):                                            │
│                                                                              │
│   x (PyObject*):                                                             │
│   ┌────────────────────────────────────────────────────────────────────┐    │
│   │ ┌──────────────┬──────────────┬────────────────────────┐          │    │
│   │ │ type_ptr ────┼────► int     │ ref_count: 1           │          │    │
│   │ ├──────────────┴──────────────┼────────────────────────┤          │    │
│   │ │              value: 42                               │          │    │
│   │ └──────────────────────────────────────────────────────┘          │    │
│   └────────────────────────────────────────────────────────────────────┘    │
│   24+ bytes (type pointer + refcount + value + padding)                      │
│                                                                              │
│   y (PyObject*):                                                             │
│   ┌────────────────────────────────────────────────────────────────────┐    │
│   │ ┌──────────────┬──────────────┬────────────────────────┐          │    │
│   │ │ type_ptr ────┼────► float   │ ref_count: 1           │          │    │
│   │ ├──────────────┴──────────────┼────────────────────────┤          │    │
│   │ │              value: 3.14                             │          │    │
│   │ └──────────────────────────────────────────────────────┘          │    │
│   └────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│   Every value knows its type!                                                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Tagged Values (Alternative Representation)

Some dynamic languages use "tagged pointers" or "NaN boxing":

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    TAGGED VALUE REPRESENTATION                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   NaN Boxing (used by LuaJIT, some JS engines):                              │
│   ────────────────────────────────────────────                               │
│   Encode type in the NaN bits of a 64-bit float                              │
│                                                                              │
│   ┌────────────────────────────────────────────────────────────────────┐    │
│   │ 64 bits                                                            │    │
│   │ ┌─────┬───────────────────────────────────────────────────────┐   │    │
│   │ │ Tag │                    Payload                            │   │    │
│   │ │ 16  │                    48 bits                            │   │    │
│   │ └─────┴───────────────────────────────────────────────────────┘   │    │
│   └────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│   Tag values:                                                                │
│   0x0000 = double (use all 64 bits as float)                                │
│   0xFFF1 = integer (payload is 48-bit int)                                  │
│   0xFFF2 = pointer (payload is object address)                              │
│   0xFFF3 = boolean (payload is 0 or 1)                                      │
│   0xFFF4 = nil                                                              │
│                                                                              │
│   Benefits:                                                                  │
│   • Compact: only 8 bytes per value                                          │
│   • No indirection for primitives                                            │
│   • Type check is just bitmask                                               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Memory Comparison

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    MEMORY OVERHEAD COMPARISON                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Storing an array of 1000 integers:                                         │
│                                                                              │
│   STATIC (Zig/C):                                                            │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │ [i32; 1000]                                                         │   │
│   │ 4 bytes × 1000 = 4,000 bytes                                        │   │
│   │ Contiguous, cache-friendly                                           │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   DYNAMIC (Python list):                                                     │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │ [PyObject*; 1000] → each points to:                                 │   │
│   │   PyObject header (16 bytes) + int value (8 bytes)                  │   │
│   │ 8 × 1000 (pointers) + 24 × 1000 (objects) = 32,000 bytes           │   │
│   │ Plus: memory fragmentation, cache misses                             │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   8× more memory for the same data!                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 4: Type Checking Implementation

How do compilers actually check types?

### Static Type Checking (Zig's Sema)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    STATIC TYPE CHECKING                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Code:                                                                      │
│   fn add(a: i32, b: i32) i32 {                                              │
│       return a + b;                                                          │
│   }                                                                          │
│   const result = add(5, 3);                                                  │
│                                                                              │
│   Sema Process:                                                              │
│   ─────────────                                                              │
│                                                                              │
│   1. Process function declaration:                                           │
│      add: fn(i32, i32) i32                                                  │
│      Store in symbol table                                                   │
│                                                                              │
│   2. Process function body:                                                  │
│      a: i32, b: i32 (from params)                                           │
│      a + b → i32 + i32 → i32 ✓                                             │
│      return i32, expected i32 ✓                                             │
│                                                                              │
│   3. Process call site:                                                      │
│      add(5, 3)                                                               │
│      5 → i32 (literal inference)                                            │
│      3 → i32 (literal inference)                                            │
│      Check: fn(i32, i32) called with (i32, i32) ✓                          │
│      Result type: i32                                                        │
│                                                                              │
│   All checks happen BEFORE any code runs!                                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Type Checking Algorithm

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    TYPE CHECKING ALGORITHM                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   function typeCheck(expr, env):                                             │
│       switch expr.kind:                                                      │
│                                                                              │
│           case NumberLiteral:                                                │
│               return inferNumericType(expr.value)                            │
│                                                                              │
│           case Identifier:                                                   │
│               type = env.lookup(expr.name)                                   │
│               if type is null:                                               │
│                   error("undefined: " + expr.name)                           │
│               return type                                                    │
│                                                                              │
│           case BinaryOp:                                                     │
│               leftType = typeCheck(expr.left, env)                           │
│               rightType = typeCheck(expr.right, env)                         │
│               return checkBinaryOp(expr.op, leftType, rightType)             │
│                                                                              │
│           case FnCall:                                                       │
│               fnType = typeCheck(expr.fn, env)                               │
│               argTypes = [typeCheck(arg, env) for arg in expr.args]         │
│               checkArgsMatch(fnType.params, argTypes)                        │
│               return fnType.returnType                                       │
│                                                                              │
│           case VarDecl:                                                      │
│               valueType = typeCheck(expr.value, env)                         │
│               if expr.typeAnnotation:                                        │
│                   checkCompatible(expr.typeAnnotation, valueType)            │
│               env.define(expr.name, valueType)                               │
│               return void                                                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Dynamic Type Dispatch

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    DYNAMIC TYPE DISPATCH                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Python Code:                                                               │
│   x + y                                                                      │
│                                                                              │
│   Runtime Process:                                                           │
│   ───────────────                                                            │
│                                                                              │
│   1. Get type of x: type(x) → <class 'int'>                                 │
│   2. Get type of y: type(y) → <class 'str'>                                 │
│   3. Look up __add__ method on int: int.__add__                             │
│   4. Call int.__add__(x, y)                                                  │
│   5. int.__add__ returns NotImplemented (can't add str)                      │
│   6. Try reverse: str.__radd__(y, x)                                        │
│   7. Also fails → raise TypeError                                            │
│                                                                              │
│   This happens for EVERY + operation at runtime!                             │
│                                                                              │
│   Pseudocode:                                                                │
│   ───────────                                                                │
│   function binary_add(x, y):                                                 │
│       x_type = get_type(x)                                                   │
│       add_method = lookup_method(x_type, "__add__")                          │
│       result = call(add_method, x, y)                                        │
│       if result == NotImplemented:                                           │
│           y_type = get_type(y)                                               │
│           radd_method = lookup_method(y_type, "__radd__")                    │
│           result = call(radd_method, y, x)                                   │
│       if result == NotImplemented:                                           │
│           raise TypeError(...)                                               │
│       return result                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Error Detection Comparison

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    ERROR DETECTION                                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   STATIC LANGUAGE (Zig):                                                     │
│   ──────────────────────                                                     │
│                                                                              │
│   const x: i32 = "hello";                                                    │
│                                                                              │
│   $ zig build                                                                │
│   error: expected type 'i32', found '[]const u8'                            │
│   const x: i32 = "hello";                                                    │
│                   ^~~~~~~                                                    │
│                                                                              │
│   Caught at compile time. Program never runs with the bug.                   │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   DYNAMIC LANGUAGE (Python):                                                 │
│   ──────────────────────────                                                 │
│                                                                              │
│   def process(data):                                                         │
│       return data + 1                                                        │
│                                                                              │
│   # Somewhere else, months later...                                          │
│   process("hello")                                                           │
│                                                                              │
│   $ python app.py                                                            │
│   Traceback (most recent call last):                                         │
│     File "app.py", line 42, in process                                       │
│       return data + 1                                                        │
│   TypeError: can only concatenate str (not "int") to str                     │
│                                                                              │
│   Caught at runtime, possibly in production!                                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 5: Performance Implications

Why are statically typed languages generally faster?

### The Performance Gap

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    STATIC vs DYNAMIC PERFORMANCE                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Operation: Add two integers                                                │
│                                                                              │
│   STATIC (Zig/C):                   DYNAMIC (Python):                        │
│   ────────────────                  ─────────────────                        │
│                                                                              │
│   mov eax, [a]    ; 1 cycle         LOAD_FAST 'a'                           │
│   add eax, [b]    ; 1 cycle           ↓                                     │
│   mov [result], eax                 type_check(a)      ; is it int?         │
│                                       ↓                                      │
│   Total: ~2-3 cycles                LOAD_FAST 'b'                           │
│                                       ↓                                      │
│                                     type_check(b)      ; is it int?         │
│                                       ↓                                      │
│                                     lookup __add__     ; find method        │
│                                       ↓                                      │
│                                     call int_add       ; finally add        │
│                                       ↓                                      │
│                                     create PyObject    ; box result         │
│                                       ↓                                      │
│                                     Total: ~100+ cycles                      │
│                                                                              │
│   50-100× difference for primitive operations!                               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Sources of Overhead

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    DYNAMIC TYPING OVERHEAD                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. TYPE CHECKING                                                           │
│      Every operation must check types                                        │
│      if (typeof x === 'number' && typeof y === 'number')                    │
│                                                                              │
│   2. DYNAMIC DISPATCH                                                        │
│      Method lookup through vtables or dictionaries                           │
│      obj.__dict__['method_name']                                            │
│                                                                              │
│   3. BOXING/UNBOXING                                                         │
│      Primitives wrapped in objects                                           │
│      42 → PyLong object → extract 42 → compute → new PyLong                 │
│                                                                              │
│   4. MEMORY INDIRECTION                                                      │
│      Everything is a pointer                                                 │
│      Cache misses, pointer chasing                                           │
│                                                                              │
│   5. ALLOCATION                                                              │
│      New objects for results                                                 │
│      1 + 2 creates new integer object                                        │
│                                                                              │
│   6. GARBAGE COLLECTION                                                      │
│      Track all those objects                                                 │
│      Reference counting or tracing                                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### JIT Compilation: Bridging the Gap

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    JIT COMPILATION                                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   JIT = Just-In-Time Compilation                                             │
│   Compile hot code paths at runtime with observed type information           │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                                                                     │   │
│   │   First execution:     Observe types      JIT Compile               │   │
│   │   ────────────────     ─────────────      ───────────               │   │
│   │                                                                     │   │
│   │   for i in range(n):   "i is always int"  mov eax, [i]             │   │
│   │       x = i + 1        "x is always int"  add eax, 1               │   │
│   │                                           mov [x], eax              │   │
│   │                                                                     │   │
│   │   Interpret slowly     Learn types        Run native code           │   │
│   │   (100+ cycles/op)                        (~2 cycles/op)            │   │
│   │                                                                     │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   With guards for type changes:                                              │
│   ─────────────────────────────                                              │
│   if type(i) != int:                                                         │
│       deoptimize()  // fall back to interpreter                             │
│   // fast path here                                                          │
│                                                                              │
│   Examples: V8 (JavaScript), PyPy (Python), LuaJIT (Lua)                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Benchmark Reality

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    TYPICAL PERFORMANCE RATIOS                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Task: Compute-intensive numeric work                                       │
│                                                                              │
│   Language        │ Relative Speed │ Notes                                   │
│   ────────────────┼────────────────┼────────────────────────────────────────│
│   C / Zig         │ 1.0×           │ Baseline (native, no overhead)         │
│   Rust            │ 1.0-1.1×       │ Same as C with safety checks           │
│   Java (JIT)      │ 1.0-2×         │ JIT can match native                   │
│   JavaScript (V8) │ 1.5-5×         │ Good JIT, still has overhead           │
│   PyPy            │ 5-10×          │ Python with JIT                        │
│   Python (CPython)│ 50-100×        │ No JIT, pure interpretation            │
│   Ruby            │ 30-50×         │ Similar to CPython                     │
│                                                                              │
│   Note: For I/O bound work, the gap is much smaller!                         │
│   A slow language waiting for disk/network is still mostly waiting.         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 6: The Gradual Typing Middle Ground

What if you want the flexibility of dynamic typing with some static guarantees?

### Gradual Typing Concept

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    GRADUAL TYPING                                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Gradual typing = Mix static and dynamic in the same program                │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                                                                     │   │
│   │   def process(data):          # Dynamic: no type annotation        │   │
│   │       return data.strip()                                           │   │
│   │                                                                     │   │
│   │   def process_typed(data: str) -> str:  # Static: annotated        │   │
│   │       return data.strip()                                           │   │
│   │                                                                     │   │
│   │   # Mix freely:                                                     │   │
│   │   result = process(get_data())           # No checking             │   │
│   │   result = process_typed(get_data())     # Checked at boundary     │   │
│   │                                                                     │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   Key idea: Typed and untyped code can coexist                               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### TypeScript Example

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    TYPESCRIPT: GRADUAL TYPING FOR JS                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   TypeScript adds static types to JavaScript:                                │
│                                                                              │
│   // Fully typed                                                             │
│   function add(a: number, b: number): number {                               │
│       return a + b;                                                          │
│   }                                                                          │
│                                                                              │
│   // Using 'any' - escape hatch to dynamic                                   │
│   function process(data: any): any {                                         │
│       return data.whatever();  // No checking!                               │
│   }                                                                          │
│                                                                              │
│   // Gradual migration:                                                      │
│   // 1. Start with .js files (all dynamic)                                   │
│   // 2. Rename to .ts                                                        │
│   // 3. Add types incrementally                                              │
│   // 4. Enable strict mode when ready                                        │
│                                                                              │
│   Compiler Pipeline:                                                         │
│   ┌────────────┐     ┌────────────┐     ┌────────────┐                      │
│   │ TypeScript │ ──► │   Type     │ ──► │ JavaScript │                      │
│   │   Source   │     │  Checker   │     │   Output   │                      │
│   └────────────┘     └────────────┘     └────────────┘                      │
│                                                                              │
│   Types are ERASED at runtime - JavaScript has no types!                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Python Type Hints

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    PYTHON TYPE HINTS                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Python 3.5+ supports type annotations:                                     │
│                                                                              │
│   from typing import List, Optional                                          │
│                                                                              │
│   def greet(name: str) -> str:                                              │
│       return f"Hello, {name}"                                                │
│                                                                              │
│   def process(items: List[int]) -> Optional[int]:                           │
│       if items:                                                              │
│           return sum(items)                                                  │
│       return None                                                            │
│                                                                              │
│   IMPORTANT: Python IGNORES these at runtime!                                │
│   They're just hints for external tools.                                     │
│                                                                              │
│   External Type Checkers:                                                    │
│   ┌────────────┐                                                            │
│   │   mypy     │  Static analysis tool                                      │
│   │   pyright  │  Microsoft's fast type checker                             │
│   │   pyre     │  Facebook's type checker                                   │
│   └────────────┘                                                            │
│                                                                              │
│   $ mypy program.py                                                          │
│   program.py:10: error: Argument 1 to "greet" has incompatible type "int"   │
│                                                                              │
│   The Python interpreter still runs code with type errors!                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### How Gradual Typing Works in Compilers

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    GRADUAL TYPING IMPLEMENTATION                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Key concept: The "any" or "unknown" type                                   │
│                                                                              │
│   Type System:                                                               │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                                                                     │   │
│   │   any ←───────────────────────────────────────────────────► any    │   │
│   │    ↑                                                           ↑    │   │
│   │    │  "any" is compatible with everything                      │    │   │
│   │    │                                                           │    │   │
│   │   int ───────────X───────────────────────X──────────────── string   │   │
│   │    ↑             │                       │                     ↑    │   │
│   │    │         (not compatible)        (not compatible)          │    │   │
│   │    │                                                           │    │   │
│   │   Typed code checks types normally                              │    │   │
│   │   "any" acts as escape hatch                                   │    │   │
│   │                                                                     │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   Boundary checking:                                                         │
│   ──────────────────                                                         │
│                                                                              │
│   function typed(x: number) { ... }                                         │
│   function untyped(x) { typed(x); }  // Insert runtime check here!         │
│                                                                              │
│   Compiled to:                                                               │
│   function untyped(x) {                                                      │
│       if (typeof x !== 'number') throw TypeError(...);                      │
│       typed(x);                                                              │
│   }                                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Benefits and Limitations

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    GRADUAL TYPING TRADE-OFFS                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   BENEFITS:                                                                  │
│   ─────────                                                                  │
│   ✓ Migrate existing codebases incrementally                                 │
│   ✓ Add types where they help most (APIs, complex logic)                    │
│   ✓ Keep flexibility where needed (scripting, prototyping)                  │
│   ✓ Better IDE support in typed portions                                    │
│   ✓ Documentation through types                                             │
│                                                                              │
│   LIMITATIONS:                                                               │
│   ────────────                                                               │
│   ✗ Partial guarantees - untyped code can break typed code                  │
│   ✗ Runtime checks at boundaries add overhead                               │
│   ✗ "any" can spread, undermining type safety                               │
│   ✗ Can't optimize as well as fully static                                  │
│   ✗ Two languages to understand (typed and untyped idioms)                  │
│                                                                              │
│   Best for:                                                                  │
│   • Large existing dynamic codebases                                         │
│   • Teams transitioning to types                                             │
│   • Interop with untyped libraries                                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 7: Zig's Approach

How does Zig handle static typing, and what makes it special?

### Zig's Type System

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    ZIG'S STATIC TYPE SYSTEM                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Zig is FULLY statically typed:                                             │
│   • Every variable has a known type at compile time                          │
│   • No "any" or dynamic types                                                │
│   • No runtime type information (in safe code)                               │
│   • Types are erased in the final binary                                     │
│                                                                              │
│   // Every type is explicit or inferred at compile time                      │
│   const x: i32 = 42;           // Explicit                                   │
│   const y = @as(i32, 42);      // Explicit cast                              │
│   const z = 42;                // Inferred as comptime_int                   │
│                                                                              │
│   // No implicit conversions that lose information                           │
│   const a: i32 = 1000;                                                       │
│   const b: i8 = a;             // ERROR: narrowing conversion                │
│   const c: i8 = @intCast(a);   // OK: explicit, runtime checked             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Comptime: Static Typing with Dynamic Flexibility

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    ZIG'S COMPTIME                                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Zig's comptime provides dynamic-like flexibility at compile time:          │
│                                                                              │
│   // Types as first-class values (at comptime)                               │
│   fn Matrix(comptime T: type, comptime rows: usize, comptime cols: usize)    │
│       type                                                                   │
│   {                                                                          │
│       return struct {                                                        │
│           data: [rows][cols]T,                                               │
│                                                                              │
│           pub fn get(self: @This(), r: usize, c: usize) T {                 │
│               return self.data[r][c];                                        │
│           }                                                                  │
│       };                                                                     │
│   }                                                                          │
│                                                                              │
│   const Mat3x3 = Matrix(f32, 3, 3);  // Generate type at compile time       │
│   var m: Mat3x3 = undefined;                                                 │
│                                                                              │
│   This is like:                                                              │
│   • C++ templates                                                            │
│   • Rust const generics                                                      │
│   • But with a full interpreter at compile time!                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Comptime vs Dynamic: Same Flexibility, Different Time

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    COMPTIME vs DYNAMIC                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Python (Dynamic):                   Zig (Comptime):                        │
│   ─────────────────                   ───────────────                        │
│                                                                              │
│   # Type decided at runtime           // Type decided at compile time        │
│   def make_list(item_type):           fn makeArray(comptime T: type)         │
│       if item_type == int:                type                               │
│           return [0, 0, 0]            {                                      │
│       else:                               return [3]T;                       │
│           return ["", "", ""]         }                                      │
│                                                                              │
│   # Runs every execution              // Runs once during compilation        │
│   lst = make_list(int)                const arr = makeArray(i32);            │
│                                                                              │
│   ───────────────────────────────────────────────────────────────────────   │
│                                                                              │
│   Same expressive power!                                                     │
│   But Zig version:                                                           │
│   • Generates specialized code per type                                      │
│   • No runtime overhead                                                      │
│   • Errors caught at compile time                                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Union Types and Tagged Unions

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    ZIG TAGGED UNIONS                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   For cases where you need runtime type dispatch:                            │
│                                                                              │
│   const Value = union(enum) {                                                │
│       int: i64,                                                              │
│       float: f64,                                                            │
│       string: []const u8,                                                    │
│       none,                                                                  │
│   };                                                                         │
│                                                                              │
│   fn process(v: Value) void {                                                │
│       switch (v) {                                                           │
│           .int => |i| std.debug.print("int: {}\n", .{i}),                   │
│           .float => |f| std.debug.print("float: {}\n", .{f}),               │
│           .string => |s| std.debug.print("string: {s}\n", .{s}),            │
│           .none => std.debug.print("none\n", .{}),                          │
│       }                                                                      │
│   }                                                                          │
│                                                                              │
│   This is like dynamic typing, but:                                          │
│   • Explicit (you choose when to use it)                                    │
│   • Exhaustive (compiler checks all cases)                                   │
│   • Efficient (single byte tag, no pointer indirection)                     │
│   • Type-safe (can't access wrong variant)                                  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### How Sema Implements This

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    ZIG'S SEMA TYPE CHECKING                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Zig's Sema (semantic analyzer) does the heavy lifting:                     │
│                                                                              │
│   ZIR Input:                        Sema Processing:                         │
│   ──────────                        ────────────────                         │
│                                                                              │
│   %0 = int(42)                      → Type: comptime_int                    │
│   %1 = decl("x", %0, i32)           → Coerce comptime_int to i32           │
│                                       → Validate: 42 fits in i32 ✓          │
│                                       → Type of x: i32                      │
│                                                                              │
│   %2 = decl_ref("x")                → Lookup x in scope: found             │
│                                       → Type: i32                           │
│                                                                              │
│   %3 = decl_ref("y")                → Lookup y in scope: NOT FOUND         │
│                                       → ERROR: undefined identifier 'y'     │
│                                                                              │
│   %4 = add(%2, %0)                  → Types: i32 + comptime_int            │
│                                       → Coerce comptime_int to i32         │
│                                       → Result type: i32                    │
│                                                                              │
│   AIR Output:                                                                │
│   ───────────                                                                │
│   %0 = const_i32(42)                                                        │
│   %1 = local_set(0, %0)             // x at slot 0                          │
│   %2 = local_get(0)                                                         │
│   %3 = const_i32(42)                                                        │
│   %4 = add_i32(%2, %3)                                                      │
│                                                                              │
│   Every operation now has a concrete type!                                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 8: Implementing a Type Checker

Let's build a simple type checker to understand the concepts:

### Type Representation

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    TYPE DATA STRUCTURES                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   // Core type representation                                                │
│   Type = union {                                                             │
│       Primitive: enum { I32, I64, F32, F64, Bool, Void },                   │
│       Pointer: *Type,                                                        │
│       Array: struct { element: *Type, len: usize },                         │
│       Function: struct { params: []Type, ret: *Type },                      │
│       Struct: struct { name: string, fields: []Field },                     │
│       Unknown,  // For type inference                                        │
│       Error,    // Propagate type errors                                     │
│   }                                                                          │
│                                                                              │
│   Field = struct {                                                           │
│       name: string,                                                          │
│       type: Type,                                                            │
│   }                                                                          │
│                                                                              │
│   // Symbol table entry                                                      │
│   Symbol = struct {                                                          │
│       name: string,                                                          │
│       type: Type,                                                            │
│       kind: enum { Variable, Function, Type },                              │
│   }                                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Type Checker Implementation

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    TYPE CHECKER CORE                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   struct TypeChecker {                                                       │
│       symbols: SymbolTable,                                                  │
│       errors: []Error,                                                       │
│                                                                              │
│       fn check(self, expr: *Expr) Type {                                    │
│           switch (expr.*) {                                                  │
│                                                                              │
│               .IntLiteral => {                                               │
│                   return .{ .Primitive = .I32 };                            │
│               },                                                             │
│                                                                              │
│               .Identifier => |name| {                                        │
│                   if (self.symbols.lookup(name)) |sym| {                    │
│                       return sym.type;                                       │
│                   } else {                                                   │
│                       self.errors.append(.{                                 │
│                           .msg = "undefined: " ++ name                      │
│                       });                                                    │
│                       return .Error;                                         │
│                   }                                                          │
│               },                                                             │
│                                                                              │
│               .BinaryOp => |op| {                                           │
│                   const left_type = self.check(op.left);                    │
│                   const right_type = self.check(op.right);                  │
│                   return self.checkBinaryOp(op.kind, left_type, right_type);│
│               },                                                             │
│                                                                              │
│               .FnCall => |call| {                                           │
│                   const fn_type = self.check(call.func);                    │
│                   // ... check arguments match parameters                   │
│                   return fn_type.Function.ret.*;                            │
│               },                                                             │
│           }                                                                  │
│       }                                                                      │
│   }                                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Type Coercion Rules

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    TYPE COERCION                                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   fn coerce(from: Type, to: Type) ?Type {                                   │
│       // Same type - always ok                                               │
│       if (from == to) return to;                                            │
│                                                                              │
│       // Comptime int can become any integer type                           │
│       if (from == .ComptimeInt and to.isInteger()) {                        │
│           return to;                                                         │
│       }                                                                      │
│                                                                              │
│       // Pointer to array coerces to slice                                   │
│       if (from == .Pointer and from.child == .Array and                     │
│           to == .Slice and to.child == from.child.element) {                │
│           return to;                                                         │
│       }                                                                      │
│                                                                              │
│       // Integer widening (i8 -> i16 -> i32 -> i64)                         │
│       if (from.isInteger() and to.isInteger() and                           │
│           to.bitSize() >= from.bitSize() and                                │
│           to.isSigned() == from.isSigned()) {                               │
│           return to;                                                         │
│       }                                                                      │
│                                                                              │
│       // No valid coercion                                                   │
│       return null;                                                           │
│   }                                                                          │
│                                                                              │
│   // In type checker:                                                        │
│   if (coerce(actual_type, expected_type) == null) {                         │
│       error("type mismatch: expected {}, got {}", expected, actual);        │
│   }                                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Type Inference

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    TYPE INFERENCE                                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Type inference = figuring out types without explicit annotations           │
│                                                                              │
│   // Zig example:                                                            │
│   const x = 42;           // x: comptime_int (inferred)                      │
│   const y: i32 = x;       // Coerce comptime_int -> i32                     │
│   const z = y + 1;        // z: i32 (propagated from y)                     │
│                                                                              │
│   Algorithm (Hindley-Milner simplified):                                     │
│   ──────────────────────────────────────                                     │
│                                                                              │
│   1. Assign type variables to unknown types                                  │
│      let x = e   →   x: T1, e: T2, constraint: T1 = T2                      │
│                                                                              │
│   2. Generate constraints from expressions                                   │
│      e1 + e2     →   e1: T3, e2: T4, constraint: T3 = T4 = numeric         │
│                                                                              │
│   3. Unify constraints                                                       │
│      T1 = i32, T2 = i32   →   solved!                                       │
│      T1 = i32, T1 = str   →   error: conflicting types                      │
│                                                                              │
│   4. Substitute solutions                                                    │
│      Replace all T1 with i32 in the AST                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Complete Example

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    TYPE CHECKING EXAMPLE                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Source:                                                                    │
│   fn add(a: i32, b: i32) i32 {                                              │
│       return a + b;                                                          │
│   }                                                                          │
│   const result = add(1, 2);                                                  │
│                                                                              │
│   Type Checking Steps:                                                       │
│   ────────────────────                                                       │
│                                                                              │
│   1. Process function declaration:                                           │
│      symbols["add"] = Function { params: [i32, i32], ret: i32 }             │
│                                                                              │
│   2. Enter function scope:                                                   │
│      symbols["a"] = Variable { type: i32 }                                  │
│      symbols["b"] = Variable { type: i32 }                                  │
│                                                                              │
│   3. Check: a + b                                                            │
│      type(a) = i32                                                           │
│      type(b) = i32                                                           │
│      i32 + i32 = i32 ✓                                                      │
│                                                                              │
│   4. Check: return a + b                                                     │
│      return type = i32                                                       │
│      expected return = i32 ✓                                                │
│                                                                              │
│   5. Exit function scope                                                     │
│                                                                              │
│   6. Check: add(1, 2)                                                        │
│      type(add) = Function { params: [i32, i32], ret: i32 }                  │
│      type(1) = comptime_int, coerce to i32 ✓                                │
│      type(2) = comptime_int, coerce to i32 ✓                                │
│      result type = i32                                                       │
│                                                                              │
│   7. Check: const result = add(1, 2)                                         │
│      symbols["result"] = Variable { type: i32 }                             │
│                                                                              │
│   All types resolved!                                                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 9: Trade-offs and When to Choose

### When to Choose Static Typing

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    CHOOSE STATIC TYPING WHEN                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ✓ Performance is critical                                                  │
│     Systems programming, game engines, databases                             │
│                                                                              │
│   ✓ Large codebase with many developers                                      │
│     Types as documentation, refactoring safety                               │
│                                                                              │
│   ✓ Long-running production systems                                          │
│     Catch bugs at compile time, not 3 AM                                    │
│                                                                              │
│   ✓ API boundaries matter                                                    │
│     Clear contracts between components                                       │
│                                                                              │
│   ✓ IDE support is important                                                 │
│     Autocomplete, refactoring, navigation                                    │
│                                                                              │
│   Examples: Operating systems, compilers, game engines,                      │
│             databases, financial systems, embedded                           │
│                                                                              │
│   Languages: Zig, Rust, C, C++, Go, Java, C#                                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### When to Choose Dynamic Typing

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    CHOOSE DYNAMIC TYPING WHEN                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ✓ Rapid prototyping                                                        │
│     Explore ideas quickly without type ceremony                              │
│                                                                              │
│   ✓ Scripting and automation                                                 │
│     One-off scripts, glue code                                               │
│                                                                              │
│   ✓ Highly dynamic data                                                      │
│     JSON APIs, configuration, user-defined schemas                           │
│                                                                              │
│   ✓ Interactive development                                                  │
│     REPLs, notebooks, live coding                                            │
│                                                                              │
│   ✓ Metaprogramming                                                          │
│     Modifying code at runtime, DSLs                                          │
│                                                                              │
│   ✓ Small scripts with few contributors                                      │
│     Overhead of types not worth it                                           │
│                                                                              │
│   Examples: Data science, web scripting, shell automation,                   │
│             configuration, testing, rapid prototyping                        │
│                                                                              │
│   Languages: Python, JavaScript, Ruby, Lua, Lisp                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Modern Trends

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    INDUSTRY TRENDS                                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   The industry is moving toward MORE static typing:                          │
│                                                                              │
│   JavaScript → TypeScript                                                    │
│   • Microsoft created TypeScript                                             │
│   • Now used by majority of large JS projects                                │
│   • Angular, React, Vue all support it                                       │
│                                                                              │
│   Python → Type Hints + mypy                                                 │
│   • PEP 484 added type hints in Python 3.5                                  │
│   • Major libraries adding type annotations                                  │
│   • Google, Facebook, Microsoft use type checkers                           │
│                                                                              │
│   Ruby → Sorbet (Stripe's type checker)                                     │
│   • Stripe typed their entire Ruby codebase                                  │
│   • RBS standard for Ruby types                                              │
│                                                                              │
│   Why?                                                                       │
│   • Large codebases are hard to maintain without types                       │
│   • Refactoring dynamic code is scary                                        │
│   • Types catch bugs that tests miss                                         │
│   • IDE support dramatically improves productivity                           │
│                                                                              │
│   The sweet spot: gradual typing for existing code,                          │
│   full static typing for new projects.                                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 10: The Big Picture

### Summary Comparison

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    STATIC vs DYNAMIC: COMPLETE COMPARISON                    │
├─────────────────────┬────────────────────────┬───────────────────────────────┤
│ Aspect              │ Static Typing          │ Dynamic Typing                │
├─────────────────────┼────────────────────────┼───────────────────────────────┤
│ Type checking       │ Compile time           │ Runtime                       │
│ Errors found        │ Before running         │ During execution              │
│ Type annotations    │ Required/inferred      │ Optional                      │
│ Performance         │ Near-optimal           │ Overhead from checks          │
│ Memory use          │ Compact                │ Object wrappers               │
│ Flexibility         │ Constrained            │ Maximum                       │
│ Refactoring         │ Compiler-assisted      │ Risky without tests           │
│ IDE support         │ Excellent              │ Limited                       │
│ Learning curve      │ Steeper                │ Gentler                       │
│ Compile time        │ Longer                 │ Instant                       │
│ Metaprogramming     │ Limited/compile-time   │ Full runtime                  │
│ Interop             │ Explicit FFI           │ Often seamless                │
├─────────────────────┴────────────────────────┴───────────────────────────────┤
│                                                                              │
│ Neither is "better" - they're tools for different jobs.                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### The Compiler Writer's Perspective

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    FOR COMPILER WRITERS                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Building a STATIC language compiler:                                       │
│   ─────────────────────────────────────                                      │
│   • Invest heavily in the type checker (Sema)                               │
│   • Generate type-specific IR (add_i32, mul_f64)                            │
│   • Erase types in final output                                              │
│   • Can do aggressive optimizations                                          │
│   • Errors are compiler messages                                             │
│                                                                              │
│   Building a DYNAMIC language compiler:                                      │
│   ──────────────────────────────────────                                     │
│   • Simple frontend (no type checking)                                       │
│   • Generate type-agnostic bytecode                                          │
│   • Build a runtime with type dispatch                                       │
│   • Consider JIT for performance                                             │
│   • Errors are runtime exceptions                                            │
│                                                                              │
│   Building a GRADUALLY typed language:                                       │
│   ─────────────────────────────────────                                      │
│   • Support both typed and untyped code                                      │
│   • Insert runtime checks at boundaries                                      │
│   • Handle the "any" type specially                                          │
│   • Balance safety vs compatibility                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Key Takeaways

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    KEY TAKEAWAYS                                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. STATIC vs DYNAMIC is about WHEN types are checked                       │
│      Compile time (before running) vs runtime (during execution)             │
│                                                                              │
│   2. This choice SHAPES EVERYTHING                                           │
│      Compiler architecture, runtime design, performance, tooling             │
│                                                                              │
│   3. STATIC languages have work up front                                     │
│      Heavy compiler, light runtime, types erased                             │
│                                                                              │
│   4. DYNAMIC languages defer work                                            │
│      Light compiler, heavy runtime, types preserved                          │
│                                                                              │
│   5. GRADUAL typing is a PRAGMATIC middle ground                             │
│      For migrating existing code, not new projects                           │
│                                                                              │
│   6. ZIG shows COMPTIME as an alternative                                    │
│      Static typing with dynamic-like flexibility at compile time             │
│                                                                              │
│   7. The INDUSTRY is moving toward more static typing                        │
│      TypeScript, Python hints, Ruby Sorbet - types are winning               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Further Reading

### Books

- **"Types and Programming Languages"** by Benjamin C. Pierce
  The definitive academic text on type theory. Dense but comprehensive.

- **"Practical Foundations for Programming Languages"** by Robert Harper
  Another excellent academic treatment, available free online.

- **"Crafting Interpreters"** by Robert Nystrom
  Builds both a tree-walking interpreter (dynamic) and bytecode VM.

### Papers

- **"Gradual Typing for Functional Languages"** by Siek & Taha
  The original gradual typing paper.

- **"The Design and Implementation of Typed Scheme"**
  How to add types to a dynamic language.

### Type Systems to Study

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    TYPE SYSTEMS TO STUDY                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Language    │ Notable Features                                             │
│   ────────────┼───────────────────────────────────────────────────────────  │
│   Haskell     │ Strong inference, algebraic data types, typeclasses         │
│   Rust        │ Ownership, borrowing, lifetimes                             │
│   Zig         │ Comptime, no hidden control flow                            │
│   TypeScript  │ Structural typing, gradual, union/intersection              │
│   OCaml       │ ML-style inference, modules                                  │
│   Idris       │ Dependent types (types can depend on values)                │
│   Scala       │ Mix of OO and FP typing                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Conclusion

The static vs dynamic typing distinction is one of the most fundamental decisions in language design. It affects every aspect of your compiler:

- **Parser**: Does it need type annotations?
- **Semantic Analysis**: Does it type-check, or just validate structure?
- **IR**: Are operations type-specific or generic?
- **Runtime**: Does it need type dispatch machinery?
- **Performance**: Can you optimize knowing exact types?

Understanding this distinction helps you:
- Choose the right language for each project
- Understand why compilers are built the way they are
- Appreciate the trade-offs language designers make
- Build your own compilers with informed decisions

Static typing isn't "better" than dynamic typing—they're different tools for different jobs. The best compiler writers understand both approaches and can apply them appropriately.

---

## Navigation

← [Previous: Part 14 - Understanding Bytecode](../14-bytecode)

[Back to Series Index](../)
