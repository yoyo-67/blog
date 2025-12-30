---
title: "Lesson 2: ARM64 Basics"
weight: 2
---

# Lesson 2: ARM64 Basics

Before generating code, you need to understand ARM64's building blocks: registers, instruction format, and operand types.

**What you'll learn:**
- The 31 general-purpose registers and their sizes
- Special-purpose registers (stack pointer, link register)
- Instruction format and operand types
- Common instructions we'll use

---

## Sub-lesson 2.1: General-Purpose Registers

### The Problem

How many registers does ARM64 have? What are they called?

### The Solution

ARM64 has **31 general-purpose registers**, numbered 0-30:

```
┌─────────────────────────────────────────────────────────────────────┐
│ ARM64 GENERAL-PURPOSE REGISTERS                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  64-bit name    32-bit name    Notes                               │
│  ──────────     ──────────     ─────                               │
│  x0             w0             First argument / return value       │
│  x1             w1             Second argument                     │
│  x2             w2             Third argument                      │
│  x3             w3             Fourth argument                     │
│  x4             w4             Fifth argument                      │
│  x5             w5             Sixth argument                      │
│  x6             w6             Seventh argument                    │
│  x7             w7             Eighth argument                     │
│  x8             w8             Indirect result location            │
│  x9             w9             Temporary / scratch                 │
│  x10            w10            Temporary / scratch                 │
│  x11            w11            Temporary / scratch                 │
│  x12            w12            Temporary / scratch                 │
│  x13            w13            Temporary / scratch                 │
│  x14            w14            Temporary / scratch                 │
│  x15            w15            Temporary / scratch                 │
│  x16            w16            Intra-procedure-call scratch       │
│  x17            w17            Intra-procedure-call scratch       │
│  x18            w18            Platform register (reserved)        │
│  x19            w19            Callee-saved                        │
│  x20            w20            Callee-saved                        │
│  x21            w21            Callee-saved                        │
│  x22            w22            Callee-saved                        │
│  x23            w23            Callee-saved                        │
│  x24            w24            Callee-saved                        │
│  x25            w25            Callee-saved                        │
│  x26            w26            Callee-saved                        │
│  x27            w27            Callee-saved                        │
│  x28            w28            Callee-saved                        │
│  x29            w29            Frame pointer (FP)                  │
│  x30            w30            Link register (LR)                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Key points:**
- `x` registers are 64-bit, `w` registers are the lower 32 bits of the same register
- Writing to `w0` clears the upper 32 bits of `x0`
- For our i32 type, we'll use `w` registers

**Compare to x86:**

| Feature | ARM64 | x86-64 |
|---------|-------|--------|
| Total GPRs | 31 | 16 |
| 64-bit names | x0-x30 | rax, rbx, ..., r15 |
| 32-bit names | w0-w30 | eax, ebx, ..., r15d |
| Naming | Numbered (simple) | Mixed names (complex) |

---

## Sub-lesson 2.2: Special Registers

### The Problem

Some registers have special purposes. What are they?

### The Solution

```
┌─────────────────────────────────────────────────────────────────────┐
│ SPECIAL-PURPOSE REGISTERS                                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ sp (Stack Pointer):                                                 │
│   - Points to the top of the stack                                 │
│   - Grows downward (toward lower addresses)                        │
│   - Must be 16-byte aligned                                        │
│   - Also accessible as x31 in some contexts                        │
│                                                                     │
│ x29 / FP (Frame Pointer):                                          │
│   - Points to the base of the current stack frame                  │
│   - Saved at function entry                                        │
│   - Used to access local variables and parameters                  │
│                                                                     │
│ x30 / LR (Link Register):                                          │
│   - Holds the return address after a `bl` (branch with link)       │
│   - `ret` jumps to the address in x30                              │
│   - Must be saved if we call other functions                       │
│                                                                     │
│ pc (Program Counter):                                               │
│   - Address of current instruction                                 │
│   - Not directly accessible as a GPR                               │
│   - Modified by branches and `ret`                                 │
│                                                                     │
│ xzr / wzr (Zero Register):                                         │
│   - Always reads as zero                                           │
│   - Writes are discarded                                           │
│   - Useful for comparisons and clearing                            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**The Link Register is Important:**

