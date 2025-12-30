---
title: "Lesson 6: Generating Arithmetic"
weight: 6
---

# Lesson 6: Generating Arithmetic Operations

Now let's generate code for binary operations: addition, subtraction, multiplication, and division.

**What you'll learn:**
- Generating add, sub, mul instructions
- The special case of division (idivl)
- Putting operands in the right places

---

## Sub-lesson 6.1: Addition

### The Problem

Given a ZIR add instruction, generate x86:

```
ZIR:   %2 = add(%0, %1)
       where %0 is in r10d, %1 is in r11d

x86:   ???
```

### The Solution

x86's `addl` instruction adds source to destination, storing the result in destination:

```asm
addl    %src, %dst      # dst = dst + src
```

Since `addl` modifies the destination, we first copy one operand to the result register:

```asm
movl    %r10d, %r12d    # copy first operand to result register
addl    %r11d, %r12d    # add second operand
```

**Implementation:**

```
generateAdd(index, lhs_index, rhs_index) {
    lhs_reg = getRegister(lhs_index)   # e.g., r10d
    rhs_reg = getRegister(rhs_index)   # e.g., r11d
    dst_reg = allocateRegister(index)  # e.g., r12d

    emit("    movl    %{}, %{}", lhs_reg, dst_reg)
    emit("    addl    %{}, %{}", rhs_reg, dst_reg)
}
```

**Example:**

```
Source:   2 + 3

ZIR:      %0 = literal(2)
          %1 = literal(3)
          %2 = add(%0, %1)

x86:      movl    $2, %r10d       # %0
          movl    $3, %r11d       # %1
          movl    %r10d, %r12d    # %2 = copy lhs
          addl    %r11d, %r12d    # %2 += rhs
```

---

## Sub-lesson 6.2: Subtraction

### The Problem

Subtraction is similar, but order matters: `a - b` is not the same as `b - a`.

### The Solution

Use `subl` with careful attention to operand order:

```asm
subl    %src, %dst      # dst = dst - src
```

**Implementation:**

```
generateSub(index, lhs_index, rhs_index) {
    lhs_reg = getRegister(lhs_index)
    rhs_reg = getRegister(rhs_index)
    dst_reg = allocateRegister(index)

    emit("    movl    %{}, %{}", lhs_reg, dst_reg)  # dst = lhs
    emit("    subl    %{}, %{}", rhs_reg, dst_reg)  # dst = dst - rhs = lhs - rhs
}
```

**Example:**

```
Source:   10 - 3

ZIR:      %0 = literal(10)
          %1 = literal(3)
          %2 = sub(%0, %1)

x86:      movl    $10, %r10d      # %0
          movl    $3, %r11d       # %1
          movl    %r10d, %r12d    # copy 10 to result
          subl    %r11d, %r12d    # result = 10 - 3 = 7
```

---

## Sub-lesson 6.3: Multiplication

### The Problem

Multiply two values. Does it work the same as add/sub?

### The Solution

For signed multiplication, use `imull`:

```asm
imull   %src, %dst      # dst = dst * src
```

Same pattern as add/sub:

```
generateMul(index, lhs_index, rhs_index) {
    lhs_reg = getRegister(lhs_index)
    rhs_reg = getRegister(rhs_index)
    dst_reg = allocateRegister(index)

    emit("    movl    %{}, %{}", lhs_reg, dst_reg)
    emit("    imull   %{}, %{}", rhs_reg, dst_reg)
}
```

**Example:**

```
Source:   6 * 7

ZIR:      %0 = literal(6)
          %1 = literal(7)
          %2 = mul(%0, %1)

x86:      movl    $6, %r10d
          movl    $7, %r11d
          movl    %r10d, %r12d    # copy 6
          imull   %r11d, %r12d    # 6 * 7 = 42
```

---

## Sub-lesson 6.4: Division (The Tricky One)

### The Problem

Unlike add/sub/mul where we pick any registers, x86 division (`idivl`) **demands specific registers**. This is a historical quirk from the 1970s that we're still stuck with.

