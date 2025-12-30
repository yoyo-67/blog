---
title: "Lesson 7: Generating Functions"
weight: 7
---

# Lesson 7: Generating Functions

Functions need special structure: labels, stack frame setup, parameter access, and proper returns. This lesson shows you how to generate complete function bodies.

**What you'll learn:**
- Function labels and visibility
- Stack frame prologue and epilogue
- Accessing function parameters
- Generating return statements

---

## Sub-lesson 7.1: Function Labels

### The Problem

Each function needs a label so it can be called. We also need to mark which functions are visible outside our assembly file.

### The Solution

Use `.globl` to export the function, then define its label:

```asm
    .text                   // Code section
    .globl _add             // Export "add" symbol (macOS uses underscore)
_add:                       // Label for the function
    // function body here
```

**macOS vs Linux:**

| Platform | Label Style |
|----------|-------------|
| macOS | `_main`, `_add` (underscore prefix) |
| Linux | `main`, `add` (no prefix) |

**Implementation:**

```
generateFunctionHeader(name) {
    if (macOS) {
        emit("    .globl _{}", name)
        emit("_{}:", name)
    } else {
        emit("    .globl {}", name)
        emit("{}:", name)
    }
}
```

---

## Sub-lesson 7.2: The Stack and Function Prologue

### First: What is the Stack?

