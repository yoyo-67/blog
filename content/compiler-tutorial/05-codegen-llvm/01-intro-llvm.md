---
title: "5b.1: Introduction to LLVM"
weight: 1
---

# Lesson 5b.1: Introduction to LLVM

What is LLVM and why use it as a compiler backend?

---

## Goal

Understand LLVM's role in compilation and why it's a powerful choice for code generation.

---

## What is LLVM?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           LLVM OVERVIEW                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   LLVM = Low Level Virtual Machine (historical name)                         │
│                                                                              │
│   Today: A collection of modular compiler technologies                       │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         LLVM PROJECT                                │   │
│   │                                                                     │   │
│   │   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐              │   │
│   │   │  LLVM   │  │  Clang  │  │  LLD    │  │  LLDB   │              │   │
│   │   │  Core   │  │ (C/C++) │  │(linker) │  │(debugger│              │   │
│   │   └─────────┘  └─────────┘  └─────────┘  └─────────┘              │   │
│   │                                                                     │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   We'll use LLVM Core: the IR, optimizer, and code generators               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## LLVM in the Compilation Pipeline

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      LLVM COMPILATION PIPELINE                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Your Language                                                              │
│       │                                                                      │
│       ▼                                                                      │
│   ┌─────────────┐                                                           │
│   │  Frontend   │  Lexer, Parser, Sema (YOU BUILD THIS)                     │
│   └──────┬──────┘                                                           │
│          │                                                                   │
│          ▼                                                                   │
│   ┌─────────────┐                                                           │
│   │  LLVM IR    │  Portable, typed intermediate representation              │
│   └──────┬──────┘                                                           │
│          │                                                                   │
│          ▼                                                                   │
│   ┌─────────────┐                                                           │
│   │  Optimizer  │  100+ optimization passes (LLVM PROVIDES)                 │
│   └──────┬──────┘                                                           │
│          │                                                                   │
│          ▼                                                                   │
│   ┌─────────────┐                                                           │
│   │  Backend    │  x86, ARM, RISC-V, WASM... (LLVM PROVIDES)               │
│   └──────┬──────┘                                                           │
│          │                                                                   │
│          ▼                                                                   │
│   Machine Code                                                               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Why Choose LLVM?

### Advantages

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         LLVM ADVANTAGES                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. OPTIMIZATION                                                            │
│      • Dead code elimination                                                 │
│      • Constant folding/propagation                                          │
│      • Loop optimization                                                     │
│      • Inlining                                                              │
│      • Vectorization (SIMD)                                                  │
│      • 100+ more passes                                                      │
│                                                                              │
│   2. MULTI-TARGET                                                            │
│      • x86-64, x86                                                           │
│      • ARM, AArch64                                                          │
│      • RISC-V                                                                │
│      • WebAssembly                                                           │
│      • Many more                                                             │
│                                                                              │
│   3. DEBUGGING                                                               │
│      • DWARF debug info                                                      │
│      • Source-level debugging                                                │
│      • Works with GDB, LLDB                                                  │
│                                                                              │
│   4. ECOSYSTEM                                                               │
│      • Used by Clang, Rust, Swift, Julia                                    │
│      • Well-documented                                                       │
│      • Active development                                                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Disadvantages

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         LLVM DISADVANTAGES                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. SIZE                                                                    │
│      • LLVM libraries are ~100-500MB                                         │
│      • Significant compile-time dependency                                   │
│                                                                              │
│   2. COMPILE TIME                                                            │
│      • Optimization passes take time                                         │
│      • Debug builds faster, release builds slower                            │
│                                                                              │
│   3. COMPLEXITY                                                              │
│      • Large API to learn                                                    │
│      • IR has many features you may not need                                │
│                                                                              │
│   4. ABI STABILITY                                                           │
│      • C++ API changes between versions                                      │
│      • Need to match LLVM version carefully                                  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## LLVM vs C Backend Comparison

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      C BACKEND vs LLVM BACKEND                               │
├─────────────────────────┬────────────────────────────────────────────────────┤
│       C Backend         │           LLVM Backend                             │
├─────────────────────────┼────────────────────────────────────────────────────┤
│ Output: C source code   │ Output: LLVM IR                                    │
│ Simple text generation  │ Structured IR generation                           │
│ Uses gcc/clang to compile│ Uses LLVM tools (llc, opt)                        │
│ Human-readable output   │ Human-readable IR (text format)                    │
│ No dependencies         │ Requires LLVM installation                         │
│ Optimization via cc -O3 │ Direct optimization control                        │
│ Limited debug info      │ Full debug info support                            │
│ Simple to implement     │ More complex, more powerful                        │
└─────────────────────────┴────────────────────────────────────────────────────┘
```

---

## Languages Using LLVM

Many production languages use LLVM:

| Language | Notes |
|----------|-------|
| **Clang** | C/C++/Objective-C frontend for LLVM |
| **Rust** | rustc uses LLVM for codegen |
| **Swift** | Apple's language, LLVM-based |
| **Julia** | JIT compiled via LLVM |
| **Zig** | Uses LLVM (with self-hosted alternative) |
| **Crystal** | Ruby-like, LLVM-compiled |
| **Kotlin Native** | Kotlin to native via LLVM |

---

## Our Approach

We'll generate LLVM IR as text (`.ll` files):

```llvm
; hello.ll
define i32 @main() {
entry:
    ret i32 42
}
```

Then use LLVM tools:
```bash
# Interpret directly
lli hello.ll

# Compile to executable
llc hello.ll -o hello.s
clang hello.s -o hello
./hello
```

This is simpler than using the LLVM C++ API directly.

---

## Installing LLVM

```bash
# macOS
brew install llvm

# Ubuntu/Debian
sudo apt install llvm

# Check installation
llc --version
lli --version
```

---

## Verify Your Understanding

### Question 1
What does LLVM provide that we don't have to build ourselves?

Answer: Optimization passes and code generation for multiple CPU architectures.

### Question 2
What's the trade-off of using LLVM vs generating C?

Answer: LLVM provides more control and better optimization but requires the LLVM toolchain as a dependency and is more complex.

---

## What's Next

Let's learn the basics of LLVM IR syntax.

Next: [Lesson 5b.2: LLVM IR Basics](../02-llvm-ir-basics/) →
