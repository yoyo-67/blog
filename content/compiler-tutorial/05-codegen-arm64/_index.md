---
title: "Section 5d: ARM64 Assembly Backend"
weight: 9
---

# Section 5d: ARM64 Assembly Code Generation

A backend that generates ARM64 (AArch64) assembly directly, designed for Apple Silicon Macs and Linux ARM systems.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        ARM64 BACKEND PIPELINE                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ZIR (Typed IR)                                                             │
│       │                                                                      │
│       ▼                                                                      │
│   ┌─────────────────┐                                                       │
│   │  ARM64 Codegen  │  Generate ARM64 assembly                              │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐                                                       │
│   │   output.s      │  Assembly text file                                   │
│   └────────┬────────┘                                                       │
│            │                                                                 │
│            ▼                                                                 │
│   ┌─────────────────┐                                                       │
│   │      as         │  Assembler (GNU or Apple)                             │
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
│   │   executable    │  Native ARM64 binary                                  │
│   └─────────────────┘                                                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Why ARM64?

ARM64 processors power:
- **Apple Silicon Macs** (M1, M2, M3, M4)
- **Linux ARM servers** (AWS Graviton, Ampere)
- **Raspberry Pi 4+** and other SBCs
- **Mobile devices** (iOS, Android)

| Approach | Best For |
|----------|----------|
| **x86-64** | Intel/AMD Macs and PCs |
| **ARM64** | Apple Silicon, ARM Linux |
| **LLVM** | Multi-platform, optimizations |

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

Becomes (on macOS):

```asm
    .text
    .globl _add
_add:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    add     w0, w0, w1
    ldp     x29, x30, [sp], #16
    ret

    .globl _main
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     w0, #10
    mov     w1, #5
    bl      _add
    ldp     x29, x30, [sp], #16
    ret
```

Then compile and run:
```bash
cc -o program output.s
./program
echo $?  # prints 15
```

---

## Lessons in This Section

| Lesson | Topic | What You'll Learn |
|--------|-------|-------------------|
| [1. Why ARM64?](01-why-arm64/) | Introduction | RISC vs CISC, where ARM64 runs |
| [2. ARM64 Basics](02-arm64-basics/) | Architecture | Registers (x0-x30), instructions |
| [3. Calling Convention](03-calling-convention/) | AAPCS64 | Parameters (x0-x7), returns |
| [4. Register Allocation](04-register-allocation/) | Resource management | Simple allocation strategy |
| [5. Constants](05-gen-constants/) | Literals | `mov w9, #42` |
| [6. Arithmetic](06-gen-arithmetic/) | Binary ops | add, sub, mul, sdiv |
| [7. Functions](07-gen-functions/) | Structure | Prologue, epilogue, params |
| [8. Function Calls](08-gen-calls/) | Calling | `bl` instruction, link register |
| [9. Complete Backend](09-complete/) | Integration | Full pipeline |

---

## Prerequisites

Complete the main tutorial through Section 4 (Sema) first. This section provides an ARM64 alternative to Section 5c (x86).

You'll need:
- An ARM64 system (Apple Silicon Mac or Linux ARM)
- A C compiler (`cc` or `clang`)
- Basic understanding of binary numbers

**Architecture Check:**

```bash
uname -m
# arm64 or aarch64 → You're on ARM64 (native)
# x86_64 → You're on x86 (use Section 5c instead)
```

| Your System | Compatibility |
|-------------|---------------|
| Apple Silicon Mac (M1/M2/M3) | ✅ Native ARM64 |
| Linux on ARM64 | ✅ Native ARM64 |
| Intel/AMD Mac or PC | ❌ Use x86 tutorial instead |

---

## Code Generation Strategy

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                     ARM64 CODEGEN STRATEGY                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   For each ZIR instruction, emit corresponding ARM64 assembly:              │
│                                                                              │
│   literal(42)        →  mov wN, #42                                         │
│   param_ref(0)       →  mov wN, w0                                          │
│   param_ref(1)       →  mov wN, w1                                          │
│   add(a, b)          →  add wDst, wA, wB                                    │
│   sub(a, b)          →  sub wDst, wA, wB                                    │
│   mul(a, b)          →  mul wDst, wA, wB                                    │
│   div(a, b)          →  sdiv wDst, wA, wB                                   │
│   ret(val)           →  mov w0, wN; ldp x29,x30,[sp],#16; ret              │
│   call(fn, args...)  →  [setup w0-w7]; bl fn; [result in w0]               │
│                                                                              │
│   Each ZIR instruction result maps to a physical register.                  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Concepts You'll Learn

1. **ARM64 registers** - x0-x30 (64-bit) and w0-w30 (32-bit)
2. **3-operand instructions** - `add dst, src1, src2` (cleaner than x86)
3. **AAPCS64 calling convention** - Parameters in x0-x7, return in x0
4. **The link register** - x30 holds return address (no automatic stack push)
5. **Simple division** - Just `sdiv` (no special registers like x86)
6. **macOS vs Linux** - Symbol prefixes (`_main` vs `main`)

---

## ARM64 vs x86 Quick Comparison

| Aspect | x86-64 | ARM64 |
|--------|--------|-------|
| Add | `addl %esi, %eax` | `add w0, w0, w1` |
| Move | `movl $42, %eax` | `mov w0, #42` |
| Return | `ret` | `ret` |
| Call | `call func` | `bl func` |
| Division | `cdq; idivl %reg` | `sdiv dst, a, b` |
| Operand order | src, dst | dst, src1, src2 |

---

## Start Here

Begin with [Lesson 1: Why ARM64?](01-why-arm64/) →