Unlike x86 where `call` pushes the return address to the stack, ARM64's `bl` (branch with link) stores the return address in `x30`:

```asm
// Calling a function
bl      some_function    // x30 = address of next instruction, jump to some_function

// Inside some_function
ret                      // jump to address in x30
```

If `some_function` calls another function, it must save `x30` first, or the original return address is lost!

---

## Sub-lesson 2.3: Instruction Format

### The Problem

How are ARM64 instructions structured? What's the general format?

### The Solution

Most ARM64 instructions follow one of these patterns:

```
┌─────────────────────────────────────────────────────────────────────┐
│ ARM64 INSTRUCTION FORMATS                                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ 3-operand (most arithmetic):                                        │
│   opcode  dst, src1, src2                                          │
│                                                                     │
│   add     w0, w1, w2       // w0 = w1 + w2                        │
│   sub     w0, w1, w2       // w0 = w1 - w2                        │
│   mul     w0, w1, w2       // w0 = w1 * w2                        │
│                                                                     │
│ 2-operand (moves, some ops):                                        │
│   opcode  dst, src                                                  │
│                                                                     │
│   mov     w0, w1           // w0 = w1                              │
│   mov     w0, #42          // w0 = 42                              │
│   neg     w0, w1           // w0 = -w1                             │
│                                                                     │
│ Immediate operand:                                                  │
│   opcode  dst, src, #imm                                           │
│                                                                     │
│   add     w0, w1, #10      // w0 = w1 + 10                        │
│   sub     w0, w0, #1       // w0 = w0 - 1                         │
│                                                                     │
│ Memory operations (explained in detail in Lesson 7):               │
│   ldr     dst, [base]                // load from memory address   │
│   str     src, [base]                // store to memory address    │
│   stp     r1, r2, [sp, #-16]!        // store pair (for prologue)  │
│   ldp     r1, r2, [sp], #16          // load pair (for epilogue)   │
│                                                                     │
│   The [brackets] mean "memory at this address"                     │
│   The ! means "also update the base register"                      │
│   Don't worry about these yet - we'll cover them in Lesson 7!      │
│                                                                     │
│ Branches:                                                           │
│   b       label            // unconditional branch                 │
│   bl      label            // branch with link (call)              │
│   ret                      // return (jump to x30)                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Key advantage over x86:** The destination is separate from the sources, so you don't destroy an operand:

```asm
// ARM64: clean, result in separate register
add     w2, w0, w1      // w2 = w0 + w1, w0 and w1 unchanged

