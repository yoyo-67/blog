---
title: "Lesson 6: Generating Arithmetic"
weight: 6
---

# Lesson 6: Generating Arithmetic Operations

Now let's generate code for binary operations: addition, subtraction, multiplication, and division.

**What you'll learn:**
- Generating add, sub, mul instructions
- Division with sdiv (so much simpler than x86!)
- ARM64's clean 3-operand format

---

## Sub-lesson 6.1: Addition

### The Problem

Given a ZIR add instruction, generate ARM64:

```
ZIR:   %2 = add(%0, %1)
       where %0 is in w9, %1 is in w10

ARM64: ???
```

### The Solution

ARM64's `add` takes three operands: destination, source1, source2:

```asm
add     w11, w9, w10    // w11 = w9 + w10
```

**Implementation:**

```
generateAdd(index, lhs_index, rhs_index) {
    lhs_reg = getRegister(lhs_index)   // e.g., w9
    rhs_reg = getRegister(rhs_index)   // e.g., w10
    dst_reg = allocateRegister(index)  // e.g., w11

    emit("    add     {}, {}, {}", dst_reg, lhs_reg, rhs_reg)
}
```

**Example:**

```
Source:   2 + 3

ZIR:      %0 = literal(2)
          %1 = literal(3)
          %2 = add(%0, %1)

ARM64:    mov     w9, #2          // %0
          mov     w10, #3         // %1
          add     w11, w9, w10    // %2 = %0 + %1
```

**Compare to x86:**

```asm
// ARM64: clean 3-operand, doesn't modify sources
add     w11, w9, w10    // w11 = w9 + w10, w9 and w10 unchanged

// x86: 2-operand, must copy first
movl    %r10d, %r12d    // copy lhs
addl    %r11d, %r12d    // r12d = r12d + r11d (modifies r12d)
```

---

## Sub-lesson 6.2: Subtraction

### The Problem

Subtraction is similar, but order matters: `a - b` is not the same as `b - a`.

### The Solution

```asm
sub     w11, w9, w10    // w11 = w9 - w10
```

**Implementation:**

```
generateSub(index, lhs_index, rhs_index) {
    lhs_reg = getRegister(lhs_index)
    rhs_reg = getRegister(rhs_index)
    dst_reg = allocateRegister(index)

    emit("    sub     {}, {}, {}", dst_reg, lhs_reg, rhs_reg)
}
```

**Example:**

```
Source:   10 - 3

ZIR:      %0 = literal(10)
          %1 = literal(3)
          %2 = sub(%0, %1)

ARM64:    mov     w9, #10         // %0
          mov     w10, #3         // %1
          sub     w11, w9, w10    // %2 = 10 - 3 = 7
```

---

## Sub-lesson 6.3: Multiplication

### The Problem

Multiply two values. Is it as clean as add/sub?

### The Solution

Yes! The `mul` instruction follows the same 3-operand pattern:

```asm
mul     w11, w9, w10    // w11 = w9 * w10
```

**Implementation:**

```
generateMul(index, lhs_index, rhs_index) {
    lhs_reg = getRegister(lhs_index)
    rhs_reg = getRegister(rhs_index)
    dst_reg = allocateRegister(index)

    emit("    mul     {}, {}, {}", dst_reg, lhs_reg, rhs_reg)
}
```

**Example:**

```
Source:   6 * 7

ZIR:      %0 = literal(6)
          %1 = literal(7)
          %2 = mul(%0, %1)

ARM64:    mov     w9, #6
          mov     w10, #7
          mul     w11, w9, w10    // w11 = 42
```

---

## Sub-lesson 6.4: Division (The Easy One!)

### The Problem

Division is notoriously complex on x86 (special registers, sign extension). Is ARM64 simpler?

### The Solution

Yes! ARM64's `sdiv` (signed divide) is just another 3-operand instruction:

```asm
sdiv    w11, w9, w10    // w11 = w9 / w10 (signed)
```

That's it! No special registers, no setup, no `cdq` nonsense.

**Implementation:**

```
generateDiv(index, lhs_index, rhs_index) {
    lhs_reg = getRegister(lhs_index)
    rhs_reg = getRegister(rhs_index)
    dst_reg = allocateRegister(index)

    emit("    sdiv    {}, {}, {}", dst_reg, lhs_reg, rhs_reg)
}
```

**Example:**

```
Source:   42 / 6

ZIR:      %0 = literal(42)
          %1 = literal(6)
          %2 = div(%0, %1)

ARM64:    mov     w9, #42
          mov     w10, #6
          sdiv    w11, w9, w10    // w11 = 7
```

**Compare to x86:**

```
┌─────────────────────────────────────────────────────────────────────┐
│ DIVISION: ARM64 vs x86                                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ ARM64 (1 instruction):                                             │
│   sdiv    w11, w9, w10        // that's it!                        │
│                                                                     │
│ x86 (4 instructions):                                              │
│   movl    %r10d, %eax         // dividend in eax                   │
│   cdq                          // sign-extend to edx:eax           │
│   idivl   %r11d               // divide by r11d                    │
│   movl    %eax, %r12d         // quotient from eax                 │
│                                                                     │
│ ARM64 is 4x simpler for division!                                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Complete Arithmetic Code Generator

```
generateBinaryOp(index, op, lhs_index, rhs_index) {
    lhs_reg = getRegister(lhs_index)
    rhs_reg = getRegister(rhs_index)
    dst_reg = allocateRegister(index)

    if op == "add" {
        emit("    add     {}, {}, {}", dst_reg, lhs_reg, rhs_reg)
    }
    else if op == "sub" {
        emit("    sub     {}, {}, {}", dst_reg, lhs_reg, rhs_reg)
    }
    else if op == "mul" {
        emit("    mul     {}, {}, {}", dst_reg, lhs_reg, rhs_reg)
    }
    else if op == "div" {
        emit("    sdiv    {}, {}, {}", dst_reg, lhs_reg, rhs_reg)
    }
}
```

---

## Summary: Arithmetic Generation

```
┌────────────────────────────────────────────────────────────────────┐
│ ARM64 ARITHMETIC PATTERNS                                          │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│ All operations follow the same clean pattern:                      │
│   opcode  dst, src1, src2                                         │
│                                                                    │
│ ADD:    add   wD, wA, wB      // wD = wA + wB                     │
│ SUB:    sub   wD, wA, wB      // wD = wA - wB                     │
│ MUL:    mul   wD, wA, wB      // wD = wA * wB                     │
│ DIV:    sdiv  wD, wA, wB      // wD = wA / wB (signed)            │
│                                                                    │
│ Benefits over x86:                                                 │
│   - 3-operand: doesn't modify sources                             │
│   - Uniform: all ops look the same                                │
│   - Simple division: no special register setup                    │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

---

## Try It Yourself

Compute `(10 + 5) * 2`:

```bash
cat > arith.s << 'EOF'
    .text
    .globl _main
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // %0 = literal(10)
    mov     w9, #10

    // %1 = literal(5)
    mov     w10, #5

    // %2 = add(%0, %1) = 15
    add     w11, w9, w10

    // %3 = literal(2)
    mov     w12, #2

    // %4 = mul(%2, %3) = 30
    mul     w13, w11, w12

    // return %4
    mov     w0, w13

    ldp     x29, x30, [sp], #16
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
    .globl _main
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // 100 / 4 = 25
    mov     w9, #100
    mov     w10, #4
    sdiv    w11, w9, w10
    mov     w0, w11

    ldp     x29, x30, [sp], #16
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
