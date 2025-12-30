---
title: "Lesson 8: Generating Function Calls"
weight: 8
---

# Lesson 8: Generating Function Calls

When your code calls a function, you need to set up arguments, execute the call, and capture the return value. This lesson shows you how.

**What you'll learn:**
- Moving arguments into parameter registers
- The call instruction
- Capturing the return value
- Handling caller-saved registers

---

## Sub-lesson 8.1: Setting Up Arguments

### The Problem

Given a function call like `add(10, 5)`, we need to:
1. Put `10` in `edi` (first parameter)
2. Put `5` in `esi` (second parameter)
3. Call the function

But wait - our values might already be in our scratch registers. How do we move them to the parameter registers?

### The Solution

Before the call, copy each argument to its designated parameter register:

```asm
# Call add(%r10d, %r11d) where r10d=10, r11d=5
movl    %r10d, %edi         # arg 0 → edi
movl    %r11d, %esi         # arg 1 → esi
call    add
```

**Implementation:**

```
arg_regs = ["edi", "esi", "edx", "ecx", "r8d", "r9d"]

generateCall(index, fn_name, arg_indices) {
    // Move each argument to its parameter register
    for i, arg_index in arg_indices {
        arg_reg = getRegister(arg_index)
        param_reg = arg_regs[i]
        emit("    movl    %{}, %{}", arg_reg, param_reg)
    }

    // Execute the call
    emit("    call    {}", fn_name)

    // Capture return value
    dst_reg = allocateRegister(index)
    emit("    movl    %eax, %{}", dst_reg)
}
```

---

## Sub-lesson 8.2: The Call Instruction

### The Problem

What does the `call` instruction actually do?

### The Solution

`call` does two things:
1. Pushes the return address onto the stack
2. Jumps to the function's label

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHAT "call" DOES                                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│     call add                                                        │
│                                                                     │
│ Is equivalent to:                                                   │
│     pushq   next_instruction_address                                │
│     jmp     add                                                     │
│                                                                     │
│ When "add" executes "ret":                                          │
│     ret                                                             │
│                                                                     │
│ What happens:                                                       │
│     1. Pop value from stack into a temporary                       │
│     2. Jump to that address                                        │
│                                                                     │
│ (You can't literally write "popq %rip" - the CPU does this         │
│ internally when you use the "ret" instruction)                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**The stack during a call:**

```
Before call:              After call:              After ret:
                          rsp → ┌────────────┐
rsp → ┌────────────┐            │ ret addr   │     rsp → ┌────────────┐
      │ ...        │            ├────────────┤           │ ...        │
      └────────────┘            │ ...        │           └────────────┘
                                └────────────┘
```

---

## Sub-lesson 8.3: Getting the Return Value

### The Problem

After `call add` returns, where is the result?

### The Solution

The return value is in `eax`. Copy it to your scratch register:

```asm
call    add
movl    %eax, %r12d         # save result to r12d
```

**Complete call sequence:**

```asm
# result = add(x, y)
# where x is in r10d, y is in r11d

movl    %r10d, %edi         # arg 0
movl    %r11d, %esi         # arg 1
call    add                  # call function
movl    %eax, %r12d         # save result (now result is in r12d)
```

---

## Sub-lesson 8.4: Caller-Saved Registers

### The Problem

When we call a function, it might overwrite registers we're using! The parameter registers (edi, esi, etc.) and scratch registers (r10, r11) are **caller-saved** - the called function can freely modify them.

### The Solution

**Option 1: Accept the limitation**

For simple code, just be careful about register usage across calls:
- Use the result immediately
- Don't expect values in edi/esi/r10/r11 to survive calls

**Option 2: Save registers before call**

If you need values to survive a call, push them to the stack:

```asm
# We need r10d to survive the call
pushq   %r10                # save r10 (push is 64-bit)
movl    %r11d, %edi         # set up args
movl    %r12d, %esi
call    some_function
popq    %r10                # restore r10
# Now r10d still has our value
```

**Option 3: Use callee-saved registers**

Registers rbx, r12-r15 are preserved across calls. If you use them, save them in the prologue:

```asm
foo:
    pushq   %rbp
    movq    %rsp, %rbp
    pushq   %rbx            # save callee-saved reg we'll use

    # use rbx freely, it survives calls

    popq    %rbx            # restore before return
    popq    %rbp
    ret
```

**For our simple compiler**: We'll use option 1. Each call result goes to a new scratch register, and we don't rely on values surviving across calls.

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

Generated x86:
    .globl double
double:
    pushq   %rbp
    movq    %rsp, %rbp
    movl    %edi, %r10d     # x
    movl    $2, %r11d       # 2
    movl    %r10d, %r12d    # x * 2
    imull   %r11d, %r12d
    movl    %r12d, %eax
    popq    %rbp
    ret

    .globl main
main:
    pushq   %rbp
    movq    %rsp, %rbp
    movl    $21, %r10d      # %0 = literal(21)
    movl    %r10d, %edi     # set up arg for call
    call    double           # %1 = call(double, [%0])
    movl    %eax, %r11d     # save return value
    movl    %r11d, %eax     # %2 = ret(%1)
    popq    %rbp
    ret
```

---

## Summary: Function Call Generation

```
┌────────────────────────────────────────────────────────────────────┐
│ FUNCTION CALL PATTERN                                              │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ # result = fn(arg0, arg1, arg2)                                   │
│                                                                    │
│ movl    %arg0_reg, %edi       # set up argument 0                 │
│ movl    %arg1_reg, %esi       # set up argument 1                 │
│ movl    %arg2_reg, %edx       # set up argument 2                 │
│ call    fn                     # call the function                │
│ movl    %eax, %result_reg     # capture return value              │
│                                                                    │
│ ARGUMENT REGISTERS (in order):                                    │
│   edi, esi, edx, ecx, r8d, r9d                                   │
│                                                                    │
│ RETURN VALUE:                                                     │
│   eax                                                             │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Try It Yourself

Write a program with two functions that call each other:

```bash
cat > calls.s << 'EOF'
    .text

    .globl square
square:
    # square(x) = x * x
    pushq   %rbp
    movq    %rsp, %rbp
    movl    %edi, %r10d
    movl    %r10d, %r11d
    imull   %r10d, %r11d
    movl    %r11d, %eax
    popq    %rbp
    ret

    .globl add_squares
add_squares:
    # add_squares(a, b) = square(a) + square(b)
    pushq   %rbp
    movq    %rsp, %rbp
    pushq   %rbx            # save callee-saved reg

    # Save 'b' in rbx (survives the call to square(a))
    movl    %esi, %ebx

    # call square(a)
    # edi already has 'a'
    call    square
    movl    %eax, %r10d     # r10d = square(a)

    # call square(b)
    movl    %ebx, %edi      # b was saved in ebx
    call    square
    movl    %eax, %r11d     # r11d = square(b)

    # return square(a) + square(b)
    movl    %r10d, %eax
    addl    %r11d, %eax

    popq    %rbx
    popq    %rbp
    ret

    .globl main
main:
    pushq   %rbp
    movq    %rsp, %rbp

    # add_squares(3, 4) = 9 + 16 = 25
    movl    $3, %edi
    movl    $4, %esi
    call    add_squares

    popq    %rbp
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