```
┌─────────────────────────────────────────────────────────────────────┐
│ WHY IS x86 DIVISION WEIRD?                                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ ADD/SUB/MUL:  You pick the registers.                              │
│   addl %r10d, %r11d      ✓ Works with any registers               │
│   imull %r12d, %r13d     ✓ Works with any registers               │
│                                                                     │
│ DIVISION:     The CPU picks the registers for you.                 │
│   idivl ???              Must use eax and edx, no choice!          │
│                                                                     │
│ The idivl instruction is hard-coded to:                            │
│   - Read the dividend from eax (and edx)                           │
│   - Write the quotient to eax                                      │
│   - Write the remainder to edx                                     │
│                                                                     │
│ This design is from early Intel chips where transistors were       │
│ precious and dedicated registers saved silicon.                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### The Solution

We need to shuffle values into the right places before dividing:

```
┌─────────────────────────────────────────────────────────────────────┐
│ DIVISION: STEP BY STEP                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ Goal: compute 42 / 6                                               │
│                                                                     │
│ STEP 1: Move dividend (42) into eax                                │
│   ┌─────────────────────────────────────────────────────┐          │
│   │ r10d: 42    eax: ???    edx: ???    r11d: 6        │          │
│   └─────────────────────────────────────────────────────┘          │
│   movl %r10d, %eax                                                 │
│   ┌─────────────────────────────────────────────────────┐          │
│   │ r10d: 42    eax: 42     edx: ???    r11d: 6        │          │
│   └─────────────────────────────────────────────────────┘          │
│                                                                     │
│ STEP 2: Prepare edx with "cdq" (explained below)                   │
│   cdq                                                               │
│   ┌─────────────────────────────────────────────────────┐          │
│   │ r10d: 42    eax: 42     edx: 0      r11d: 6        │          │
│   └─────────────────────────────────────────────────────┘          │
│                                                                     │
│ STEP 3: Divide!                                                     │
│   idivl %r11d    (divide by whatever is in r11d)                   │
│   ┌─────────────────────────────────────────────────────┐          │
│   │ r10d: 42    eax: 7      edx: 0      r11d: 6        │          │
│   └─────────────────────────────────────────────────────┘          │
│                     ▲ quotient   ▲ remainder                       │
│                                                                     │
│ STEP 4: Copy result out of eax to our register                     │
│   movl %eax, %r12d                                                 │
│   ┌─────────────────────────────────────────────────────┐          │
│   │ r12d: 7  ← our result!                             │          │
│   └─────────────────────────────────────────────────────┘          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### What does `cdq` do?

The `cdq` instruction prepares edx for division. Here's why it's needed:

```
┌─────────────────────────────────────────────────────────────────────┐
│ THE cdq INSTRUCTION                                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ idivl actually divides a 64-BIT number stored across TWO           │
│ 32-bit registers:                                                   │
│                                                                     │
│   ┌──────────────┬──────────────┐                                  │
│   │     edx      │     eax      │  = one 64-bit number             │
│   │ (high bits)  │ (low bits)   │                                  │
│   └──────────────┴──────────────┘                                  │
│                                                                     │
│ For 32-bit division, we only care about eax. But we must set       │
│ edx correctly or we get wrong answers!                             │
│                                                                     │
│ WHAT cdq DOES:                                                      │
│                                                                     │
│ For positive numbers (like 42):                                    │
│   cdq fills edx with all zeros                                     │
│   ┌─────────────────────┬─────────────────────┐                    │
│   │ edx = 0x00000000    │ eax = 0x0000002A    │  = 42             │
│   └─────────────────────┴─────────────────────┘                    │
│                                                                     │
│ For negative numbers (like -42):                                   │
│   cdq fills edx with all ones                                      │
│   ┌─────────────────────┬─────────────────────┐                    │
│   │ edx = 0xFFFFFFFF    │ eax = 0xFFFFFFD6    │  = -42            │
│   └─────────────────────┴─────────────────────┘                    │
│                                                                     │
│ HOW cdq KNOWS WHICH TO USE:                                        │
│                                                                     │
│ It looks at the TOP bit of eax (the "sign bit" in two's comp.):   │
│                                                                     │
│   Positive: top bit = 0  →  edx = 0x00000000                      │
│   Negative: top bit = 1  →  edx = 0xFFFFFFFF                      │
│                                                                     │
│ This way, the 64-bit number (edx:eax) represents the same value   │
│ as the 32-bit number in eax, and division works correctly.         │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Why does this matter?** Without `cdq`, edx has garbage. If edx happened to equal 1 and eax = 42, the CPU would think you want to divide 4,294,967,338 (a huge 64-bit number!), not just 42. You'd get completely wrong results.

### Implementation

```
generateDiv(index, lhs_index, rhs_index) {
    lhs_reg = getRegister(lhs_index)   // dividend (what we divide)
    rhs_reg = getRegister(rhs_index)   // divisor (what we divide by)
    dst_reg = allocateRegister(index)

    emit("    movl    %{}, %eax", lhs_reg)  // Step 1: dividend → eax
    emit("    cdq")                          // Step 2: prepare edx
    emit("    idivl   %{}", rhs_reg)         // Step 3: divide!
    emit("    movl    %eax, %{}", dst_reg)   // Step 4: get result
}
```

### Example

```
Source:   42 / 6

