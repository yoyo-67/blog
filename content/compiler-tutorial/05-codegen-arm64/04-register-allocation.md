---
title: "Lesson 4: Register Allocation"
weight: 4
---

# Lesson 4: Register Allocation Strategy

ZIR uses unlimited virtual registers (%0, %1, %2...). Real CPUs have limited physical registers. We need a strategy to map them.

**What you'll learn:**
- The register allocation problem
- A simple linear allocation strategy
- Why ARM64's many registers make this easier

---

## Sub-lesson 4.1: The Mapping Problem

### The Problem

ZIR instructions reference virtual registers by index:

```
%0 = literal(10)
%1 = literal(5)
%2 = add(%0, %1)
%3 = literal(2)
%4 = mul(%2, %3)
%5 = ret(%4)
```

We have 5 values. Where do they go in physical registers?

### The Solution

Create a mapping from ZIR index to ARM64 register:

```
┌─────────────────────────────────────────────────────────────────────┐
│ ZIR TO REGISTER MAPPING                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ ZIR Index    ARM64 Register    Contents                            │
│ ─────────    ──────────────    ────────                            │
│ %0           w9                10                                  │
│ %1           w10               5                                   │
│ %2           w11               15 (10 + 5)                         │
│ %3           w12               2                                   │
│ %4           w13               30 (15 * 2)                         │
│                                                                     │
│ Simple rule: instruction N → scratch_regs[N]                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Sub-lesson 4.2: Choosing Scratch Registers

### The Problem

Which physical registers should we use for temporaries? We can't use:
- w0-w7: these are for passing/receiving parameters
- w19-w28: callee-saved (would need to save/restore them)
- w29, w30: special (frame pointer, link register)

### The Solution

Use **w9-w15** as scratch registers:

```
┌─────────────────────────────────────────────────────────────────────┐
│ REGISTER ASSIGNMENT FOR CODE GENERATION                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ PARAMETER REGISTERS (for incoming args):                           │
│   w0, w1, w2, w3, w4, w5, w6, w7                                  │
│                                                                     │
│ SCRATCH REGISTERS (for our computations):                          │
│   w9, w10, w11, w12, w13, w14, w15                                │
│   → 7 registers for temporaries                                    │
│   → More than x86's 6 scratch registers!                          │
│                                                                     │
│ RESERVED:                                                           │
│   w8: indirect result (we won't use)                              │
│   w16, w17: platform scratch (avoid for simplicity)               │
│   w18: platform reserved (never use)                              │
│   w19-w28: callee-saved (would need save/restore)                 │
│   w29: frame pointer                                               │
│   w30: link register                                               │
│                                                                     │
│ RETURN VALUE:                                                       │
│   w0: copy result here before ret                                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Implementation:**

```
ARM64Gen {
    scratch_regs = ["w9", "w10", "w11", "w12", "w13", "w14", "w15"]
    param_regs = ["w0", "w1", "w2", "w3", "w4", "w5", "w6", "w7"]
    reg_map = {}  // ZIR index → register name
    next_reg = 0

    allocateRegister(index) -> string {
        reg = scratch_regs[next_reg]
        reg_map[index] = reg
        next_reg += 1
        return reg
    }

    getRegister(index) -> string {
        return reg_map[index]
    }
}
```

---

## Sub-lesson 4.3: ARM64's Register Advantage

### The Problem

What if we have more ZIR instructions than scratch registers?

### The Solution

ARM64 has many more registers than x86, making overflow rare:

```
┌─────────────────────────────────────────────────────────────────────┐
│ REGISTER COMPARISON                                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│                        ARM64         x86-64                         │
│ Total GPRs             31            16                             │
│ Parameter registers    8 (w0-w7)     6 (rdi, rsi, rdx, rcx, r8, r9)│
│ Scratch registers      7 (w9-w15)    6 (r10-r15)                   │
│ Callee-saved           10 (w19-w28)  5 (rbx, r12-r15)              │
│                                                                     │
│ For simple functions with <7 temporaries:                          │
│   → We never run out of registers!                                 │
│                                                                     │
│ If we DID run out (rare):                                          │
│   → Spill to stack: str wN, [sp, #offset]                         │
│   → Reload when needed: ldr wN, [sp, #offset]                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**For this tutorial:** We assume functions use ≤7 temporaries. Real compilers implement **spilling** to handle more.

**Complete allocation example:**

```
ZIR:
  %0 = param_ref(0)       // a
  %1 = param_ref(1)       // b
  %2 = add(%0, %1)        // a + b
  %3 = literal(2)         // 2
  %4 = mul(%2, %3)        // (a + b) * 2
  %5 = ret(%4)

Register allocation:
  %0 → w9  (copy from w0)
  %1 → w10 (copy from w1)
  %2 → w11 (add w9, w10)
  %3 → w12 (mov #2)
  %4 → w13 (mul w11, w12)

Generated code:
  mov     w9, w0          // %0 = param_ref(0)
  mov     w10, w1         // %1 = param_ref(1)
  add     w11, w9, w10    // %2 = add(%0, %1)
  mov     w12, #2         // %3 = literal(2)
  mul     w13, w11, w12   // %4 = mul(%2, %3)
  mov     w0, w13         // %5 = ret(%4)
  ret
```

---

## Summary: Register Allocation

```
┌────────────────────────────────────────────────────────────────────┐
│ ARM64 REGISTER ALLOCATION STRATEGY                                 │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ PARAMETERS:                                                        │
│   w0-w7: incoming arguments                                        │
│   Copy to scratch registers for use                               │
│                                                                    │
│ SCRATCH POOL:                                                      │
│   w9, w10, w11, w12, w13, w14, w15                                │
│   Allocate sequentially: ZIR %N → scratch_regs[N]                 │
│                                                                    │
│ RETURN:                                                            │
│   Copy final result to w0 before ret                              │
│                                                                    │
│ ALGORITHM:                                                         │
│   1. For each ZIR instruction:                                    │
│      - Allocate next available scratch register                   │
│      - Record mapping: index → register                           │
│   2. When referencing a previous result:                          │
│      - Look up register in mapping                                │
│   3. For return:                                                   │
│      - mov w0, <result_reg>                                       │
│      - ret                                                         │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Try It Yourself

Trace the register allocation for this function:

```
fn compute(x: i32) i32 {
    return (x + 1) * (x - 1);  // x² - 1
}
```

**ZIR:**
```
%0 = param_ref(0)    // x
%1 = literal(1)
%2 = add(%0, %1)     // x + 1
%3 = literal(1)
%4 = sub(%0, %3)     // x - 1
%5 = mul(%2, %4)     // (x+1) * (x-1)
%6 = ret(%5)
```

**Your task:** Write the ARM64 assembly with register allocation.

<details>
<summary>Solution</summary>

```asm
_compute:
    mov     w9, w0          // %0: x in w9
    mov     w10, #1         // %1: 1 in w10
    add     w11, w9, w10    // %2: x + 1 in w11
    mov     w12, #1         // %3: 1 in w12
    sub     w13, w9, w12    // %4: x - 1 in w13
    mul     w14, w11, w13   // %5: (x+1)*(x-1) in w14
    mov     w0, w14         // return result
    ret
```

Test it:
```bash
cat > compute.s << 'EOF'
    .text
    .globl _main
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     w0, #5          // compute(5) = 24
    bl      _compute
    ldp     x29, x30, [sp], #16
    ret

    .globl _compute
_compute:
    mov     w9, w0
    mov     w10, #1
    add     w11, w9, w10
    mov     w12, #1
    sub     w13, w9, w12
    mul     w14, w11, w13
    mov     w0, w14
    ret
EOF

cc -o compute compute.s
./compute
echo $?  # Should print 24 (5² - 1)
```
</details>

---

## What's Next

We have our register strategy. Now let's start generating actual code, beginning with the simplest case: constants.

**Next: [Lesson 5: Generating Constants](../05-gen-constants/)** →
