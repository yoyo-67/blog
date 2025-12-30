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
    .text                   # Code section
    .globl add              # Export "add" symbol
add:                        # Label for the function
    # function body here
```

**Implementation:**

```
generateFunctionHeader(name) {
    emit("    .globl {}", name)
    emit("{}:", name)
}
```

**Example:**

```
fn main() i32 { return 42; }
fn helper(x: i32) i32 { return x * 2; }

Output:
    .text
    .globl main
main:
    # main body...

    .globl helper
helper:
    # helper body...
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
│        │  newest item    │ ◄── rsp (stack pointer) points here     │
│        └─────────────────┘                                         │
│                 │                                                   │
│                 ▼                                                   │
│          Low addresses (stack grows this way)                       │
│                                                                     │
│ When you "push" something, rsp decreases (moves down)              │
│ When you "pop" something, rsp increases (moves up)                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### What is the Stack Pointer (rsp)?

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE STACK POINTER (rsp)                                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ rsp = "Register: Stack Pointer"                                    │
│                                                                     │
│ It's a special register that ALWAYS points to the top of the       │
│ stack (the most recently pushed item).                             │
│                                                                     │
│ When you do:                                                        │
│   pushq %rax    → rsp decreases by 8, value stored at new rsp     │
│   popq %rax     → value loaded from rsp, rsp increases by 8       │
│                                                                     │
│ The CPU automatically updates rsp on push/pop.                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### What is the Return Address?

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE RETURN ADDRESS                                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ When you call a function, how does the CPU know where to go back?  │
│                                                                     │
│ The RETURN ADDRESS is the memory address of the instruction        │
│ right after the 'call' instruction.                                │
│                                                                     │
│ EXAMPLE:                                                            │
│                                                                     │
│   Address    Instruction                                           │
│   ───────    ───────────                                           │
│   0x1000     movl $5, %edi                                         │
│   0x1005     call add          ← CPU is here, about to call       │
│   0x100A     movl %eax, %r10d  ← return address (next instruction) │
│   0x100E     ...                                                   │
│                                                                     │
│ When 'call add' executes:                                          │
│   1. CPU pushes 0x100A onto the stack (the return address)        │
│   2. CPU jumps to the 'add' function                               │
│                                                                     │
│ When 'ret' executes (in the add function):                         │
│   1. CPU pops the return address from the stack                    │
│   2. CPU jumps to that address (0x100A)                            │
│   3. Execution continues after the original call                   │
│                                                                     │
│ This is how functions know where to return to!                     │
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
│                rsp                                                  │
│                                                                     │
│ When bar() returns, its frame is "popped" and foo continues.       │
│ When foo() returns, its frame is "popped" and main continues.      │
│                                                                     │
│ This is why it's called a "stack" - last in, first out!           │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### What is the Base Pointer (rbp)?

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE BASE POINTER (rbp) - also called "Frame Pointer"                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ rbp = "Register: Base Pointer"                                     │
│                                                                     │
│ THE PROBLEM: rsp moves around as we push/pop things.               │
│              This makes it hard to find our stuff!                 │
│                                                                     │
│ THE SOLUTION: rbp stays FIXED for the entire function.             │
│               It marks the "base" of our stack frame.              │
│                                                                     │
│ Think of it like this:                                              │
│                                                                     │
│   rbp = "the floor of our room" (doesn't move)                     │
│   rsp = "where we're currently stacking boxes" (moves around)      │
│                                                                     │
│        ┌─────────────────┐                                         │
│   rbp →│ saved old rbp   │  "floor" of our frame                   │
│        ├─────────────────┤                                         │
│        │ local var 1     │  -8(%rbp)  - always at same offset!    │
│        ├─────────────────┤                                         │
│        │ local var 2     │  -16(%rbp) - always at same offset!    │
│        ├─────────────────┤                                         │
│   rsp →│ temp value      │  (rsp moves as we push/pop)            │
│        └─────────────────┘                                         │
│                                                                     │
│ With rbp fixed, we can always find local variables at the same    │
│ offset, no matter how much we push/pop.                            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### The Problem

Now we understand the pieces. At function entry, we need to:
1. Save the CALLER's rbp (so we can restore it when we return)
2. Set up OUR rbp to point to our frame

### The Solution: The Prologue

The **prologue** is the setup code at the start of every function:

```asm
functionname:
    pushq   %rbp            # Save caller's rbp on the stack
    movq    %rsp, %rbp      # Our rbp = current stack top
```

**Step by step:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ PROLOGUE STEP BY STEP                                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ BEFORE (just entered function via 'call'):                         │
│                                                                     │
│        ┌─────────────────┐                                         │
│        │ caller's stuff  │                                         │
│        ├─────────────────┤                                         │
│   rsp →│ return address  │  ← 'call' pushed this automatically    │
│        └─────────────────┘                                         │
│                                                                     │
│   rbp still points to caller's frame (we haven't touched it)       │
│                                                                     │
│ ─────────────────────────────────────────────────────────────────  │
│                                                                     │
│ AFTER: pushq %rbp                                                   │
│                                                                     │
│        ┌─────────────────┐                                         │
│        │ caller's stuff  │                                         │
│        ├─────────────────┤                                         │
│        │ return address  │                                         │
│        ├─────────────────┤                                         │
│   rsp →│ caller's rbp    │  ← we saved it so we can restore later │
│        └─────────────────┘                                         │
│                                                                     │
│ ─────────────────────────────────────────────────────────────────  │
│                                                                     │
│ AFTER: movq %rsp, %rbp                                              │
│                                                                     │
│        ┌─────────────────┐                                         │
│        │ caller's stuff  │                                         │
│        ├─────────────────┤                                         │
│        │ return address  │  8(%rbp) - one slot above rbp          │
│        ├─────────────────┤                                         │
│ rsp,rbp→│ caller's rbp   │  ← rbp now marks OUR frame's base      │
│        └─────────────────┘                                         │
│                                                                     │
│ Now rbp is set! It won't move until we return.                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Implementation:**

