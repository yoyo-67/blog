---
title: "Lesson 3: Calling Convention"
weight: 3
---

# Lesson 3: ARM64 Calling Convention (AAPCS64)

Functions need to agree on how to pass parameters and return values. ARM64 uses the AAPCS64 (ARM Architecture Procedure Call Standard for 64-bit).

**What you'll learn:**
- How parameters are passed (x0-x7)
- Where return values go (x0)
- Which registers are preserved across calls
- The role of the link register

---

## Sub-lesson 3.1: Parameter Passing

### The Problem

When calling `add(10, 5)`, where do the arguments go?

### The Solution

The first 8 integer/pointer arguments go in registers x0-x7:

```
┌─────────────────────────────────────────────────────────────────────┐
│ PARAMETER REGISTERS (AAPCS64)                                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Argument    64-bit reg    32-bit reg    Our use (i32)              │
│ ────────    ──────────    ──────────    ────────────               │
│ 1st         x0            w0            ✓                          │
│ 2nd         x1            w1            ✓                          │
│ 3rd         x2            w2            ✓                          │
│ 4th         x3            w3            ✓                          │
│ 5th         x4            w4            ✓                          │
│ 6th         x5            w5            ✓                          │
│ 7th         x6            w6            ✓                          │
│ 8th         x7            w7            ✓                          │
│ 9th+        stack         stack         (not needed for simple)    │
│                                                                     │
│ For i32 values, use w0-w7 (32-bit versions)                        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Example - calling add(10, 5):**

```asm
mov     w0, #10         // first argument in w0
mov     w1, #5          // second argument in w1
bl      _add            // call add function
// result is now in w0
```

**Compare to x86:**

| Argument | ARM64 | x86-64 |
|----------|-------|--------|
| 1st | x0/w0 | rdi/edi |
| 2nd | x1/w1 | rsi/esi |
| 3rd | x2/w2 | rdx/edx |
| 4th | x3/w3 | rcx/ecx |
| 5th | x4/w4 | r8/r8d |
| 6th | x5/w5 | r9/r9d |
| 7th | x6/w6 | stack |
| 8th | x7/w7 | stack |

ARM64 can pass **8 arguments** in registers vs x86's 6. More registers = fewer stack operations!

---

## Sub-lesson 3.2: Return Values

### The Problem

After calling a function, where is the return value?

### The Solution

Integer return values are in **x0** (or **w0** for 32-bit):

```
┌─────────────────────────────────────────────────────────────────────┐
│ RETURN VALUE LOCATION                                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Return Type        Register                                        │
│ ───────────        ────────                                        │
│ i32, u32           w0 (lower 32 bits of x0)                        │
│ i64, u64           x0                                              │
│ pointer            x0                                              │
│ bool               w0 (0 or 1)                                     │
│                                                                     │
│ To return a value:                                                  │
│   mov   w0, wN     // put result in w0                             │
│   ret              // return to caller                             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Example - function returning a + b:**

```asm
// fn add(a: i32, b: i32) -> i32
_add:
    add     w0, w0, w1      // w0 = w0 + w1, result in w0
    ret                      // return (result already in w0!)
```

Notice how clean this is - if the first argument is also part of the result, we can operate directly:

```asm
// a + b: arguments in w0, w1, result in w0
add     w0, w0, w1      // That's it! No extra mov needed
```

---

## Sub-lesson 3.3: Register Preservation

### The Problem

You have a value in a register, then you call a function. Is your value still there when the call returns?

### The Solution

Think of it this way: **when you call a function, some registers get TRASHED and some SURVIVE.**

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHAT HAPPENS TO REGISTERS WHEN YOU CALL A FUNCTION? (AAPCS64)       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ TRASHED BY CALLS (assume your value is gone):                      │
│   x0-x18                                                           │
│   ├── x0-x7: arguments / return value                             │
│   ├── x8: indirect result location                                │
│   └── x9-x18: temporaries                                         │
│                                                                     │
│   The function you call is FREE to overwrite these.                │
│                                                                     │
│ SURVIVE CALLS (your value is safe):                                │
│   x19-x28                                                          │
│   The function you call MUST restore these before returning.       │
│                                                                     │
│ SPECIAL (also survive):                                            │
│   x29 (FP): frame pointer                                         │
│   x30 (LR): link register - but gets overwritten by `bl`!         │
│   sp: stack pointer                                                │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Simple mental model:**

```
                         bl some_function
                               │
    ┌──────────────────────────┼──────────────────────────┐
    │                          │                          │
    ▼                          ▼                          ▼
┌────────┐              ┌────────────┐              ┌────────┐
│ BEFORE │              │   DURING   │              │ AFTER  │
├────────┤              ├────────────┤              ├────────┤
│w9  = 5 │              │ function   │              │w9  = ? │ ← TRASHED!
│w10 = 3 │      ──►     │ can do     │      ──►     │w10 = ? │ ← TRASHED!
│w19 = 7 │              │ whatever   │              │w19 = 7 │ ← SAFE!
│w20 = 9 │              │ it wants   │              │w20 = 9 │ ← SAFE!
└────────┘              └────────────┘              └────────┘
```