Before we write any code, let's understand what the **stack** is:

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHAT IS THE STACK?                                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ The stack is a region of memory that programs use for:             │
│   - Storing return addresses (where to go back after a call)       │
│   - Saving register values temporarily                             │
│   - Local variables (in more complex functions)                    │
│                                                                     │
│ KEY PROPERTY: The stack grows DOWNWARD in memory.                  │
│                                                                     │
│          High addresses                                             │
│                 │                                                   │
│        ┌────────▼────────┐                                         │
│        │  older stuff    │                                         │
│        ├─────────────────┤                                         │
│        │  more stuff     │                                         │
│        ├─────────────────┤                                         │
│        │  newest item    │ ◄── sp (stack pointer) points here      │
│        └─────────────────┘                                         │
│                 │                                                   │
│                 ▼                                                   │
│          Low addresses (stack grows this way)                       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### What is the Stack Pointer (sp)?

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE STACK POINTER (sp)                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ sp = "Stack Pointer"                                                │
│                                                                     │
│ It's a special register that ALWAYS points to the top of the       │
│ stack (the most recently stored item).                             │
│                                                                     │
│ In ARM64, we don't have push/pop instructions like x86.            │
│ Instead, we use store/load with sp:                                │
│                                                                     │
│   str x0, [sp, #-16]!  → store x0, sp decreases by 16             │
│   ldr x0, [sp], #16    → load into x0, sp increases by 16         │
│                                                                     │
│ The `stp` instruction stores TWO registers at once (store pair).  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### How Does Returning Work? (ARM64 vs x86)

This is a key difference between ARM64 and x86:

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE LINK REGISTER (x30) - ARM64's WAY OF RETURNING                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ x86: When you call a function, the return address is               │
│      PUSHED ONTO THE STACK automatically.                          │
│                                                                     │
│ ARM64: When you call a function, the return address goes           │
│        INTO A REGISTER (x30, called "Link Register" or LR).        │
│                                                                     │
│ EXAMPLE:                                                            │
│                                                                     │
│   Address    Instruction                                           │
│   ───────    ───────────                                           │
│   0x1000     mov w0, #5                                            │
│   0x1004     bl  add           ← about to call                     │
│   0x1008     mov w9, w0        ← return address                    │
│                                                                     │
│ When 'bl add' executes:                                            │
│   1. x30 = 0x1008 (the return address)                            │
│   2. CPU jumps to 'add' function                                   │
│                                                                     │
│ When 'ret' executes:                                               │
│   1. CPU jumps to address in x30 (0x1008)                         │
│                                                                     │
│ THE CATCH: If our function calls ANOTHER function, 'bl' will       │
│ overwrite x30! So we must SAVE x30 to the stack first.             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### What is a Stack Frame?

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHAT IS A STACK FRAME?                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Each function call gets its own "workspace" on the stack.          │
│ This workspace is called a STACK FRAME.                            │
│                                                                     │
│ When main() calls foo() which calls bar():                         │
│                                                                     │
│        ┌─────────────────┐                                         │
│        │  main's frame   │  main's workspace                       │
│        ├─────────────────┤                                         │
│        │  foo's frame    │  foo's workspace                        │
│        ├─────────────────┤                                         │
│        │  bar's frame    │  bar's workspace (current)              │
│        └─────────────────┘                                         │
│                 ▲                                                   │
│                sp                                                   │
│                                                                     │
│ When bar() returns, its frame is "popped" and foo continues.       │
│ When foo() returns, its frame is "popped" and main continues.      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### What is the Frame Pointer (x29)?

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE FRAME POINTER (x29)                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ x29 = "Frame Pointer" (also called FP)                             │
│                                                                     │
│ THE PROBLEM: sp moves around as we store/load things.              │
│              This makes it hard to find our stuff!                 │
│                                                                     │
│ THE SOLUTION: x29 stays FIXED for the entire function.             │
│               It marks the "base" of our stack frame.              │
│                                                                     │
│ Think of it like this:                                              │
│                                                                     │
│   x29 = "the floor of our room" (doesn't move)                     │
│   sp = "where we're currently stacking boxes" (moves around)       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### The Problem

Now we understand the pieces. At function entry, we need to:
1. Save the CALLER's x29 (so we can restore it when we return)
2. Save x30 (the return address, in case we call other functions)
3. Set up OUR x29 to point to our frame

### The Solution: The Prologue

The **prologue** is the setup code at the start of every function:

```asm
_function:
    stp     x29, x30, [sp, #-16]!   // Save FP and LR, decrement SP by 16
    mov     x29, sp                  // Our FP = current SP
```

**Step by step:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ PROLOGUE STEP BY STEP                                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ BEFORE (just entered function via 'bl'):                           │
│                                                                     │
│   sp → ┌──────────────┐                                            │
│        │ caller's     │                                            │
│        │ stack frame  │                                            │
│        └──────────────┘                                            │
│                                                                     │
│   x29 still points to caller's frame                               │
│   x30 holds our return address (set by 'bl')                       │
│                                                                     │
│ ─────────────────────────────────────────────────────────────────  │
│                                                                     │
│ AFTER: stp x29, x30, [sp, #-16]!                                   │
│                                                                     │
│   sp → ┌──────────────┐                                            │
│        │ saved x30    │  ← return address (so we can call others) │
│        │ saved x29    │  ← caller's frame pointer                 │
│        ├──────────────┤                                            │
│        │ caller's     │                                            │
│        │ stack frame  │                                            │
│        └──────────────┘                                            │
│                                                                     │
│ ─────────────────────────────────────────────────────────────────  │
│                                                                     │
│ AFTER: mov x29, sp                                                  │
│                                                                     │
│ sp,x29→ ┌──────────────┐                                           │
│         │ saved x30    │                                           │
│         │ saved x29    │ ← x29 now marks OUR frame's base         │
│         ├──────────────┤                                           │
│         │ caller's     │                                           │
│         │ stack frame  │                                           │
│         └──────────────┘                                           │
│                                                                     │
│ Now x29 is set! It won't move until we return.                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Implementation:**

```
generatePrologue() {
    emit("    stp     x29, x30, [sp, #-16]!")
    emit("    mov     x29, sp")
}
```

**For leaf functions** (functions that don't call others), the prologue is optional since we don't need to save x30. But we'll include it for consistency.

---

## Sub-lesson 7.3: Accessing Parameters

### The Problem

Function parameters arrive in registers w0-w7. We need to make them available for computation.

### The Solution

Copy parameters to our scratch registers:

```asm
// fn foo(a: i32, b: i32, c: i32)
// a in w0, b in w1, c in w2
_foo:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     w9, w0          // a → w9
    mov     w10, w1         // b → w10
    mov     w11, w2         // c → w11
    // now use w9, w10, w11 in function body
```

**Parameter register mapping:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ PARAMETER LOCATIONS (i32)                                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Parameter #   Arrives in     Copy to (our allocation)              │
│ ───────────   ──────────     ────────────────────────              │
│ 0             w0             w9 (first scratch)                    │
│ 1             w1             w10                                   │
│ 2             w2             w11                                   │
│ 3             w3             w12                                   │
│ 4             w4             w13                                   │
│ 5             w5             w14                                   │
│ 6             w6             w15                                   │
│ 7             w7             (would need more scratch)             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Implementation:**

```
param_regs = ["w0", "w1", "w2", "w3", "w4", "w5", "w6", "w7"]

generateParamRef(index, param_index) {
    src_reg = param_regs[param_index]
    dst_reg = allocateRegister(index)
    emit("    mov     {}, {}", dst_reg, src_reg)
}
```

---

## Sub-lesson 7.4: Generating Returns

### The Problem

When ZIR has a `ret` instruction, we need to:
1. Move the return value to w0
2. Restore the stack frame
3. Return to the caller

### The Solution

```asm
    mov     w0, wN              // Put return value in w0
    ldp     x29, x30, [sp], #16 // Restore FP and LR, increment SP
    ret                          // Return (jump to address in x30)
```

**Implementation:**

```
generateReturn(value_index) {
    value_reg = getRegister(value_index)
    emit("    mov     w0, {}", value_reg)
    emit("    ldp     x29, x30, [sp], #16")
    emit("    ret")
}
```

---

## Sub-lesson 7.5: Complete Function Generation

### Putting It All Together

Here's the complete flow for generating a function:

```
generateFunction(func) {
    // Reset register allocation
    next_reg = 0
    reg_map = {}

    // 1. Header
    emit("    .globl _{}", func.name)
    emit("_{}:", func.name)

    // 2. Prologue
    emit("    stp     x29, x30, [sp, #-16]!")
    emit("    mov     x29, sp")

    // 3. Generate each instruction
    for index, instruction in func.zir.instructions {
        generateInstruction(index, instruction)
    }
}

generateInstruction(index, instruction) {
    switch instruction {
        literal(value):
            reg = allocateRegister(index)
            emit("    mov     {}, #{}", reg, value)

        param_ref(param_index):
            src = param_regs[param_index]
            dst = allocateRegister(index)
            emit("    mov     {}, {}", dst, src)

        add(lhs, rhs):
            generateBinaryOp(index, "add", lhs, rhs)

        sub(lhs, rhs):
            generateBinaryOp(index, "sub", lhs, rhs)

        mul(lhs, rhs):
            generateBinaryOp(index, "mul", lhs, rhs)

        div(lhs, rhs):
            generateBinaryOp(index, "sdiv", lhs, rhs)

        ret(value):
            value_reg = getRegister(value)
            emit("    mov     w0, {}", value_reg)
            emit("    ldp     x29, x30, [sp], #16")
            emit("    ret")
    }
}
```

**Complete example:**

```
Source:
fn add(a: i32, b: i32) i32 {
    return a + b;
}

ZIR:
  %0 = param_ref(0)
  %1 = param_ref(1)
  %2 = add(%0, %1)
  %3 = ret(%2)

Generated ARM64 (macOS):
    .globl _add
_add:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    mov     w9, w0          // %0 = param_ref(0)
    mov     w10, w1         // %1 = param_ref(1)
    add     w11, w9, w10    // %2 = add(%0, %1)
    mov     w0, w11         // %3 = ret(%2)
    ldp     x29, x30, [sp], #16
    ret
```

---

## Summary: Function Generation

```
┌────────────────────────────────────────────────────────────────────┐
│ ARM64 FUNCTION GENERATION TEMPLATE                                 │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│     .globl _functionname          // export (macOS style)         │
│ _functionname:                                                     │
│     stp     x29, x30, [sp, #-16]! // prologue: save FP, LR        │
│     mov     x29, sp                                                │
│                                                                    │
│     // copy parameters to scratch registers                       │
│     mov     w9, w0                // param 0                      │
│     mov     w10, w1               // param 1                      │
│     ...                                                            │
│                                                                    │
│     // function body                                               │
│     ...                                                            │
│                                                                    │
│     // return                                                      │
│     mov     w0, wResult           // set return value             │
│     ldp     x29, x30, [sp], #16   // epilogue: restore FP, LR     │
│     ret                                                            │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Try It Yourself

Write a function that computes `a * b + c`:

```bash
cat > func.s << 'EOF'
    .text

    .globl _compute
_compute:
    // compute(a, b, c) = a * b + c
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // %0 = param_ref(0) - a
    mov     w9, w0

    // %1 = param_ref(1) - b
    mov     w10, w1

    // %2 = param_ref(2) - c
    mov     w11, w2

    // %3 = mul(%0, %1) - a * b
    mul     w12, w9, w10

    // %4 = add(%3, %2) - (a * b) + c
    add     w13, w12, w11

    // ret %4
    mov     w0, w13
    ldp     x29, x30, [sp], #16
    ret

    .globl _main
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // compute(5, 8, 2) = 5 * 8 + 2 = 42
    mov     w0, #5
    mov     w1, #8
    mov     w2, #2
    bl      _compute

    ldp     x29, x30, [sp], #16
    ret
EOF

cc -o func func.s
./func
echo $?  # Should print 42
```

---

## What's Next

We can generate individual functions. Now let's handle function calls: setting up arguments and capturing return values.

**Next: [Lesson 8: Generating Function Calls](../08-gen-calls/)** →