```
generatePrologue() {
    emit("    pushq   %rbp")
    emit("    movq    %rsp, %rbp")
}
```

---

## Sub-lesson 7.3: Accessing Parameters

### The Problem

Function parameters arrive in registers (rdi, rsi, etc.). We need to make them available for computation.

### The Solution

At function entry, copy parameters to our scratch registers:

```asm
# fn foo(a: i32, b: i32, c: i32)
# a in edi, b in esi, c in edx
foo:
    pushq   %rbp
    movq    %rsp, %rbp
    movl    %edi, %r10d     # a → %0
    movl    %esi, %r11d     # b → %1
    movl    %edx, %r12d     # c → %2
    # now use r10d, r11d, r12d in function body
```

**Parameter register mapping:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ PARAMETER LOCATIONS (i32)                                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Parameter #   Arrives in     Copy to (our allocation)              │
│ ───────────   ──────────     ────────────────────────              │
│ 0             edi            r10d (or first scratch)               │
│ 1             esi            r11d                                  │
│ 2             edx            r12d                                  │
│ 3             ecx            r13d                                  │
│ 4             r8d            r14d                                  │
│ 5             r9d            r15d                                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Implementation:**

```
param_regs = ["edi", "esi", "edx", "ecx", "r8d", "r9d"]

generateParamLoad(index, param_index) {
    src_reg = param_regs[param_index]
    dst_reg = allocateRegister(index)
    emit("    movl    %{}, %{}", src_reg, dst_reg)
}
```

---

## Sub-lesson 7.4: Generating Returns

### The Problem

When ZIR has a `ret` instruction, we need to:
1. Move the return value to `eax`
2. Clean up the stack frame
3. Return to the caller

### The Solution

```asm
    movl    %result_reg, %eax   # Put return value in eax
    popq    %rbp                 # Restore caller's base pointer
    ret                          # Return to caller
```