ZIR:      %0 = literal(42)
          %1 = literal(6)
          %2 = div(%0, %1)

x86:      movl    $42, %r10d      # %0 = 42
          movl    $6, %r11d       # %1 = 6
          movl    %r10d, %eax     # Step 1: 42 → eax
          cdq                      # Step 2: edx = 0 (positive number)
          idivl   %r11d           # Step 3: divide by 6
          movl    %eax, %r12d     # Step 4: result (7) → r12d
```

### How ARM64 does it (for comparison)

ARM64 has a simple `sdiv` instruction that works like add/sub/mul:

```asm
// ARM64: just one instruction, any registers
sdiv    w2, w0, w1      // w2 = w0 / w1

// x86: four instructions, fixed registers
movl    %r10d, %eax
cdq
idivl   %r11d
movl    %eax, %r12d
```

This is one place where ARM64 is clearly simpler!

**Warning**: Division by zero will crash your program on both architectures!

---

## Complete Arithmetic Code Generator

```
generateBinaryOp(index, op, lhs_index, rhs_index) {
    lhs_reg = getRegister(lhs_index)
    rhs_reg = getRegister(rhs_index)
    dst_reg = allocateRegister(index)

    if op == "add" {
        emit("    movl    %{}, %{}", lhs_reg, dst_reg)
        emit("    addl    %{}, %{}", rhs_reg, dst_reg)
    }
    else if op == "sub" {
        emit("    movl    %{}, %{}", lhs_reg, dst_reg)
        emit("    subl    %{}, %{}", rhs_reg, dst_reg)
    }
    else if op == "mul" {
        emit("    movl    %{}, %{}", lhs_reg, dst_reg)
        emit("    imull   %{}, %{}", rhs_reg, dst_reg)
    }
    else if op == "div" {
        emit("    movl    %{}, %eax", lhs_reg)
        emit("    cdq")
        emit("    idivl   %{}", rhs_reg)
        emit("    movl    %eax, %{}", dst_reg)
    }
}
```

---

## Summary: Arithmetic Generation

```
┌────────────────────────────────────────────────────────────────────┐
│ ARITHMETIC GENERATION PATTERNS                                     │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ ADD:  movl %lhs, %dst      SUB:  movl %lhs, %dst                  │
│       addl %rhs, %dst            subl %rhs, %dst                  │
│                                                                    │
│ MUL:  movl %lhs, %dst      DIV:  movl %lhs, %eax                  │
│       imull %rhs, %dst           cdq                              │
│                                                                    │
│                                  idivl %rhs                       │
│                                  movl %eax, %dst                  │
│                                                                    │
│ Pattern: Copy lhs to dst, then operate with rhs                   │
│ Exception: Division uses fixed eax/edx registers                  │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Try It Yourself

Compile a function that computes `(10 + 5) * 2`:

```bash
cat > arith.s << 'EOF'
    .text
    .globl main
main:
    pushq   %rbp
    movq    %rsp, %rbp

    # %0 = literal(10)
    movl    $10, %r10d

    # %1 = literal(5)
    movl    $5, %r11d

    # %2 = add(%0, %1) = 15
    movl    %r10d, %r12d
    addl    %r11d, %r12d

    # %3 = literal(2)
    movl    $2, %r13d

    # %4 = mul(%2, %3) = 30
    movl    %r12d, %r14d
    imull   %r13d, %r14d

    # return %4
    movl    %r14d, %eax

    popq    %rbp
    ret
EOF

cc -o arith arith.s
./arith
echo $?  # Should print 30
```

Now try division:

```bash
cat > div.s << 'EOF'
    .text
    .globl main
main:
    pushq   %rbp
    movq    %rsp, %rbp

    # 100 / 4 = 25
    movl    $100, %r10d
    movl    $4, %r11d
    movl    %r10d, %eax
    cdq
    idivl   %r11d
    # eax = 25

    popq    %rbp
    ret
EOF

cc -o div div.s
./div
echo $?  # Should print 25
```

---

## What's Next

We can generate constants and arithmetic. Now let's put them inside functions with proper prologue, epilogue, and parameter handling.

**Next: [Lesson 7: Generating Functions](../07-gen-functions/)** →
