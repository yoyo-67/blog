---
title: "5.1: Target Choice"
weight: 1
---

# Lesson 5.1: Choosing a Target

What should our compiler output?

---

## Goal

Understand the different code generation targets and why we choose C.

---

## Target Options

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         TARGET OPTIONS                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. NATIVE MACHINE CODE (x86-64, ARM)                                      │
│      + Fastest execution                                                    │
│      + No runtime dependencies                                              │
│      - Complex instruction encoding                                         │
│      - Platform-specific                                                    │
│      - Requires assembler/linker knowledge                                  │
│                                                                              │
│   2. LLVM IR                                                                │
│      + Industrial-strength optimization                                     │
│      + Multiple targets from one IR                                         │
│      - Adds LLVM dependency (~100MB)                                        │
│      - Learning curve                                                       │
│                                                                              │
│   3. BYTECODE (like Java, Python)                                          │
│      + Portable                                                             │
│      + Can be interpreted                                                   │
│      - Needs a virtual machine                                              │
│      - Slower than native                                                   │
│                                                                              │
│   4. C CODE                                                                 │
│      + Simple to generate                                                   │
│      + Human-readable output                                                │
│      + Compiles everywhere                                                  │
│      + Uses existing C optimizer                                            │
│      - Extra compilation step                                               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Why C?

For a learning compiler, C is ideal:

1. **Readable**: You can see exactly what your compiler produces
2. **Debuggable**: Run the output through gdb/lldb
3. **Portable**: Works on any platform with a C compiler
4. **Free optimization**: `gcc -O3` optimizes your output
5. **Simple**: Just emit text strings

Many real compilers use this approach:
- Early C++ compilers generated C
- Nim generates C (and C++, JavaScript)
- Hare generates QBE IR (similar idea)

---

## The Compilation Pipeline

```
Our Language        C Code           Machine Code
    │                 │                   │
    ▼                 ▼                   ▼
┌─────────┐     ┌──────────┐      ┌─────────────┐
│ source  │ ──▶ │ output.c │ ──▶  │ executable  │
│  .mini  │     │          │      │             │
└─────────┘     └──────────┘      └─────────────┘
    │                 │                   │
    │    Our         │     C Compiler    │
    │  Compiler      │    (gcc/clang)    │
```

---

## C Code Structure

Generated C code looks like:

```c
// Headers
#include <stdint.h>
#include <stdbool.h>

// Function declarations (if needed for forward refs)
int32_t add(int32_t p0, int32_t p1);

// Function definitions
int32_t add(int32_t p0, int32_t p1) {
    int32_t t0 = p0 + p1;
    return t0;
}

// Main entry point
int32_t main() {
    return 0;
}
```

---

## Code Generator State

```
CodeGenerator {
    output: StringBuilder,    // The generated code
    indent: integer,          // Current indentation level

    // Emit helpers
    emit(string)              // Add text to output
    emitLine(string)          // Add text + newline
    emitIndent()              // Add current indentation
}
```

---

## Simple Example

```
AIR:
    function "main":
      param_types: []
      return_type: i32
      instructions:
        %0 = const_i32(0)
        %1 = ret(%0)

Generated C:
    int32_t main() {
        int32_t t0 = 0;
        return t0;
    }
```

---

## Alternative: Stack-Based Bytecode

If you wanted a VM instead:

```
AIR:
    %0 = const_i32(3)
    %1 = const_i32(5)
    %2 = add_i32(%0, %1)
    %3 = ret(%2)

Bytecode:
    PUSH_I32 3
    PUSH_I32 5
    ADD_I32
    RET
```

Then write an interpreter that executes these instructions.

---

## Verify Your Understanding

### Question 1
Why is generating C simpler than generating machine code?

Answer: C is text-based and human-readable. Machine code requires knowing CPU instruction encodings, register allocation, and platform-specific ABIs.

### Question 2
What are the disadvantages of generating C?

Answer: Extra compilation step (need gcc/clang), slightly slower compile time, can't do runtime code generation.

### Question 3
How do we get optimization "for free" with C output?

Answer: C compilers like GCC and Clang have decades of optimization work. Running `gcc -O3` on our output applies all those optimizations.

---

## What's Next

Let's map our types to C types.

Next: [Lesson 5.2: Type Mapping](../02-type-mapping/) →
