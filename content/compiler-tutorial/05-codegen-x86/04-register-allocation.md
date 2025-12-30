---
title: "Lesson 4: Register Allocation"
weight: 4
---

# Lesson 4: Register Allocation Strategy

ZIR gives each instruction a unique index (like `%0`, `%1`, `%2`). But x86 only has 16 registers. How do we map unlimited virtual registers to limited physical ones?

**What you'll learn:**
- The register allocation problem
- A simple linear allocation strategy
- What to do when we run out of registers (spilling)

---

## Sub-lesson 4.1: The Mapping Problem

### The Problem

In ZIR, every instruction produces a result that can be referenced later:

```
%0 = literal(2)
%1 = literal(3)
%2 = mul(%0, %1)      # uses %0 and %1
%3 = literal(4)
%4 = add(%2, %3)      # uses %2 and %3
%5 = ret(%4)
```

Each `%n` is a "virtual register" - we can have as many as we need.

But x86 has only ~10 usable registers for temporaries (after reserving some for parameters, stack, etc.). What if our function needs 20 temporaries?

### The Solution

We need a **register allocation** strategy that:
1. Assigns each ZIR instruction result to a physical register
2. Reuses registers when values are no longer needed
3. "Spills" to memory when we run out

For our simple compiler, we'll use **linear scan allocation**: assign registers in order, and only spill if we run out.

```
┌─────────────────────────────────────────────────────────────────────┐
│ REGISTER ALLOCATION STRATEGIES                                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ 1. SIMPLE LINEAR (what we'll do):                                   │
│    - Assign registers in order: r10, r11, r12, ...                 │
│    - Good enough for small functions                               │
│    - Easy to implement                                              │
│                                                                     │
│ 2. GRAPH COLORING (production compilers):                           │
│    - Build interference graph                                       │
│    - Find optimal allocation                                        │
│    - Complex but efficient                                          │
│                                                                     │
│ 3. LINEAR SCAN (compromise):                                        │
│    - One pass over instructions                                     │
│    - Track live ranges                                              │
│    - Reuse registers when values die                               │
│                                                                     │
│ We'll use approach #1 - simple and educational.                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Sub-lesson 4.2: Simple Linear Allocation

### The Problem

How do we assign physical registers to ZIR instruction results?

### The Solution

Use a simple mapping: ZIR index → register from a pool.

**Available scratch registers** (caller-saved, we can use freely):

```
r10, r11     ← Primary scratch registers
r12, r13     ← Callee-saved (must save/restore if used)
r14, r15     ← More callee-saved
```

**Our allocation table:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ REGISTER ASSIGNMENT                                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ ZIR Index    Physical Register (32-bit)                            │
│ ─────────    ──────────────────────────                            │
│ %0           r10d                                                   │
│ %1           r11d                                                   │
│ %2           r12d  (must save/restore)                             │
│ %3           r13d  (must save/restore)                             │
│ %4           r14d  (must save/restore)                             │
│ %5           r15d  (must save/restore)                             │
│ %6+          spill to stack                                        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Implementation:**

```
// Codegen state
X86Gen {
    scratch_regs: ["r10d", "r11d", "r12d", "r13d", "r14d", "r15d"]
}

// Get register for ZIR instruction index
getRegister(index) -> string {
    if index < scratch_regs.len {
        return scratch_regs[index]
    }
    // Would need to spill to stack - we'll skip this for now
    error("Too many temporaries, would need to spill")
}
```

**Example mapping:**

```
ZIR:                          x86:
%0 = literal(2)               movl $2, %r10d
%1 = literal(3)               movl $3, %r11d
%2 = mul(%0, %1)              movl %r10d, %r12d
                              imull %r11d, %r12d
%3 = literal(4)               movl $4, %r13d
%4 = add(%2, %3)              movl %r12d, %r14d
                              addl %r13d, %r14d
%5 = ret(%4)                  movl %r14d, %eax
                              ret
```

---

## Sub-lesson 4.3: Handling Parameters and Special Cases

### The Problem

Not all values come from computations. Some come from:
1. **Function parameters** (in rdi, rsi, etc.)
2. **Function call results** (in rax)

How do we integrate these with our register allocation?

### The Solution

**For parameters**: At function entry, copy from parameter registers to our scratch registers:

```
# fn foo(a: i32, b: i32)
# a is in edi, b is in esi
# We'll copy them to our scratch pool as the first "instructions"

