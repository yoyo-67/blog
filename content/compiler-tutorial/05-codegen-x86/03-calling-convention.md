---
title: "Lesson 3: Calling Convention"
weight: 3
---

# Lesson 3: Calling Convention (System V AMD64 ABI)

When one function calls another, how are parameters passed? How does the return value come back? This lesson teaches you the **calling convention**: the agreed-upon rules that make function calls work.

**What you'll learn:**
- How function parameters are passed in registers
- Where return values go
- Which registers are preserved across calls
- Stack alignment requirements

---

## Sub-lesson 3.1: Parameter Passing

### The Problem

When we call `add(10, 5)`, the caller has the values `10` and `5`. The callee (`add`) needs to receive them. How do they get there?

### The Solution

On Linux and macOS (x86-64), the **System V AMD64 ABI** says: put the first 6 integer arguments in specific registers:

```
┌─────────────────────────────────────────────────────────────────────┐
│ PARAMETER REGISTERS (System V AMD64 ABI)                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Argument #   Register (64-bit)   Register (32-bit)                  │
│ ──────────   ────────────────    ────────────────                   │
│ 1st          rdi                 edi                                │
│ 2nd          rsi                 esi                                │
│ 3rd          rdx                 edx                                │
│ 4th          rcx                 ecx                                │
│ 5th          r8                  r8d                                │
│ 6th          r9                  r9d                                │
│ 7th+         (pushed on stack)                                      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Example: Calling `add(10, 5)`**

```asm
# Caller sets up arguments:
movl    $10, %edi       # first argument → edi
movl    $5, %esi        # second argument → esi
call    add             # call the function

# Inside add(), the function sees:
#   edi = 10 (first parameter)
#   esi = 5  (second parameter)
```

**Example: Function with 4 parameters**

```
fn compute(a: i32, b: i32, c: i32, d: i32) i32

Caller:                     Callee receives:
  arg1 → edi                  a = edi
  arg2 → esi                  b = esi
  arg3 → edx                  c = edx
  arg4 → ecx                  d = ecx
