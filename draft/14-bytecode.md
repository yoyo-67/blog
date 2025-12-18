---
title: "Zig Compiler Internals Part 14: Understanding Bytecode"
date: 2025-12-18
---

# Zig Compiler Internals Part 14: Understanding Bytecode

*What is bytecode and why do so many language implementations use it?*

---

## Introduction

You've likely heard the term "bytecode" in discussions about Java, Python, WebAssembly, or the Lua scripting language. But what exactly is bytecode, and why do so many language implementations choose this approach?

In this article, we'll explore:
- What bytecode is and how it differs from source code and machine code
- Why bytecode exists and what problems it solves
- The two major VM architectures: stack-based and register-based
- How bytecode instructions are designed and encoded
- Famous bytecode systems and how they compare
- How Zig's approach relates to bytecode concepts
- How to design and execute your own simple bytecode

Understanding bytecode gives you insight into how interpreted languages work, why they make certain trade-offs, and how compilation can happen in stages.

---

## Part 1: What is Bytecode?

Bytecode sits between human-readable source code and CPU-specific machine code:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    THE COMPILATION SPECTRUM                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   SOURCE CODE          BYTECODE              MACHINE CODE                    │
│   ─────────────        ────────              ────────────                    │
│   Human-readable       Portable binary       CPU-specific                    │
│   Text format          Compact encoding      Native instructions             │
│   Easy to edit         Platform-independent  Maximum performance             │
│                                                                              │
│   ┌───────────┐       ┌───────────┐        ┌───────────┐                    │
│   │ x = 1 + 2 │  ──>  │ PUSH 1    │  ──>   │ mov $1,%r1│                    │
│   │           │       │ PUSH 2    │        │ mov $2,%r2│                    │
│   │           │       │ ADD       │        │ add %r2,%r1                    │
│   │           │       │ STORE x   │        │ mov %r1,x │                    │
│   └───────────┘       └───────────┘        └───────────┘                    │
│                                                                              │
│   High-level           Intermediate          Low-level                       │
│   Abstraction          Representation        Native                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Key Characteristics of Bytecode

**1. Binary Format**
Unlike source code (text), bytecode is encoded in binary. Each instruction is typically one or more bytes, hence the name "bytecode."

**2. Portable**
Bytecode doesn't target a specific CPU architecture. The same `.class` file (Java) or `.pyc` file (Python) runs on any platform with the appropriate virtual machine.

**3. Compact**
Bytecode is much smaller than source code. Comments, whitespace, and verbose syntax are eliminated. Variable names become indices.

**4. Structured**
Bytecode has a regular, easy-to-parse format. A virtual machine can decode and execute it much faster than parsing source code repeatedly.