// x86: must copy first if you need to preserve
movl    %eax, %edx      // copy eax to edx
addl    %ecx, %edx      // edx = edx + ecx (edx is modified)
```

---

## Sub-lesson 2.4: Common Instructions

### The Problem

What specific instructions will we use for code generation?

### The Solution

Here are the instructions we'll use in our backend:

```
┌─────────────────────────────────────────────────────────────────────┐
│ INSTRUCTIONS FOR CODE GENERATION                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ DATA MOVEMENT:                                                      │
│   mov   wD, wN           // wD = wN (register to register)        │
│   mov   wD, #imm         // wD = immediate value                  │
│                                                                     │
│ ARITHMETIC:                                                         │
│   add   wD, wN, wM       // wD = wN + wM                          │
│   sub   wD, wN, wM       // wD = wN - wM                          │
│   mul   wD, wN, wM       // wD = wN * wM                          │
│   sdiv  wD, wN, wM       // wD = wN / wM (signed)                 │
│                                                                     │
│ STACK OPERATIONS:                                                   │
│   stp   x29, x30, [sp, #-16]!   // save FP and LR to stack        │
│   ldp   x29, x30, [sp], #16     // restore FP and LR from stack   │
│                                                                     │
│   FP = Frame Pointer (x29) - base of our stack frame              │
│   LR = Link Register (x30) - return address                       │
│                                                                     │
│ CONTROL FLOW:                                                       │
│   b     label            // Branch (unconditional jump)           │
│   bl    label            // Branch with Link (call function)      │
│   ret                    // return (jump to address in x30)       │
│                                                                     │
│   bl = "Branch with Link" - jumps AND saves return address in x30 │
│                                                                     │
│ FRAME SETUP:                                                        │
│   mov   x29, sp          // set frame pointer to stack pointer    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Division is Simple!**

Unlike x86 where division requires setting up `eax`/`edx` and using `idivl`, ARM64 division is just:

```asm
// ARM64: simple 3-operand division
sdiv    w2, w0, w1      // w2 = w0 / w1

// x86: complex multi-instruction sequence
movl    %eax_val, %eax  // dividend in eax
cdq                      // sign-extend to edx:eax
idivl   %divisor        // quotient in eax, remainder in edx
```

---

## Summary: ARM64 Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│ ARM64 ARCHITECTURE SUMMARY                                         │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ REGISTERS:                                                         │
│   General:  x0-x30 (64-bit), w0-w30 (32-bit)                      │
│   Special:  sp (stack), x29 (frame), x30 (link/return)            │
│   Zero:     xzr/wzr (always zero)                                 │
│                                                                    │
│ INSTRUCTION FORMAT:                                                │
│   op  dst, src1, src2     (most arithmetic)                       │
│   op  dst, src            (moves)                                 │
│   op  dst, src, #imm      (immediate operand)                     │
│                                                                    │
│ FOR i32:                                                           │
│   Use w registers (w0-w30)                                        │
│   Use mov, add, sub, mul, sdiv                                    │
│                                                                    │
│ CALLING:                                                           │
│   bl label  - call (return address → x30)                         │
│   ret       - return (jump to x30)                                │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Try It Yourself

Experiment with basic ARM64 instructions:

```bash
cat > basics.s << 'EOF'
    .text
    .globl _main
_main:
    // ─────────────────────────────────────────────────────────────
    // These two lines are the "prologue" - explained in Lesson 7
    // For now, just know: every function needs these at the start
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    // ─────────────────────────────────────────────────────────────

    // Simple arithmetic: (10 + 5) * 2 = 30
    mov     w0, #10         // w0 = 10
    mov     w1, #5          // w1 = 5
    add     w2, w0, w1      // w2 = 15
    mov     w3, #2          // w3 = 2
    mul     w0, w2, w3      // w0 = 30 (result in w0 for return)

    // ─────────────────────────────────────────────────────────────
    // These two lines are the "epilogue" - explained in Lesson 7
    // For now, just know: every function needs these at the end
    ldp     x29, x30, [sp], #16
    ret
    // ─────────────────────────────────────────────────────────────
EOF

cc -o basics basics.s
./basics
echo $?  # Should print 30
```

Try division:

```bash
cat > div.s << 'EOF'
    .text
    .globl _main
_main:
    // Prologue (explained in Lesson 7)
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // 100 / 4 = 25
    mov     w0, #100
    mov     w1, #4
    sdiv    w0, w0, w1      // w0 = 25

    // Epilogue (explained in Lesson 7)
    ldp     x29, x30, [sp], #16
    ret
EOF

cc -o div div.s
./div
echo $?  # Should print 25
```

**For Linux ARM64**, remove the underscore from `_main`.

**What's with the stp/ldp lines?** These are the function prologue and epilogue - boilerplate that every function needs. We'll explain exactly what they do in Lesson 7. For now, just copy them and focus on the arithmetic in the middle!

---

## What's Next

We understand the registers and instructions. Now let's learn how functions pass parameters and return values - the ARM64 calling convention.

**Next: [Lesson 3: Calling Convention](../03-calling-convention/)** →
