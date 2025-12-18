---
title: "6.4: Extensions"
weight: 4
---

# Lesson 6.4: Where to Go From Here

Ideas for extending your mini compiler.

---

## Goal

Explore ways to add features and deepen your compiler knowledge.

---

## Easy Extensions

### 1. More Operators

Add comparison operators:
```
fn isPositive(x: i32) bool {
    return x > 0;
}
```

Changes needed:
- Lexer: Add `>`, `<`, `>=`, `<=`, `==`, `!=` tokens
- Parser: Add comparison expressions (lower precedence than arithmetic)
- Sema: Return type is `bool` for comparisons
- Codegen: Generate C comparison operators

### 2. Boolean Literals

```
const flag: bool = true;
```

Already have `bool` type - just add:
- Lexer: `true` and `false` keywords
- Parser: Parse as literals
- ZIR/AIR: `const_bool` instruction

### 3. Modulo Operator

```
const remainder: i32 = 10 % 3;  // = 1
```

Just add `%` everywhere you have `*` and `/`.

---

## Medium Extensions

### 4. If Statements

```
fn abs(x: i32) i32 {
    if x < 0 {
        return -x;
    }
    return x;
}
```

Changes needed:
- Parser: `if condition { statements }`
- AST: `IfStmt { condition, then_block, else_block? }`
- Codegen: Generate C `if` statements

### 5. While Loops

```
fn sum(n: i32) i32 {
    var total: i32 = 0;
    var i: i32 = 0;
    while i <= n {
        total = total + i;
        i = i + 1;
    }
    return total;
}
```

Need:
- Parser: `while` statement
- Variable mutation: `var` vs `const`
- Codegen: C `while` loops

### 6. Function Calls

```
fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn main() i32 {
    return add(3, 5);
}
```

Changes:
- Parser: Call expressions `name(args)`
- ZIR: `call` instruction
- Sema: Check argument types match parameters
- Codegen: Generate function calls

---

## Harder Extensions

### 7. Arrays

```
fn first(arr: [5]i32) i32 {
    return arr[0];
}
```

Requires:
- Array types in type system
- Index expressions
- Bounds checking (optional)
- Memory layout decisions

### 8. Structs

```
struct Point {
    x: i32,
    y: i32,
}

fn distance(p: Point) i32 {
    return p.x * p.x + p.y * p.y;
}
```

Requires:
- Struct type definitions
- Field access
- Memory layout
- Type checking for field access

### 9. Pointers

```
fn increment(ptr: *i32) void {
    *ptr = *ptr + 1;
}
```

Opens up:
- Manual memory management
- Mutable references
- Unsafe operations

---

## Alternative Backends

### Generate LLVM IR

Instead of C, generate LLVM IR:
```llvm
define i32 @main() {
    ret i32 42
}
```

Benefits:
- Access to LLVM optimizations
- Multiple target architectures
- More control over code generation

### Generate WebAssembly

Compile to `.wasm`:
```wat
(module
  (func $main (result i32)
    i32.const 42
    return))
```

Benefits:
- Run in browsers
- Sandboxed execution
- Growing ecosystem

### Generate Bytecode + Interpreter

Create your own VM:
```
PUSH 42
RET
```

Benefits:
- Full control
- Good for scripting languages
- Easier debugging

---

## Optimizations

### Constant Folding

Compute constants at compile time:
```
const x: i32 = 3 + 5;  // Compute at compile time
// Generates: const x: i32 = 8;
```

### Dead Code Elimination

Remove unreachable code:
```
fn foo() i32 {
    return 1;
    const x: i32 = 2;  // Never executed, remove it
}
```

### Inlining

Replace function calls with function body:
```
fn double(x: i32) i32 { return x * 2; }
fn main() i32 { return double(5); }
// After inlining:
fn main() i32 { return 5 * 2; }
```

---

## Learning Resources

### Books
- "Crafting Interpreters" by Robert Nystrom (free online)
- "Engineering a Compiler" by Cooper & Torczon
- "Modern Compiler Implementation in C" by Appel

### Online
- LLVM Tutorial: llvm.org/docs/tutorial/
- Writing a C Compiler series by Nora Sandler
- Zig compiler source code (what this tutorial is based on)

### Projects to Study
- Zig compiler (self-hosted)
- Rust compiler (rustc)
- Go compiler (gc)
- TinyCC (small C compiler)

---

## Congratulations!

You've built a working compiler that:
- Lexes source code into tokens
- Parses into an abstract syntax tree
- Generates intermediate representation
- Performs semantic analysis
- Produces executable code

This is the same architecture used by production compilers like GCC, Clang, Zig, and Rust. The concepts you've learned scale up to real-world compilers.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│                      🎉 YOU BUILT A COMPILER! 🎉                            │
│                                                                              │
│   Source → Lexer → Parser → ZIR → Sema → Codegen → Executable              │
│                                                                              │
│   ~800 lines of code                                                         │
│   Language-agnostic principles                                               │
│   Production-quality architecture                                            │
│                                                                              │
│   Now go build something amazing!                                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Thank You

Thank you for following this tutorial. Building a compiler is one of the most rewarding projects in programming. You now understand how programming languages work at a fundamental level.

Happy compiling!