### Bytecode vs. Machine Code

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    BYTECODE vs MACHINE CODE                                  │
├────────────────────────────────┬─────────────────────────────────────────────┤
│          BYTECODE              │            MACHINE CODE                     │
├────────────────────────────────┼─────────────────────────────────────────────┤
│ Runs on virtual machine        │ Runs directly on CPU                        │
│ Platform independent           │ Platform specific (x86, ARM, etc.)          │
│ Needs interpreter or JIT       │ Executes natively                           │
│ Higher-level operations        │ Low-level CPU operations                    │
│ Designed for simplicity        │ Designed for hardware efficiency            │
│ Easy to instrument/debug       │ Hard to analyze at runtime                  │
└────────────────────────────────┴─────────────────────────────────────────────┘
```

---

## Part 2: Why Bytecode Exists

Why not compile directly to machine code, or just interpret source code? Bytecode solves several problems:

### Problem 1: Portability

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    THE PORTABILITY PROBLEM                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Without Bytecode:                                                          │
│   ─────────────────                                                          │
│                                                                              │
│   Source ──> x86 Binary      (for Windows/Linux x86)                         │
│          ──> ARM Binary      (for Mac M1/M2)                                 │
│          ──> RISC-V Binary   (for embedded)                                  │
│          ──> WASM            (for browsers)                                  │
│                                                                              │
│   Need N different compilers for N platforms!                                │
│                                                                              │
│   With Bytecode:                                                             │
│   ──────────────                                                             │
│                                                                              │
│   Source ──> Bytecode ──> VM(x86)                                            │
│                       ──> VM(ARM)                                            │
│                       ──> VM(RISC-V)                                         │
│                       ──> VM(WASM)                                           │
│                                                                              │
│   One compiler, N virtual machine implementations!                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

Java famously pioneered this with "write once, run anywhere" - compile once to bytecode, run on any JVM.

### Problem 2: Interpretation Performance

Interpreting source code directly is slow:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    SOURCE INTERPRETATION vs BYTECODE                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Interpreting Source (every execution):                                     │
│   ──────────────────────────────────────                                     │
│   1. Read characters from file                                               │
│   2. Tokenize (identify keywords, numbers, operators)                        │
│   3. Parse (build syntax tree)                                               │
│   4. Execute operations                                                      │
│                                                                              │
│   This happens EVERY time the code runs!                                     │
│                                                                              │
│   Interpreting Bytecode:                                                     │
│   ──────────────────────                                                     │
│   1. Read bytecode instruction (1-3 bytes)                                   │
│   2. Decode opcode                                                           │
│   3. Execute operation                                                       │
│                                                                              │
│   Much simpler! No parsing, no tokenizing.                                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Problem 3: Distribution Size

Bytecode is typically 5-10x smaller than source code:

```
Source:    function calculateTax(income, rate) { return income * rate; }
Bytecode:  05 00 01 02 03 04  (hypothetical: 6 bytes)
```

### Problem 4: Security and Sandboxing

A virtual machine can enforce security policies:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    VM SANDBOXING                                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Bytecode Program                                                           │
│        │                                                                     │
│        ▼                                                                     │
│   ┌─────────────────────────────────────────┐                               │
│   │           VIRTUAL MACHINE               │                               │
│   │  ┌─────────────────────────────────┐   │                               │
│   │  │    Security Policy Enforcer     │   │                               │
│   │  │  • Memory access bounds         │   │                               │
│   │  │  • No direct file system        │   │                               │
│   │  │  • No network without permission│   │                               │
│   │  │  • CPU time limits              │   │                               │
│   │  └─────────────────────────────────┘   │                               │
│   └─────────────────────────────────────────┘                               │
│        │                                                                     │
│        ▼                                                                     │
│   Operating System (protected from malicious code)                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 3: Stack-Based vs Register-Based VMs

There are two major architectural approaches to virtual machines:

### Stack-Based Virtual Machines

Stack machines use an implicit operand stack. Operations pop values, compute, and push results:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    STACK-BASED VM                                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Expression: 3 + 5 * 2                                                      │
│                                                                              │
│   Bytecode:        Stack State:                                              │
│   ─────────        ────────────                                              │
│                                                                              │
│   PUSH 3           [ 3 ]                                                     │
│   PUSH 5           [ 3, 5 ]                                                  │
│   PUSH 2           [ 3, 5, 2 ]                                               │
│   MUL              [ 3, 10 ]      (5 * 2 = 10)                               │
│   ADD              [ 13 ]         (3 + 10 = 13)                              │
│                                                                              │
│   Instructions don't name operands - they're implicit on the stack!          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Examples**: JVM (Java), CPython, CLR (.NET), WebAssembly

**Advantages**:
- Simple instruction encoding (no operand addresses)
- Easy to generate bytecode from expressions
- Small code size

**Disadvantages**:
- More instructions needed (explicit push/pop)
- Stack manipulation overhead
- Harder to optimize

### Register-Based Virtual Machines

Register machines explicitly name source and destination registers:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    REGISTER-BASED VM                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Expression: 3 + 5 * 2                                                      │
│                                                                              │
│   Bytecode:              Registers:                                          │
│   ─────────              ──────────                                          │
│                                                                              │
│   LOAD R0, 3             R0=3                                                │
│   LOAD R1, 5             R0=3, R1=5                                          │
│   LOAD R2, 2             R0=3, R1=5, R2=2                                    │
│   MUL R1, R1, R2         R0=3, R1=10, R2=2    (R1 = 5 * 2)                   │
│   ADD R0, R0, R1         R0=13, R1=10, R2=2   (R0 = 3 + 10)                  │
│                                                                              │
│   Instructions explicitly name their operands!                               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Examples**: Lua 5.0+, Dalvik (Android), LuaJIT

**Advantages**:
- Fewer instructions (combine operations)
- Easier to optimize (register allocation visible)
- Better for JIT compilation

**Disadvantages**:
- Larger instruction size (must encode register numbers)
- More complex instruction format

### Comparison

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    STACK vs REGISTER COMPARISON                              │
├───────────────────┬──────────────────────┬───────────────────────────────────┤
│    Aspect         │   Stack-Based        │   Register-Based                  │
├───────────────────┼──────────────────────┼───────────────────────────────────┤
│ Instruction Size  │ Small (1-3 bytes)    │ Larger (2-4 bytes)                │
│ Instruction Count │ More instructions    │ Fewer instructions                │
│ Code Size         │ Often smaller        │ Often larger                      │
│ Execution Speed   │ More memory traffic  │ Less memory traffic               │
│ Implementation    │ Simpler              │ More complex                      │
│ Optimization      │ Harder               │ Easier                            │
│ Code Generation   │ Simpler              │ Requires register allocation      │
└───────────────────┴──────────────────────┴───────────────────────────────────┘
```

---

## Part 4: Anatomy of a Bytecode Instruction

Let's examine how bytecode instructions are structured:

### Instruction Components

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    INSTRUCTION ANATOMY                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌────────────────────────────────────────────────────────────┐            │
│   │  OPCODE  │  OPERAND 1  │  OPERAND 2  │  OPERAND 3  │ ...  │            │
│   └────────────────────────────────────────────────────────────┘            │
│   │          │                                                              │
│   │          └── What to operate on (registers, constants, etc.)            │
│   │                                                                         │
│   └── What operation to perform (ADD, LOAD, JUMP, etc.)                     │
│                                                                              │
│   Example: ADD R0, R1, R2  (R0 = R1 + R2)                                   │
│                                                                              │
│   ┌──────────┬──────────┬──────────┬──────────┐                             │
│   │   0x01   │   0x00   │   0x01   │   0x02   │                             │
│   │  (ADD)   │   (R0)   │   (R1)   │   (R2)   │                             │
│   └──────────┴──────────┴──────────┴──────────┘                             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Opcode Encoding Strategies