Or using `leave` (equivalent to `movq %rbp, %rsp; popq %rbp`):

```asm
    movl    %result_reg, %eax
    leave                        # Clean up stack frame
    ret
```

**Implementation:**

```
generateReturn(value_index) {
    value_reg = getRegister(value_index)
    emit("    movl    %{}, %eax", value_reg)
    emit("    popq    %rbp")
    emit("    ret")
}
```

---

## Sub-lesson 7.5: Complete Function Generation

### Putting It All Together

Here's the complete flow for generating a function:

```
generateFunction(func) {
    // 1. Header
    emit("    .globl {}", func.name)
    emit("{}:", func.name)

    // 2. Prologue
    emit("    pushq   %rbp")
    emit("    movq    %rsp, %rbp")

    // 3. Generate each instruction in function body
    for index, instruction in func.zir.instructions {
        generateInstruction(index, instruction)
    }
    // Note: ret instruction handled as part of instructions
}

generateInstruction(index, instruction) {
    switch instruction {
        literal(value):
            reg = allocateRegister(index)
            emit("    movl    ${}, %{}", value, reg)

        param_ref(param_index):
            param_reg = param_regs[param_index]
            dst_reg = allocateRegister(index)
            emit("    movl    %{}, %{}", param_reg, dst_reg)

        add(lhs, rhs):
            generateBinaryOp(index, "add", lhs, rhs)

        sub(lhs, rhs):
            generateBinaryOp(index, "sub", lhs, rhs)

        mul(lhs, rhs):
            generateBinaryOp(index, "mul", lhs, rhs)

        div(lhs, rhs):
            generateBinaryOp(index, "div", lhs, rhs)

        ret(value):
            value_reg = getRegister(value)
            emit("    movl    %{}, %eax", value_reg)
            emit("    popq    %rbp")
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

Generated x86:
    .globl add
add:
    pushq   %rbp
    movq    %rsp, %rbp
    movl    %edi, %r10d     # %0 = param_ref(0)
    movl    %esi, %r11d     # %1 = param_ref(1)
    movl    %r10d, %r12d    # %2 = add(%0, %1)
    addl    %r11d, %r12d
    movl    %r12d, %eax     # %3 = ret(%2)
    popq    %rbp
    ret
```

---

## Summary: Function Generation

```
┌────────────────────────────────────────────────────────────────────┐
│ FUNCTION GENERATION TEMPLATE                                       │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│     .globl functionname                                            │
│ functionname:                                                      │
│     pushq   %rbp              # prologue                          │
│     movq    %rsp, %rbp                                            │
│                                                                    │
│     # copy parameters to scratch registers                        │
│     movl    %edi, %r10d       # param 0                           │
│     movl    %esi, %r11d       # param 1                           │
│     ...                                                            │
│                                                                    │
│     # function body                                                │
│     ...                                                            │
│                                                                    │
│     # return                                                       │
│     movl    %result, %eax     # set return value                  │
│     popq    %rbp              # epilogue                          │
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
    .globl compute
compute:
    # compute(a, b, c) = a * b + c
    pushq   %rbp
    movq    %rsp, %rbp

    # %0 = param_ref(0) - a
    movl    %edi, %r10d

    # %1 = param_ref(1) - b
    movl    %esi, %r11d

    # %2 = param_ref(2) - c
    movl    %edx, %r12d

    # %3 = mul(%0, %1) - a * b
    movl    %r10d, %r13d
    imull   %r11d, %r13d

    # %4 = add(%3, %2) - (a * b) + c
    movl    %r13d, %r14d
    addl    %r12d, %r14d

    # ret %4
    movl    %r14d, %eax
    popq    %rbp
    ret

    .globl main
main:
    pushq   %rbp
    movq    %rsp, %rbp

    # compute(5, 8, 2) = 5 * 8 + 2 = 42
    movl    $5, %edi
    movl    $8, %esi
    movl    $2, %edx
    call    compute

    popq    %rbp
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