```

**For our compiler**: We'll limit functions to 6 parameters (no stack passing needed).

---

## Sub-lesson 3.2: Return Values

### The Problem

How does a function send its result back to the caller?

### The Solution

The return value goes in `rax` (or `eax` for 32-bit integers):

```
┌─────────────────────────────────────────────────────────────────────┐
│ RETURN VALUE REGISTER                                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Type        Register                                                │
│ ────        ────────                                                │
│ Integer     rax (64-bit) or eax (32-bit)                           │
│ Pointer     rax                                                     │
│ Float       xmm0 (we won't use this)                               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Example: add function**

```asm
# fn add(a: i32, b: i32) i32 { return a + b; }

add:
    movl    %edi, %eax      # copy first param to result register
    addl    %esi, %eax      # add second param
    ret                      # return (result is in eax)

# Caller uses the result:
    call    add
    # now eax contains the return value
    movl    %eax, %r10d     # save result to r10d
```

**Key insight**: After `call`, the return value is waiting in `eax`. The caller can use it immediately.

---

## Sub-lesson 3.3: Register Preservation

### The Problem

You have a value in a register, then you call a function. When the call returns, is your value still there? Or did the called function overwrite it?

### The Solution

Think of it this way: **when you call a function, some registers get TRASHED and some SURVIVE.**

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHAT HAPPENS TO REGISTERS WHEN YOU CALL A FUNCTION?                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ TRASHED BY CALLS (assume your value is gone after any call):       │
│   rax, rcx, rdx, rsi, rdi, r8, r9, r10, r11                        │
│                                                                     │
│   The function you call is FREE to overwrite these.                │
│   Don't expect your values to survive!                             │
│                                                                     │
│ SURVIVE CALLS (your value is safe):                                │
│   rbx, rbp, r12, r13, r14, r15                                     │
│                                                                     │
│   The function you call MUST restore these before returning.       │
│   Your values will still be there after the call.                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Simple mental model:**

```
                        call some_function
                               │
    ┌──────────────────────────┼──────────────────────────┐
    │                          │                          │
    ▼                          ▼                          ▼
┌────────┐              ┌────────────┐              ┌────────┐
│ BEFORE │              │   DURING   │              │ AFTER  │
├────────┤              ├────────────┤              ├────────┤
│r10 = 5 │              │ function   │              │r10 = ? │ ← TRASHED!
│r11 = 3 │      ──►     │ can do     │      ──►     │r11 = ? │ ← TRASHED!
│rbx = 7 │              │ whatever   │              │rbx = 7 │ ← SAFE!
│r12 = 9 │              │ it wants   │              │r12 = 9 │ ← SAFE!
└────────┘              └────────────┘              └────────┘
```

**The catch with "safe" registers:** If YOU want to use rbx or r12-r15, YOU must save and restore them too (because your caller expects them to survive YOUR function).

**Example:**

```asm
# BAD: r10 gets trashed by calls
    movl    %edi, %r10d     # save my value in r10d
    call    other_func       # other_func might use r10 for its own stuff!
    addl    %r10d, %eax     # WRONG: r10d is garbage now

# GOOD: rbx survives calls (but we must save/restore it)
    pushq   %rbx            # save rbx (our caller expects it unchanged)
    movl    %edi, %ebx      # put our value in rbx
    call    other_func       # other_func will preserve rbx for us
    addl    %ebx, %eax      # rbx still has our value!
    popq    %rbx            # restore rbx (keep our promise to our caller)
```

**For our simple compiler:**
- We use r10-r15 for temporaries within a function
- We don't make calls in the middle of complex expressions
- So we usually don't need to worry about this!

**Terminology note:** You'll see these called "caller-saved" vs "callee-saved" in other resources. Those terms describe WHO is responsible for saving:
- "Caller-saved" = trashed = if the CALLER needs the value, CALLER must save it
- "Callee-saved" = survives = the CALLEE promises to restore it

---

## Sub-lesson 3.4: Stack and Function Setup

### The Problem

Every function needs some setup code (called a "prologue") and cleanup code (called an "epilogue"). Why?

### The Solution

**What the prologue/epilogue does:**

1. **Saves the old frame pointer** so we can restore it when we return
2. **Sets up our own frame pointer** so we have a stable reference point
3. **Keeps the stack aligned** (some instructions require 16-byte alignment)

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE STANDARD PROLOGUE AND EPILOGUE                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ PROLOGUE (at function start):                                       │
│   pushq   %rbp            # save caller's frame pointer            │
│   movq    %rsp, %rbp      # set our frame pointer = stack top      │
│                                                                     │
│ EPILOGUE (before return):                                           │
│   popq    %rbp            # restore caller's frame pointer         │
│   ret                     # return to caller                        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Visual: What happens when `main` calls `add`:**

```
BEFORE call add:          AFTER prologue in add:

    ┌─────────────┐           ┌─────────────┐
    │   main's    │           │   main's    │
    │   stuff     │           │   stuff     │
    ├─────────────┤           ├─────────────┤
    │             │           │ return addr │ ← pushed by 'call'
    └─────────────┘           ├─────────────┤
          ▲                   │ saved rbp   │ ← pushed by prologue
         rsp                  └─────────────┘
                                    ▲
                               rsp, rbp
                               (both point here)
```

**Why `rbp` (frame pointer)?**

`rbp` gives us a stable reference point. The stack pointer (`rsp`) moves when we push/pop, but `rbp` stays fixed throughout our function:

```
rbp points here ──►  ┌─────────────┐
                     │ saved rbp   │
                     ├─────────────┤
                     │ local var 1 │  ← -8(%rbp)
                     ├─────────────┤
                     │ local var 2 │  ← -16(%rbp)
                     └─────────────┘
                           ▲
                          rsp (moves as we push/pop)
```

**The complete pattern:**

```asm
my_function:
    # PROLOGUE
    pushq   %rbp            # save old frame pointer
    movq    %rsp, %rbp      # establish our frame pointer

    # ... your code here ...

    # EPILOGUE
    popq    %rbp            # restore old frame pointer
    ret                     # return
```

**Shortcut for simple functions:**

If your function doesn't call other functions ("leaf function") and doesn't need local variables, you can skip the prologue/epilogue entirely:

```asm
add:
    # No prologue needed!
    movl    %edi, %eax      # result = first param
    addl    %esi, %eax      # result += second param
    ret                     # return
```

**For our compiler:** We'll always include the prologue/epilogue for consistency. It's a few extra instructions but makes the code uniform and easier to debug.

---

## Summary: System V AMD64 ABI Quick Reference

```
┌────────────────────────────────────────────────────────────────────┐
│ SYSTEM V AMD64 ABI - QUICK REFERENCE                               │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ INTEGER PARAMETERS (in order):                                     │
│   1: rdi    2: rsi    3: rdx    4: rcx    5: r8    6: r9          │
│                                                                    │
│ RETURN VALUE:                                                      │
│   Integers: rax (eax for 32-bit)                                  │
│                                                                    │
│ TRASHED BY CALLS (caller-saved):                                   │
│   rax, rcx, rdx, rsi, rdi, r8, r9, r10, r11                       │
│   → Assume gone after any function call                           │
│                                                                    │
│ SURVIVE CALLS (callee-saved):                                      │
│   rbx, rbp, r12, r13, r14, r15                                    │
│   → Safe across calls, but you must save/restore if you use them  │
│                                                                    │
│ STACK:                                                             │
│   - Grows downward                                                 │
│   - Must be 16-byte aligned before 'call'                         │
│   - Prologue: pushq %rbp; movq %rsp, %rbp                         │
│   - Epilogue: popq %rbp; ret (or: leave; ret)                     │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Try It Yourself

Write a function that takes two parameters and returns their difference:

```bash
cat > sub.s << 'EOF'
    .text
    .globl main
    .globl subtract

subtract:
    pushq   %rbp
    movq    %rsp, %rbp
    movl    %edi, %eax      # eax = first param (a)
    subl    %esi, %eax      # eax = a - b
    popq    %rbp
    ret

main:
    pushq   %rbp
    movq    %rsp, %rbp
    movl    $50, %edi       # first argument
    movl    $8, %esi        # second argument
    call    subtract
    # result (42) is now in eax
    popq    %rbp
    ret
EOF

cc -o sub sub.s
./sub
echo $?  # Should print 42
```

---

## What's Next

We know how functions work at the ABI level. Now we need a strategy for mapping our compiler's virtual "registers" (one per ZIR instruction) to the limited physical registers.

**Next: [Lesson 4: Register Allocation](../04-register-allocation/)** →
