---
title: "Lesson 8: Generating Function Calls"
weight: 8
---

# Lesson 8: Generating Function Calls

When your code calls a function, you need to set up arguments, execute the call, and capture the return value. This lesson shows you how.

**What you'll learn:**
- Moving arguments into parameter registers
- The `bl` (branch with link) instruction
- Capturing the return value
- Understanding caller-saved registers

---

## Sub-lesson 8.1: Setting Up Arguments

### The Problem

Given a function call like `add(10, 5)`, we need to:
1. Put `10` in w0 (first parameter)
2. Put `5` in w1 (second parameter)
3. Call the function

But our values might already be in scratch registers. How do we move them to the parameter registers?

### The Solution

Before the call, copy each argument to its designated parameter register:

```asm
// Call add(w9, w10) where w9=10, w10=5
mov     w0, w9          // arg 0 → w0
mov     w1, w10         // arg 1 → w1
bl      _add            // call add
```

**Implementation:**

```
param_regs = ["w0", "w1", "w2", "w3", "w4", "w5", "w6", "w7"]

generateCall(index, fn_name, arg_indices) {
    // Move each argument to its parameter register
    for i, arg_index in arg_indices {
        arg_reg = getRegister(arg_index)
        param_reg = param_regs[i]
        emit("    mov     {}, {}", param_reg, arg_reg)
    }

    // Execute the call
    emit("    bl      _{}", fn_name)

    // Capture return value
    dst_reg = allocateRegister(index)
    emit("    mov     {}, w0", dst_reg)
}
```

---

## Sub-lesson 8.2: The Branch with Link Instruction

### The Problem

What does `bl` actually do? How is it different from x86's `call`?

### The Solution

`bl` (branch with link) does two things:
1. Stores the return address in **x30** (the link register)
2. Jumps to the target label

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHAT "bl" DOES                                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│     bl      _some_function                                         │
│                                                                     │
│ Is equivalent to:                                                   │
│     x30 = address of next instruction                              │
│     pc = _some_function (jump to function)                         │
│                                                                     │
│ When the called function executes "ret":                            │
│     pc = x30 (jump back to return address)                         │
│                                                                     │
│ Compare to x86 "call":                                              │
│   x86 call:  push return_addr; jmp target                          │
│   ARM64 bl:  x30 = return_addr; branch to target                   │
│                                                                     │
│ Key difference: x86 uses stack, ARM64 uses a register              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

This is why we save x30 in the prologue - if we call another function, our return address would be overwritten!

---

## Sub-lesson 8.3: Getting the Return Value

### The Problem

After `bl _add` returns, where is the result?

### The Solution

The return value is in **w0**. Copy it to your scratch register:

```asm
bl      _add            // call add
mov     w11, w0         // save result to w11
```

**Complete call sequence:**

```asm
// result = add(x, y)
// where x is in w9, y is in w10

mov     w0, w9          // arg 0
mov     w1, w10         // arg 1
bl      _add            // call function
mov     w11, w0         // save result (now result is in w11)
```

---

## Sub-lesson 8.4: Caller-Saved Registers

### The Problem

When we call a function, which registers might be destroyed? Registers w0-w18 are **caller-saved** - the called function can freely modify them.

### The Solution

**Option 1: Accept the limitation**

For simple code, just be careful about register usage across calls:
- Use the result immediately
- Don't expect values in w0-w15 to survive calls

**Option 2: Save registers before call**

If you need values to survive a call, save them to the stack:

```asm
// We need w9 to survive the call
str     w9, [sp, #-16]!     // push w9
mov     w0, w10              // set up args
bl      _some_function
ldr     w9, [sp], #16       // pop w9
// Now w9 still has our value
```

**Option 3: Use callee-saved registers**

Registers w19-w28 are preserved across calls. If you use them, save them in the prologue:

```asm
_foo:
    stp     x29, x30, [sp, #-32]!
    stp     x19, x20, [sp, #16]   // save callee-saved regs we'll use
    mov     x29, sp

    // use w19, w20 freely - they survive calls

    ldp     x19, x20, [sp, #16]   // restore
    ldp     x29, x30, [sp], #32
    ret
```

**For our simple compiler:** We use option 1. Each call result goes to a new scratch register, and we don't rely on values surviving across calls.

---

## Complete Call Generation Example

```
Source:
fn double(x: i32) i32 {
    return x * 2;
}

fn main() i32 {
    return double(21);
}

ZIR for main:
  %0 = literal(21)
  %1 = call(double, [%0])
  %2 = ret(%1)

Generated ARM64:
    .globl _double
_double:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     w9, w0          // x
    mov     w10, #2         // 2
    mul     w11, w9, w10    // x * 2
    mov     w0, w11
    ldp     x29, x30, [sp], #16
    ret

    .globl _main
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     w9, #21         // %0 = literal(21)
    mov     w0, w9          // set up arg for call
    bl      _double         // %1 = call(double, [%0])
    mov     w10, w0         // save return value
    mov     w0, w10         // %2 = ret(%1)
    ldp     x29, x30, [sp], #16
    ret
```

---

## Summary: Function Call Generation

```
┌────────────────────────────────────────────────────────────────────┐
│ ARM64 FUNCTION CALL PATTERN                                        │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ // result = fn(arg0, arg1, arg2)                                  │
│                                                                    │
│ mov     w0, wArg0         // set up argument 0                    │
│ mov     w1, wArg1         // set up argument 1                    │
│ mov     w2, wArg2         // set up argument 2                    │
│ bl      _fn               // call the function (x30 = return)     │
│ mov     wResult, w0       // capture return value                 │
│                                                                    │
│ ARGUMENT REGISTERS (in order):                                    │
│   w0, w1, w2, w3, w4, w5, w6, w7                                 │
│                                                                    │
│ RETURN VALUE:                                                     │
│   w0                                                              │
│                                                                    │
│ Compare to x86:                                                   │
│   ARM64: bl _fn            (return addr in x30)                   │
│   x86:   call fn           (return addr on stack)                 │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Try It Yourself

Write a program with two functions that call each other:

```bash
cat > calls.s << 'EOF'
    .text

    .globl _square
_square:
    // square(x) = x * x
    // Leaf function - could skip prologue, but including for consistency
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mul     w0, w0, w0      // w0 = x * x (result already in w0!)
    ldp     x29, x30, [sp], #16
    ret

    .globl _add_squares
_add_squares:
    // add_squares(a, b) = square(a) + square(b)
    stp     x29, x30, [sp, #-32]!
    stp     x19, x20, [sp, #16]     // save callee-saved regs
    mov     x29, sp

    // Save 'b' in w20 (survives the call to square(a))
    mov     w20, w1

    // call square(a) - w0 already has 'a'
    bl      _square
    mov     w19, w0         // w19 = square(a)

    // call square(b)
    mov     w0, w20         // b was saved in w20
    bl      _square
    // w0 = square(b)

    // return square(a) + square(b)
    add     w0, w19, w0

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

    .globl _main
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // add_squares(3, 4) = 9 + 16 = 25
    mov     w0, #3
    mov     w1, #4
    bl      _add_squares

    ldp     x29, x30, [sp], #16
    ret
EOF

cc -o calls calls.s
./calls
echo $?  # Should print 25
```

---

## What's Next

We have all the pieces. Now let's put them together into a complete code generator that produces working executables.

**Next: [Lesson 9: Complete Backend](../09-complete/)** →
