---
title: "Section 5c: x86 Assembly Backend"
weight: 8
---

# Section 5c: x86 Assembly Code Generation

A third backend option that generates x86-64 assembly directly, without LLVM or C as intermediates.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        x86 BACKEND PIPELINE                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ZIR (Typed IR)                                                             │
│       │                                                                      │
│       ▼                                                                      │
│   ┌─────────────────┐                                                       │
│   │   x86 Codegen   │  Generate x86-64 assembly                             │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐                                                       │
│   │   output.s      │  Assembly text file (AT&T syntax)                     │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐                                                       │
│   │      as         │  GNU Assembler                                        │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐                                                       │
│   │   output.o      │  Object file                                          │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐                                                       │
│   │   ld / cc       │  Linker                                               │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐                                                       │
│   │   executable    │  Native binary                                        │
│   └─────────────────┘                                                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Why Generate x86 Directly?

You could use LLVM (like we did in Section 5b), but generating assembly directly has benefits:

| Approach | Pros | Cons |
|----------|------|------|
| **LLVM IR** | Optimizations, multi-target | Dependency, complexity |
| **C code** | Portable, readable | Extra compilation step |
| **x86 directly** | No dependencies, full control, educational | Platform-specific |

**For learning**: Generating x86 assembly teaches you exactly what the CPU sees. No magic, no abstractions.

---

## The Output

```
fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn main() i32 {
    return add(10, 5);
}
```

Becomes:

```asm
    .text
    .globl add
add:
    pushq   %rbp
    movq    %rsp, %rbp
    movl    %edi, %eax
    addl    %esi, %eax
    popq    %rbp
    ret

    .globl main
main:
    pushq   %rbp
    movq    %rsp, %rbp
    movl    $10, %edi
    movl    $5, %esi
    call    add
    popq    %rbp
    ret
```

Then compile and run:
```bash
as -o output.o output.s
cc -o program output.o
./program
echo $?  # prints 15
```

---

## Lessons in This Section

| Lesson | Topic | What You'll Learn |
|--------|-------|-------------------|
| [1. Why x86?](01-why-x86/) | Introduction | Native code, trade-offs, syntax, architectures |
| [2. x86-64 Basics](02-x86-basics/) | Architecture | Registers, instructions, memory |
| [3. Calling Convention](03-calling-convention/) | System V ABI | Parameters, returns, stack |
| [4. Register Allocation](04-register-allocation/) | Resource management | Simple allocation strategy |
| [5. Constants](05-gen-constants/) | Literals | `movl $42, %eax` |
| [6. Arithmetic](06-gen-arithmetic/) | Binary ops | add, sub, mul, div |
| [7. Functions](07-gen-functions/) | Structure | Prologue, epilogue, params |
| [8. Function Calls](08-gen-calls/) | Calling | Arguments, call, results |
| [9. Complete Backend](09-complete/) | Integration | Full pipeline |

---

## Prerequisites

Complete the main tutorial through Section 4 (Sema) first. This section provides an alternative to Section 5 (C Codegen) and Section 5b (LLVM).

You'll need:
- A Unix-like system (Linux or macOS)
- GNU assembler (`as`) or Clang/GCC (for `cc`)
- Basic understanding of binary numbers

**Architecture Note:**

| Your System | Compatibility |
|-------------|---------------|
| Intel/AMD Mac or PC | ✅ Native x86-64 |
| Apple Silicon Mac (M1/M2/M3) | ✅ Works via Rosetta 2 |
| Linux on ARM64 | ❌ x86 code won't run |

Check yours: `uname -m` → `x86_64` means native x86-64, `arm64` means ARM.

---

## Code Generation Strategy

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                     x86 CODEGEN STRATEGY                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   For each ZIR instruction, emit corresponding x86 assembly:                │
│                                                                              │
│   literal(42)        →  movl $42, %reg                                      │
│   param_ref(0)       →  movl %edi, %reg                                     │
│   param_ref(1)       →  movl %esi, %reg                                     │
│   add(a, b)          →  movl %a, %dst; addl %b, %dst                       │
│   sub(a, b)          →  movl %a, %dst; subl %b, %dst                       │
│   mul(a, b)          →  movl %a, %dst; imull %b, %dst                      │
│   ret(val)           →  movl %val, %eax; leave; ret                        │
│   call(fn, args...)  →  [setup args]; call fn; [result in %eax]            │
│                                                                              │
│   Each ZIR instruction result maps to a physical register.                  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Concepts You'll Learn

1. **x86-64 registers** - rax, rbx, rcx, ..., r15 and their 32-bit counterparts
2. **AT&T syntax** - The `src, dst` format used by GNU assembler
3. **System V AMD64 ABI** - How functions receive parameters and return values
4. **Register allocation** - Mapping unlimited virtual registers to limited physical ones
5. **Stack frames** - Prologue/epilogue patterns for function calls
6. **Instruction selection** - Choosing the right x86 instruction for each operation

---

## Start Here

Begin with [Lesson 1: Why x86 Assembly?](01-why-x86/) →