foo:
    pushq   %rbp
    movq    %rsp, %rbp
    # Copy parameters to scratch registers
    movl    %edi, %r10d     # param 0 → our %0 slot
    movl    %esi, %r11d     # param 1 → our %1 slot
    # ... rest of function uses %r10d for a, %r11d for b
```

**For function calls**: The result is in eax. We copy it to the next scratch register:

```
# result of call goes to eax, copy to our allocation
call    some_func
movl    %eax, %r12d         # save result to next scratch register
```

**Codegen state tracking:**

```
X86Gen {
    output: StringBuilder
    next_reg_index: int      // Which scratch slot to use next

    // Map from ZIR index to physical register name
    reg_map: Map<int, string>
}

allocateRegister(zir_index) -> string {
    if zir_index not in reg_map {
        reg_map[zir_index] = scratch_regs[next_reg_index]
        next_reg_index += 1
    }
    return reg_map[zir_index]
}
```

**Complete example:**

```
fn add(a: i32, b: i32) i32 {
    return a + b;
}

ZIR:
  %0 = param_ref(0)    # a
  %1 = param_ref(1)    # b
  %2 = add(%0, %1)     # a + b
  %3 = ret(%2)

x86 generation:
  # %0 = param_ref(0)
  movl    %edi, %r10d       # copy param 0 to %r10d

  # %1 = param_ref(1)
  movl    %esi, %r11d       # copy param 1 to %r11d

  # %2 = add(%0, %1)
  movl    %r10d, %r12d      # copy first operand
  addl    %r11d, %r12d      # add second operand

  # %3 = ret(%2)
  movl    %r12d, %eax       # move result to return register
  leave
  ret
```

---

## Summary: Register Allocation Strategy

```
┌────────────────────────────────────────────────────────────────────┐
│ REGISTER ALLOCATION SUMMARY                                        │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ AVAILABLE REGISTERS (for temporaries):                             │
│   Caller-saved: r10d, r11d (free to use)                          │
│   Callee-saved: r12d, r13d, r14d, r15d (must save/restore)        │
│                                                                    │
│ RESERVED REGISTERS:                                                │
│   rsp, rbp     - Stack management                                  │
│   rdi, rsi, rdx, rcx, r8, r9 - Parameters (copy early)            │
│   rax          - Return value                                      │
│                                                                    │
│ ALLOCATION STRATEGY:                                               │
│   1. Each ZIR instruction gets next available scratch register    │
│   2. Parameters: copy from rdi/rsi/etc to scratch at entry        │
│   3. Call results: copy from rax to scratch after call            │
│   4. Return: copy final result to eax                             │
│                                                                    │
│ LIMITATIONS (OK for learning):                                     │
│   - Max ~6 temporaries before spilling                            │
│   - No register reuse (values live until function end)            │
│   - Generates more mov instructions than optimal                   │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Try It Yourself

Trace through this function's register allocation:

```
fn compute(x: i32, y: i32) i32 {
    const a = x * 2;
    const b = y + 10;
    return a + b;
}

ZIR:
  %0 = param_ref(0)     # x
  %1 = param_ref(1)     # y
  %2 = literal(2)
  %3 = mul(%0, %2)      # x * 2
  %4 = literal(10)
  %5 = add(%1, %4)      # y + 10
  %6 = add(%3, %5)      # a + b
  %7 = ret(%6)

Your task: write the x86 assembly with register assignments.

Expected output structure:
  movl    %edi, %r10d     # %0 param_ref(0)
  movl    %esi, %r11d     # %1 param_ref(1)
  movl    $2, %r12d       # %2 literal(2)
  movl    %r10d, %r13d    # %3 = mul(%0, %2) - copy first
  imull   %r12d, %r13d    # complete multiplication
  movl    $10, %r14d      # %4 literal(10)
  movl    %r11d, %r15d    # %5 = add(%1, %4) - copy first
  addl    %r14d, %r15d    # complete addition
  # %6 would need spilling! (7th temporary)
```

Notice: We'd need a 7th register for `%6`. A real compiler would reuse registers whose values are no longer needed.

---

## What's Next

We have our allocation strategy. Now let's start generating code, beginning with the simplest case: constant values.

**Next: [Lesson 5: Generating Constants](../05-gen-constants/)** →