**Fixed-Width Instructions**:
Every instruction is the same size (e.g., 4 bytes)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│   Fixed-Width (32-bit instructions):                                         │
│                                                                              │
│   ┌────────┬────────┬────────┬────────┐                                     │
│   │ opcode │  arg1  │  arg2  │  arg3  │  = 4 bytes always                   │
│   │ 8 bits │ 8 bits │ 8 bits │ 8 bits │                                     │
│   └────────┴────────┴────────┴────────┘                                     │
│                                                                              │
│   Pros: Simple decoding, predictable fetch                                   │
│   Cons: Wastes space for simple instructions                                 │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Variable-Width Instructions**:
Instructions can be different sizes

```
┌──────────────────────────────────────────────────────────────────────────────┐
│   Variable-Width:                                                            │
│                                                                              │
│   NOP:      ┌────────┐                                                      │
│             │  0x00  │  = 1 byte                                            │
│             └────────┘                                                      │
│                                                                              │
│   PUSH 42:  ┌────────┬────────┐                                             │
│             │  0x01  │   42   │  = 2 bytes                                  │
│             └────────┴────────┘                                             │
│                                                                              │
│   CALL fn:  ┌────────┬────────┬────────┬────────┬────────┐                  │
│             │  0x02  │      function address (32-bit)    │  = 5 bytes       │
│             └────────┴────────┴────────┴────────┴────────┘                  │
│                                                                              │
│   Pros: Compact code                                                         │
│   Cons: More complex decoding                                                │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Example: A Simple Instruction Set

Here's a minimal bytecode instruction set:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    SIMPLE INSTRUCTION SET                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Opcode  │ Name     │ Operands     │ Description                           │
│   ────────┼──────────┼──────────────┼────────────────────────────────────   │
│   0x00    │ NOP      │ none         │ Do nothing                            │
│   0x01    │ PUSH     │ value (i32)  │ Push constant onto stack              │
│   0x02    │ POP      │ none         │ Remove top of stack                   │
│   0x03    │ ADD      │ none         │ Pop two, push sum                     │
│   0x04    │ SUB      │ none         │ Pop two, push difference              │
│   0x05    │ MUL      │ none         │ Pop two, push product                 │
│   0x06    │ DIV      │ none         │ Pop two, push quotient                │
│   0x07    │ NEG      │ none         │ Negate top of stack                   │
│   0x08    │ LOAD     │ slot (u8)    │ Push local variable                   │
│   0x09    │ STORE    │ slot (u8)    │ Pop and store to local                │
│   0x0A    │ JUMP     │ offset (i16) │ Unconditional jump                    │
│   0x0B    │ JUMPZ    │ offset (i16) │ Jump if top is zero                   │
│   0x0C    │ CALL     │ addr (u32)   │ Call function                         │
│   0x0D    │ RET      │ none         │ Return from function                  │
│   0x0E    │ PRINT    │ none         │ Print top of stack                    │
│   0x0F    │ HALT     │ none         │ Stop execution                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Encoding Constants

Large constants need special handling:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    CONSTANT ENCODING                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Small constants (inline):                                                  │
│   ────────────────────────                                                   │
│   PUSH_SMALL 42    →  ┌──────────┬──────────┐                               │
│                       │   0x01   │    42    │  2 bytes                      │
│                       └──────────┴──────────┘                               │
│                                                                              │
│   Large constants (from constant pool):                                      │
│   ─────────────────────────────────────                                      │
│   Constant Pool: [3.14159, "hello", 1000000]                                 │
│                   idx 0    idx 1    idx 2                                    │
│                                                                              │
│   LOAD_CONST 2    →  ┌──────────┬──────────┐                                │
│                      │   0x10   │    2     │  Load 1000000                  │
│                      └──────────┴──────────┘                                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 5: Famous Bytecode Systems

Let's examine some well-known bytecode implementations:

### Java Virtual Machine (JVM)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    JAVA VIRTUAL MACHINE                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Architecture: Stack-based                                                  │
│   Instruction Size: 1-3 bytes (variable)                                     │
│   Opcodes: ~200 instructions                                                 │
│                                                                              │
│   Java Source:                     Bytecode:                                 │
│   ────────────                     ─────────                                 │
│   int add(int a, int b) {          iload_0      // Push a                   │
│       return a + b;                 iload_1      // Push b                   │
│   }                                 iadd         // Add them                 │
│                                     ireturn      // Return result            │
│                                                                              │
│   View with: javap -c MyClass.class                                          │
│                                                                              │
│   Key Features:                                                              │
│   • Type-specific instructions (iadd, fadd, dadd)                            │
│   • Constant pool for strings/numbers                                        │
│   • JIT compilation (HotSpot, GraalVM)                                       │
│   • Bytecode verification for security                                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Python Bytecode

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    PYTHON BYTECODE                                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Architecture: Stack-based                                                  │
│   Instruction Size: 2 bytes (wordcode in Python 3.6+)                        │
│   Opcodes: ~120 instructions                                                 │
│                                                                              │
│   Python Source:                   Bytecode:                                 │
│   ──────────────                   ─────────                                 │
│   def add(a, b):                   LOAD_FAST 0 (a)                           │
│       return a + b                 LOAD_FAST 1 (b)                           │
│                                    BINARY_ADD                                │
│                                    RETURN_VALUE                              │
│                                                                              │
│   View with: import dis; dis.dis(add)                                        │
│                                                                              │
│   Key Features:                                                              │
│   • Dynamic typing (one ADD for all types)                                   │
│   • Name-based lookup (LOAD_NAME, LOAD_GLOBAL)                               │
│   • Compiled to .pyc files                                                   │
│   • No JIT in CPython (but PyPy has one)                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### WebAssembly (WASM)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    WEBASSEMBLY                                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Architecture: Stack-based                                                  │
│   Instruction Size: Variable (LEB128 encoding)                               │
│   Design: Low-level, type-safe, sandboxed                                    │
│                                                                              │
│   WAT (text format):               Binary:                                   │
│   ──────────────────               ───────                                   │
│   (func $add                       0x20 0x00    ;; local.get 0              │
│     (param $a i32)                 0x20 0x01    ;; local.get 1              │
│     (param $b i32)                 0x6A         ;; i32.add                  │
│     (result i32)                   0x0F         ;; return                   │
│     local.get $a                                                             │
│     local.get $b                                                             │
│     i32.add)                                                                 │
│                                                                              │
│   Key Features:                                                              │
│   • Designed for the web (runs in browsers)                                  │
│   • Near-native speed                                                        │
│   • Strong sandboxing                                                        │
│   • Multiple source languages (C, C++, Rust, Zig)                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Lua Virtual Machine

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    LUA VM (5.0+)                                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Architecture: Register-based                                               │
│   Instruction Size: 32 bits (fixed)                                          │
│   Registers: 256 virtual registers                                           │
│                                                                              │
│   Lua Source:                      Bytecode:                                 │
│   ───────────                      ─────────                                 │
│   local function add(a, b)         MOVE R2, R0        -- copy a             │
│       return a + b                 ADD R2, R2, R1     -- R2 = a + b         │
│   end                              RETURN R2, 2       -- return R2          │
│                                                                              │
│   Instruction Format (32 bits):                                              │
│   ┌────────┬────────┬────────┬────────┐                                     │
│   │ opcode │   A    │   B    │   C    │                                     │
│   │ 6 bits │ 8 bits │ 9 bits │ 9 bits │                                     │
│   └────────┴────────┴────────┴────────┘                                     │
│                                                                              │
│   Key Features:                                                              │
│   • Switched from stack to registers in 5.0                                  │
│   • Very fast interpreter                                                    │
│   • Compact: entire VM is ~20K lines of C                                    │
│   • LuaJIT: one of fastest dynamic language VMs                              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Comparison Table

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    BYTECODE SYSTEMS COMPARISON                               │
├──────────┬─────────┬───────────┬──────────┬────────────┬────────────────────┤
│ System   │ Arch    │ Inst Size │ JIT?     │ Typed?     │ Use Case           │
├──────────┼─────────┼───────────┼──────────┼────────────┼────────────────────┤
│ JVM      │ Stack   │ 1-3 bytes │ Yes      │ Yes        │ Enterprise apps    │
│ CPython  │ Stack   │ 2 bytes   │ No*      │ No         │ Scripting          │
│ WASM     │ Stack   │ Variable  │ Yes      │ Yes        │ Web/portable       │
│ Lua      │ Register│ 4 bytes   │ LuaJIT   │ No         │ Embedding          │
│ CLR      │ Stack   │ Variable  │ Yes      │ Yes        │ .NET ecosystem     │
│ Dalvik   │ Register│ 2-6 bytes │ ART      │ Yes        │ Android apps       │
├──────────┴─────────┴───────────┴──────────┴────────────┴────────────────────┤
│ * PyPy has JIT, CPython does not                                             │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 6: Bytecode in Zig's Context

How does Zig relate to bytecode? Zig takes a different approach:

### Zig's Compilation Model

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    ZIG'S APPROACH                                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Zig is an ahead-of-time (AOT) compiled language:                           │
│                                                                              │
│   Source → AST → ZIR → AIR → Machine Code                                    │
│                                                                              │
│   • No bytecode VM at runtime                                                │
│   • Compiles directly to native code (or LLVM IR)                            │
│   • No interpreter for end users                                             │
│                                                                              │
│   However, Zig DOES use bytecode internally...                               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Compile-Time Execution

Zig's compile-time execution (`comptime`) uses an internal bytecode interpreter:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    ZIG'S COMPTIME INTERPRETER                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   const result = comptime blk: {                                             │
│       var sum: i32 = 0;                                                      │
│       for (0..10) |i| {                                                      │
│           sum += @intCast(i);                                                │
│       }                                                                      │
│       break :blk sum;                                                        │
│   };                                                                         │
│                                                                              │
│   This loop runs at COMPILE TIME, not runtime!                               │
│                                                                              │
│   How it works:                                                              │
│   1. Zig compiles comptime blocks to internal bytecode                       │
│   2. Interpreter executes the bytecode during compilation                    │
│   3. Result is embedded as a constant in the binary                          │
│                                                                              │
│   The comptime bytecode is never shipped - it exists only during build.      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### AIR as "High-Level Bytecode"

While not traditional bytecode, Zig's AIR shares some characteristics:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    AIR vs TRADITIONAL BYTECODE                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Traditional Bytecode:           Zig's AIR:                                 │
│   ─────────────────────           ──────────                                 │
│   • Executed by VM                • Translated to machine code               │
│   • Portable binary               • Internal representation only             │
│   • Shipped to users              • Never leaves compiler                    │
│   • Stack or register ops         • SSA form                                 │
│                                                                              │
│   Similarities:                                                              │
│   • Sequence of instructions                                                 │
│   • Operations on typed values                                               │
│   • Lower-level than source AST                                              │
│   • Portable across targets (within compiler)                                │
│                                                                              │
│   Example AIR:                                                               │
│   %0 = constant(3)                                                           │
│   %1 = constant(5)                                                           │
│   %2 = add(%0, %1)                                                           │
│   %3 = ret(%2)                                                               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### When Might Zig Use Bytecode?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    ZIG + WASM                                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Zig CAN target WebAssembly:                                                │
│                                                                              │
│   $ zig build-exe -target wasm32-freestanding hello.zig                      │
│                                                                              │
│   Output: hello.wasm (WebAssembly bytecode!)                                 │
│                                                                              │
│   This creates bytecode that runs in browsers or WASI runtimes.              │
│   So Zig programs CAN become bytecode - just not JVM/Python style.           │
│                                                                              │
│   The WASM output is still ahead-of-time compiled, just to a                 │
│   portable bytecode format rather than x86/ARM machine code.                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 7: Designing Your Own Bytecode

Let's design a simple bytecode for a calculator language:

### The Language

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    CALCULATOR LANGUAGE                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Features:                                                                  │
│   • Integer arithmetic (+, -, *, /)                                          │
│   • Variables (single letters a-z)                                           │
│   • Print statement                                                          │
│                                                                              │
│   Example program:                                                           │
│   ──────────────                                                             │
│   x = 10                                                                     │
│   y = 3                                                                      │
│   z = x + y * 2                                                              │
│   print z                                                                    │
│                                                                              │
│   Output: 16                                                                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Instruction Set Design

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    CALCULATOR BYTECODE                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Opcode │ Mnemonic │ Operands │ Stack Effect │ Description                 │
│   ───────┼──────────┼──────────┼──────────────┼───────────────────────────  │
│   0x00   │ HALT     │ -        │ -            │ Stop execution              │
│   0x01   │ PUSH     │ i32      │ → value      │ Push integer constant       │
│   0x02   │ POP      │ -        │ value →      │ Discard top of stack        │
│   0x03   │ ADD      │ -        │ a,b → a+b    │ Add top two values          │
│   0x04   │ SUB      │ -        │ a,b → a-b    │ Subtract                    │
│   0x05   │ MUL      │ -        │ a,b → a*b    │ Multiply                    │
│   0x06   │ DIV      │ -        │ a,b → a/b    │ Divide                      │
│   0x07   │ LOAD     │ u8       │ → value      │ Load variable               │
│   0x08   │ STORE    │ u8       │ value →      │ Store to variable           │
│   0x09   │ PRINT    │ -        │ value →      │ Print and pop               │
│                                                                              │
│   Encoding:                                                                  │
│   • HALT, POP, ADD, SUB, MUL, DIV, PRINT: 1 byte                            │
│   • PUSH: 5 bytes (1 opcode + 4 byte integer)                               │
│   • LOAD, STORE: 2 bytes (1 opcode + 1 byte variable index)                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Compilation Example

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    COMPILING: z = x + y * 2                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   AST:                                                                       │
│           =                                                                  │
│          / \                                                                 │
│         z   +                                                                │
│            / \                                                               │
│           x   *                                                              │
│              / \                                                             │
│             y   2                                                            │
│                                                                              │
│   Bytecode Generation (post-order traversal for expressions):                │
│   ─────────────────────────────────────────────────────────                  │
│                                                                              │
│   Address │ Bytes          │ Assembly                                        │
│   ────────┼────────────────┼────────────────────────────────────────         │
│   0x00    │ 07 17          │ LOAD 23 (x)   ; x is var slot 23               │
│   0x02    │ 07 18          │ LOAD 24 (y)   ; y is var slot 24               │
│   0x04    │ 01 02 00 00 00 │ PUSH 2                                          │
│   0x09    │ 05             │ MUL           ; y * 2                           │
│   0x0A    │ 03             │ ADD           ; x + (y * 2)                     │
│   0x0B    │ 08 19          │ STORE 25 (z)  ; z = result                      │
│                                                                              │
│   Stack trace:                                                               │
│   LOAD x  → [10]                                                             │
│   LOAD y  → [10, 3]                                                          │
│   PUSH 2  → [10, 3, 2]                                                       │
│   MUL     → [10, 6]                                                          │
│   ADD     → [16]                                                             │
│   STORE z → []  (z = 16)                                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Complete Program Bytecode

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    FULL PROGRAM BYTECODE                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Source:          Bytecode:                                                 │
│   x = 10           PUSH 10; STORE 0                                          │
│   y = 3            PUSH 3; STORE 1                                           │
│   z = x + y * 2    LOAD 0; LOAD 1; PUSH 2; MUL; ADD; STORE 2                │
│   print z          LOAD 2; PRINT                                             │
│                    HALT                                                      │
│                                                                              │
│   Hex dump:                                                                  │
│   01 0A 00 00 00   ; PUSH 10                                                 │
│   08 00            ; STORE 0 (x)                                             │
│   01 03 00 00 00   ; PUSH 3                                                  │
│   08 01            ; STORE 1 (y)                                             │
│   07 00            ; LOAD 0 (x)                                              │
│   07 01            ; LOAD 1 (y)                                              │
│   01 02 00 00 00   ; PUSH 2                                                  │
│   05               ; MUL                                                     │
│   03               ; ADD                                                     │
│   08 02            ; STORE 2 (z)                                             │
│   07 02            ; LOAD 2 (z)                                              │
│   09               ; PRINT                                                   │
│   00               ; HALT                                                    │
│                                                                              │
│   Total: 28 bytes                                                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 8: Bytecode Execution

Now let's build an interpreter for our bytecode:

### The Interpreter Loop

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    BASIC INTERPRETER LOOP                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   function execute(bytecode):                                                │
│       ip = 0                    // instruction pointer                       │
│       stack = []                // operand stack                             │
│       vars = [0] * 26           // variables a-z                             │
│                                                                              │
│       while true:                                                            │
│           opcode = bytecode[ip]                                              │
│           ip = ip + 1                                                        │
│                                                                              │
│           switch opcode:                                                     │
│               case HALT:                                                     │
│                   return                                                     │
│                                                                              │
│               case PUSH:                                                     │
│                   value = read_i32(bytecode, ip)                             │
│                   ip = ip + 4                                                │
│                   stack.push(value)                                          │
│                                                                              │
│               case ADD:                                                      │
│                   b = stack.pop()                                            │
│                   a = stack.pop()                                            │
│                   stack.push(a + b)                                          │
│                                                                              │
│               case LOAD:                                                     │
│                   slot = bytecode[ip]                                        │
│                   ip = ip + 1                                                │
│                   stack.push(vars[slot])                                     │
│                                                                              │
│               case STORE:                                                    │
│                   slot = bytecode[ip]                                        │
│                   ip = ip + 1                                                │
│                   vars[slot] = stack.pop()                                   │
│                                                                              │
│               case PRINT:                                                    │
│                   print(stack.pop())                                         │
│                                                                              │
│               // ... other cases                                             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Dispatch Strategies

Different ways to implement the main loop:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    DISPATCH STRATEGIES                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. SWITCH DISPATCH (simplest)                                              │
│   ─────────────────────────────                                              │
│   while (running):                                                           │
│       switch bytecode[ip++]:                                                 │
│           case ADD: ...                                                      │
│           case SUB: ...                                                      │
│                                                                              │
│   Pros: Simple, portable                                                     │
│   Cons: Branch prediction suffers                                            │
│                                                                              │
│   2. COMPUTED GOTO / DIRECT THREADING                                        │
│   ───────────────────────────────────                                        │
│   // GCC extension                                                           │
│   static void* dispatch[] = { &&op_add, &&op_sub, ... };                     │
│   goto *dispatch[bytecode[ip++]];                                            │
│   op_add:                                                                    │
│       // handle add                                                          │
│       goto *dispatch[bytecode[ip++]];                                        │
│                                                                              │
│   Pros: ~20-30% faster than switch                                           │
│   Cons: GCC/Clang specific, harder to debug                                  │
│                                                                              │
│   3. TAIL CALL DISPATCH                                                      │
│   ─────────────────────                                                      │
│   typedef void (*Handler)(VM*);                                              │
│   Handler handlers[] = { op_add, op_sub, ... };                              │
│   void op_add(VM* vm) {                                                      │
│       // handle add                                                          │
│       return handlers[vm->bytecode[vm->ip++]](vm);                           │
│   }                                                                          │
│                                                                              │
│   Pros: Clean code, good with tail call optimization                         │
│   Cons: Requires TCO guarantee                                               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### JIT Compilation Basics

For better performance, bytecode can be JIT-compiled to native code:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    JIT COMPILATION                                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Interpretation:                                                            │
│   ───────────────                                                            │
│   Bytecode → Read → Decode → Execute → Read → Decode → Execute → ...        │
│                                                                              │
│   JIT Compilation:                                                           │
│   ────────────────                                                           │
│   Bytecode → Compile to native → Execute native code                         │
│                                                                              │
│   Example: Compiling ADD to x86-64                                           │
│   ────────────────────────────────                                           │
│                                                                              │
│   Bytecode:     Native x86-64:                                               │
│   ADD           pop rax           ; b                                        │
│                 pop rbx           ; a                                        │
│                 add rax, rbx      ; a + b                                    │
│                 push rax          ; result                                   │
│                                                                              │
│   JIT Strategies:                                                            │
│   ───────────────                                                            │
│   • Method JIT: Compile entire functions                                     │
│   • Tracing JIT: Compile hot loops                                           │
│   • Tiered: Interpret first, JIT hot code                                    │
│                                                                              │
│   Examples:                                                                  │
│   • HotSpot (Java): Tiered compilation                                       │
│   • LuaJIT: Tracing JIT                                                      │
│   • V8 (JavaScript): Multiple tiers (Ignition → Sparkplug → Turbofan)       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Performance Considerations

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    INTERPRETER PERFORMANCE                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Typical overhead vs native code:                                           │
│   ────────────────────────────────                                           │
│   • Switch-based interpreter: 10-50x slower                                  │
│   • Direct threading: 5-30x slower                                           │
│   • Basic JIT: 2-5x slower                                                   │
│   • Optimizing JIT: 1-2x slower (sometimes matches native!)                 │
│                                                                              │
│   Optimization techniques:                                                   │
│   ─────────────────────────                                                  │
│   • Superinstructions: Combine common sequences                              │
│     LOAD 0; LOAD 1; ADD → LOAD_LOAD_ADD 0, 1                                │
│                                                                              │
│   • Inline caching: Cache method lookups                                     │
│                                                                              │
│   • Stack caching: Keep top-of-stack in registers                           │
│     Instead of push/pop to memory, use CPU registers                        │
│                                                                              │
│   • NaN boxing: Encode type and value in 64 bits                            │
│     Avoids separate type checks                                              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 9: Complete Example

Let's trace through a complete example from source to execution:

### Source Expression

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    EXAMPLE: 3 + 5 * 2                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Expression: 3 + 5 * 2                                                      │
│   Expected result: 13 (multiplication first, then addition)                  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Step 1: Parsing to AST

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    ABSTRACT SYNTAX TREE                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [NUM(3), PLUS, NUM(5), STAR, NUM(2)]                               │
│                                                                              │
│   AST (respecting precedence):                                               │
│                                                                              │
│            +                                                                 │
│           / \                                                                │
│          3   *                                                               │
│             / \                                                              │
│            5   2                                                             │
│                                                                              │
│   In data structure form:                                                    │
│   BinaryOp {                                                                 │
│       op: ADD,                                                               │
│       left: Number(3),                                                       │
│       right: BinaryOp {                                                      │
│           op: MUL,                                                           │
│           left: Number(5),                                                   │
│           right: Number(2)                                                   │
│       }                                                                      │
│   }                                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Step 2: Bytecode Generation

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    BYTECODE GENERATION                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   function generateExpr(node):                                               │
│       if node is Number:                                                     │
│           emit(PUSH, node.value)                                             │
│       else if node is BinaryOp:                                              │
│           generateExpr(node.left)   # Generate left operand                  │
│           generateExpr(node.right)  # Generate right operand                 │
│           if node.op == ADD: emit(ADD)                                       │
│           if node.op == MUL: emit(MUL)                                       │
│           # etc.                                                             │
│                                                                              │
│   Traversal order (post-order):                                              │
│   1. Visit left child (3)      → PUSH 3                                     │
│   2. Visit right child's left (5) → PUSH 5                                  │
│   3. Visit right child's right (2) → PUSH 2                                 │
│   4. Emit right child's op (*) → MUL                                        │
│   5. Emit root op (+)         → ADD                                         │
│                                                                              │
│   Generated bytecode:                                                        │
│   ┌────────────────────────────────────────┐                                │
│   │ PUSH 3  │ PUSH 5  │ PUSH 2  │ MUL │ ADD │                               │
│   └────────────────────────────────────────┘                                │
│                                                                              │
│   Hex: 01 03 00 00 00  01 05 00 00 00  01 02 00 00 00  05  03               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Step 3: Execution Trace

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    EXECUTION TRACE                                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   IP │ Instruction │ Stack Before │ Action           │ Stack After          │
│   ───┼─────────────┼──────────────┼──────────────────┼───────────────────   │
│   0  │ PUSH 3      │ []           │ Push 3           │ [3]                  │
│   5  │ PUSH 5      │ [3]          │ Push 5           │ [3, 5]               │
│   10 │ PUSH 2      │ [3, 5]       │ Push 2           │ [3, 5, 2]            │
│   15 │ MUL         │ [3, 5, 2]    │ Pop 2,5; Push 10 │ [3, 10]              │
│   16 │ ADD         │ [3, 10]      │ Pop 10,3; Push 13│ [13]                 │
│                                                                              │
│   Result: 13 (top of stack)                                                  │
│                                                                              │
│   Visual stack evolution:                                                    │
│                                                                              │
│   PUSH 3    PUSH 5    PUSH 2    MUL       ADD                                │
│                                                                              │
│   ┌───┐                                                                      │
│   │ 3 │                                                                      │
│   └───┘     ┌───┐                                                            │
│             │ 5 │                                                            │
│   ┌───┐     ├───┤     ┌───┐                                                  │
│   │ 3 │     │ 3 │     │ 2 │                                                  │
│   └───┘     └───┘     ├───┤     ┌────┐     ┌────┐                            │
│                       │ 5 │     │ 10 │     │ 13 │                            │
│                       ├───┤     ├────┤     └────┘                            │
│                       │ 3 │     │  3 │                                       │
│                       └───┘     └────┘                                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Step 4: Interpreter Code

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    INTERPRETER IMPLEMENTATION                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   // C implementation                                                        │
│   int32_t execute(uint8_t* code, size_t len) {                              │
│       int32_t stack[256];                                                    │
│       int sp = 0;  // stack pointer                                          │
│       int ip = 0;  // instruction pointer                                    │
│                                                                              │
│       while (ip < len) {                                                     │
│           uint8_t op = code[ip++];                                          │
│                                                                              │
│           switch (op) {                                                      │
│               case OP_PUSH: {                                                │
│                   int32_t val = *(int32_t*)&code[ip];                       │
│                   ip += 4;                                                   │
│                   stack[sp++] = val;                                         │
│                   break;                                                     │
│               }                                                              │
│               case OP_ADD: {                                                 │
│                   int32_t b = stack[--sp];                                  │
│                   int32_t a = stack[--sp];                                  │
│                   stack[sp++] = a + b;                                       │
│                   break;                                                     │
│               }                                                              │
│               case OP_MUL: {                                                 │
│                   int32_t b = stack[--sp];                                  │
│                   int32_t a = stack[--sp];                                  │
│                   stack[sp++] = a * b;                                       │
│                   break;                                                     │
│               }                                                              │
│               // ... other ops                                               │
│           }                                                                  │
│       }                                                                      │
│                                                                              │
│       return stack[0];  // result                                            │
│   }                                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Part 10: The Big Picture

### When to Use Bytecode

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    WHEN TO USE BYTECODE                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   USE BYTECODE WHEN:                     USE NATIVE CODE WHEN:               │
│   ─────────────────────                  ───────────────────────             │
│   • Portability is critical              • Maximum performance needed        │
│   • Sandboxing required                  • Target platform is known          │
│   • Fast compile times matter            • No runtime overhead acceptable    │
│   • Dynamic code loading                 • Embedded/resource constrained     │
│   • Scripting/plugin systems             • Systems programming               │
│                                                                              │
│   Examples:                              Examples:                           │
│   • Game scripting (Lua)                 • Operating systems (C, Rust)       │
│   • Web apps (JavaScript/WASM)           • Game engines (C++)                │
│   • Cross-platform apps (Java)           • Database engines (C)              │
│   • Config languages (Python)            • Compilers (Zig, Rust)             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Summary Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    BYTECODE: THE COMPLETE PICTURE                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────┐                                                            │
│   │   SOURCE    │  Human-readable code                                       │
│   │    CODE     │  (x = 3 + 5)                                               │
│   └──────┬──────┘                                                            │
│          │                                                                   │
│          ▼  Lexer + Parser                                                   │
│   ┌─────────────┐                                                            │
│   │    AST      │  Tree structure                                            │
│   │             │  capturing meaning                                         │
│   └──────┬──────┘                                                            │
│          │                                                                   │
│          ▼  Bytecode Compiler                                                │
│   ┌─────────────┐                                                            │
│   │  BYTECODE   │  Portable, compact                                         │
│   │  (binary)   │  instruction sequence                                      │
│   └──────┬──────┘                                                            │
│          │                                                                   │
│          ├─────────────────────────────┐                                     │
│          ▼                             ▼                                     │
│   ┌─────────────┐               ┌─────────────┐                              │
│   │ INTERPRETER │               │    JIT      │                              │
│   │ (decode +   │               │ (compile to │                              │
│   │  execute)   │               │  native)    │                              │
│   └──────┬──────┘               └──────┬──────┘                              │
│          │                             │                                     │
│          ▼                             ▼                                     │
│   ┌─────────────────────────────────────────┐                                │
│   │              EXECUTION                  │                                │
│   │         (program runs!)                 │                                │
│   └─────────────────────────────────────────┘                                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Key Takeaways

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    KEY TAKEAWAYS                                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. BYTECODE IS AN INTERMEDIATE FORMAT                                      │
│      Between source code and machine code, offering portability              │
│      and fast loading while remaining platform-independent.                  │
│                                                                              │
│   2. TWO MAIN ARCHITECTURES                                                  │
│      Stack-based (simpler, smaller code) vs Register-based                   │
│      (fewer instructions, easier to optimize).                               │
│                                                                              │
│   3. EXECUTION OPTIONS                                                       │
│      Interpret directly (simple but slow), JIT compile                       │
│      (complex but fast), or hybrid tiered approach.                          │
│                                                                              │
│   4. DESIGN TRADE-OFFS                                                       │
│      Fixed vs variable instruction size, number of opcodes,                  │
│      constant encoding, all affect code size and speed.                      │
│                                                                              │
│   5. REAL-WORLD EXAMPLES                                                     │
│      JVM, Python, WebAssembly, Lua all use bytecode with                     │
│      different design choices for different goals.                           │
│                                                                              │
│   6. ZIG'S APPROACH                                                          │
│      Zig compiles to native code but uses bytecode internally                │
│      for comptime execution. Can also target WASM.                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Further Reading

### Books

- **"Crafting Interpreters"** by Robert Nystrom
  Free online at craftinginterpreters.com. Excellent coverage of bytecode VMs.

- **"Virtual Machines"** by Iain Craig
  Comprehensive academic treatment of VM design.

- **"Engineering a Compiler"** by Cooper & Torczon
  Chapter on intermediate representations covers bytecode concepts.

### Papers and Articles

- **"The Implementation of Lua 5.0"** - Lua team's paper on their register-based VM design

- **"The Java Virtual Machine Specification"** - Oracle's official JVM bytecode documentation

- **"WebAssembly Specification"** - The official WASM spec at webassembly.github.io

### Source Code to Study

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    CODEBASES TO STUDY                                        │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Language       │ VM Type    │ Lines   │ Notable For                       │
│   ───────────────┼────────────┼─────────┼──────────────────────────────────  │
│   Lua            │ Register   │ ~25K    │ Tiny, well-documented             │
│   CPython        │ Stack      │ ~500K   │ Most popular, good docs           │
│   LuaJIT         │ Register   │ ~50K    │ Amazing JIT implementation        │
│   mruby          │ Register   │ ~50K    │ Embeddable Ruby                   │
│   QuickJS        │ Stack      │ ~60K    │ Tiny JavaScript engine            │
│   wasm3          │ Stack      │ ~15K    │ Portable WASM interpreter         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Conclusion

Bytecode represents a powerful middle ground in language implementation. By compiling source code to a platform-independent binary format, language designers gain:

- **Portability**: One compilation, many platforms
- **Performance**: Faster than interpreting source directly
- **Security**: Sandboxed execution environment
- **Flexibility**: Interpret, JIT compile, or both

Understanding bytecode gives you insight into how languages like Java, Python, and JavaScript work under the hood. It also provides a foundation for understanding more advanced topics like JIT compilation and garbage collection.

Whether you're building a scripting language, understanding existing VMs, or just curious about how code executes, bytecode concepts form an essential part of programming language knowledge.

---

## Navigation

← [Previous: Part 13 - Mini Compiler](../13-mini-compiler)

[Back to Series Index](../)