**The catch with "safe" registers:** If YOU want to use x19-x28, YOU must save and restore them (because your caller expects them unchanged).

**For our simple compiler:** We'll use w9-w15 as scratch registers (they get trashed). We won't rely on values surviving across function calls.

**Terminology note:** You'll see these called "caller-saved" vs "callee-saved" elsewhere:
- "Caller-saved" = trashed = if the CALLER needs the value, CALLER must save it
- "Callee-saved" = survives = the CALLEE promises to restore it

---

## Sub-lesson 3.4: The Link Register

### The Problem

In x86, `call` pushes the return address onto the stack. How does ARM64 handle returns?

### The Solution

ARM64 uses a **link register (x30)** instead of the stack:

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE LINK REGISTER (x30 / LR)                                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ When you execute:                                                   │
│   bl    target_function                                            │
│                                                                     │
│ This happens:                                                       │
│   1. x30 = address of instruction after bl                         │
│   2. pc = target_function (jump to function)                       │
│                                                                     │
│ When the called function executes:                                  │
│   ret                                                               │
│                                                                     │
│ This happens:                                                       │
│   1. pc = x30 (jump to return address)                             │
│                                                                     │
│ IMPORTANT: If a function calls another function, it must           │
│ save x30 first, or the original return address is lost!            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Standard prologue saves x30:**

```asm
_my_function:
    stp     x29, x30, [sp, #-16]!   // save FP and LR to stack
    mov     x29, sp                  // set up frame pointer

    // ... function body ...
    // can safely call other functions here

    ldp     x29, x30, [sp], #16     // restore FP and LR
    ret                              // return using restored x30
```

**Leaf functions (functions that don't call others):**

```asm
_leaf_function:
    // No need to save x30 - we don't call anything
    add     w0, w0, w1
    ret
```

---

## Complete Calling Convention Example

Let's trace a complete function call:

```
Source:
fn multiply(a: i32, b: i32) i32 {
    return a * b;
}

fn main() i32 {
    return multiply(6, 7);
}

ARM64 assembly:
```

```asm
    .text

    .globl _multiply
_multiply:
    // Leaf function - no prologue needed
    mul     w0, w0, w1      // w0 = a * b
    ret

    .globl _main
_main:
    // Non-leaf - must save LR since we call multiply
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Set up arguments
    mov     w0, #6          // first arg
    mov     w1, #7          // second arg

    // Call multiply
    bl      _multiply       // result in w0

    // Return (w0 already has result)
    ldp     x29, x30, [sp], #16
    ret
```

**Execution trace:**

```
1. main starts
   - Saves x29, x30 to stack
   - Sets w0=6, w1=7

2. bl _multiply
   - x30 = address after bl
   - Jump to _multiply

3. multiply runs
   - mul w0, w0, w1 → w0 = 42
   - ret → jump to x30

4. Back in main
   - w0 = 42 (our result)
   - Restore x29, x30
   - ret → return 42
```

---

## Summary: AAPCS64 Calling Convention

```
┌────────────────────────────────────────────────────────────────────┐
│ AAPCS64 QUICK REFERENCE                                            │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ ARGUMENTS:                                                         │
│   x0-x7 (w0-w7 for 32-bit)                                        │
│   8 register arguments vs x86's 6                                  │
│                                                                    │
│ RETURN VALUE:                                                      │
│   x0 (w0 for 32-bit)                                              │
│                                                                    │
│ CALLER-SAVED (scratch):                                            │
│   x0-x18 - may be clobbered by calls                              │
│                                                                    │
│ CALLEE-SAVED (preserved):                                          │
│   x19-x28 - must save if you use them                             │
│   x29 (FP), x30 (LR), sp                                          │
│                                                                    │
│ LINK REGISTER:                                                     │
│   x30 holds return address after bl                               │
│   Must save if calling other functions                            │
│                                                                    │
│ STANDARD PROLOGUE:                                                 │
│   stp  x29, x30, [sp, #-16]!                                      │
│   mov  x29, sp                                                     │
│                                                                    │
│ STANDARD EPILOGUE:                                                 │
│   ldp  x29, x30, [sp], #16                                        │
│   ret                                                              │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Try It Yourself

Write a function that takes 4 parameters:

```bash
cat > fourargs.s << 'EOF'
    .text

    .globl _sum4
_sum4:
    // sum4(a, b, c, d) = a + b + c + d
    // Arguments: w0, w1, w2, w3
    add     w0, w0, w1      // w0 = a + b
    add     w0, w0, w2      // w0 = a + b + c
    add     w0, w0, w3      // w0 = a + b + c + d
    ret

    .globl _main
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // sum4(10, 20, 30, 40) = 100
    mov     w0, #10
    mov     w1, #20
    mov     w2, #30
    mov     w3, #40
    bl      _sum4

    ldp     x29, x30, [sp], #16
    ret
EOF

cc -o fourargs fourargs.s
./fourargs
echo $?  # Should print 100
```

---

## What's Next

We understand how functions communicate. Now let's plan our register allocation strategy - how we'll map ZIR instructions to physical registers.

**Next: [Lesson 4: Register Allocation](../04-register-allocation/)** →
