---
title: "5c.5: Generating Arithmetic"
weight: 5
---

# Lesson 5c.5: Generating Arithmetic

Emit instructions for arithmetic operations.

---

## Goal

Generate bytecode for `add`, `sub`, `mul`, `div`, and `neg` operations.

---

## The Pattern

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    ARITHMETIC GENERATION                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   AIR:                          Bytecode:                                   │
│                                                                              │
│   %0 = const_i32(3)            PUSH_I32 3                                  │
│   %1 = const_i32(5)            PUSH_I32 5                                  │
│   %2 = add_i32(%0, %1)         ADD_I32                                     │
│                                                                              │
│   The operands are already on the stack!                                    │
│   Arithmetic ops just emit a single opcode.                                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Insight: Operands Already on Stack

When we reach `add_i32(%0, %1)`:
- `%0` (value 3) was pushed earlier
- `%1` (value 5) was pushed earlier
- They're sitting on the stack, ready to be used

We just emit `ADD_I32` - it pops both and pushes the result.

---

## Generate Binary Operation

```
function generateBinaryOp(instr):
    switch instr.tag:
        ADD_I32: emitByte(ADD_I32)
        SUB_I32: emitByte(SUB_I32)
        MUL_I32: emitByte(MUL_I32)
        DIV_I32: emitByte(DIV_I32)
        ADD_I64: emitByte(ADD_I64)
        SUB_I64: emitByte(SUB_I64)
        MUL_I64: emitByte(MUL_I64)
        DIV_I64: emitByte(DIV_I64)
```

That's it! One byte per arithmetic operation.

---

## Wait, Where Are the Operands?

This is the magic of stack machines. Let's trace:

```
AIR:
    %0 = const_i32(3)
    %1 = const_i32(5)
    %2 = add_i32(%0, %1)

Generation:

    %0: generateConstant → PUSH_I32 3
    %1: generateConstant → PUSH_I32 5
    %2: generateBinaryOp → ADD_I32

Bytecode: PUSH_I32 3, PUSH_I32 5, ADD_I32

Execution trace:
    PUSH_I32 3  → Stack: [3]
    PUSH_I32 5  → Stack: [3][5]
    ADD_I32     → Stack: [8]     ← pops 3 and 5, pushes 8
```

The operands are consumed in the order they were pushed!

---

## Generate Unary Operation

```
function generateUnaryOp(instr):
    switch instr.tag:
        NEG_I32: emitByte(NEG_I32)
        NEG_I64: emitByte(NEG_I64)
```

Negation pops one value and pushes its negation.

---

## Example: Negation

```
AIR:
    %0 = const_i32(5)
    %1 = neg_i32(%0)

Bytecode:
    PUSH_I32 5
    NEG_I32

Execution:
    PUSH_I32 5  → Stack: [5]
    NEG_I32     → Stack: [-5]
```

---

## Complex Expression: 1 + 2 * 3

```
Source: 1 + 2 * 3

AIR (precedence already handled):
    %0 = const_i32(1)
    %1 = const_i32(2)
    %2 = const_i32(3)
    %3 = mul_i32(%1, %2)    ← 2 * 3 first
    %4 = add_i32(%0, %3)    ← then 1 + result

Bytecode:
    PUSH_I32 1
    PUSH_I32 2
    PUSH_I32 3
    MUL_I32
    ADD_I32

Execution:
    PUSH_I32 1  → [1]
    PUSH_I32 2  → [1][2]
    PUSH_I32 3  → [1][2][3]
    MUL_I32     → [1][6]      ← 2*3=6
    ADD_I32     → [7]         ← 1+6=7
```

---

## The Problem: Stack Order

Wait, there's a subtlety. When we generate `add_i32(%0, %3)`:
- `%0` was pushed at instruction 0
- `%3` was computed at instruction 3

But by instruction 4, the stack has `[1][6]`, not `[6][1]`.

This works because AIR instructions are ordered so that:
1. Push left operand
2. Push right operand (or compute it)
3. Perform operation

The parser and ZIR generation already ensure this order!

---

## Non-Commutative Operations

For subtraction and division, order matters:

```
Source: 10 - 3

AIR:
    %0 = const_i32(10)
    %1 = const_i32(3)
    %2 = sub_i32(%0, %1)

Bytecode:
    PUSH_I32 10
    PUSH_I32 3
    SUB_I32

Execution:
    PUSH_I32 10 → [10]
    PUSH_I32 3  → [10][3]
    SUB_I32     → [7]     ← 10 - 3 = 7, correct!

SUB_I32 semantics: pop b, pop a, push (a - b)
```

---

## Stack Effects Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        STACK EFFECTS                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Instruction      Before          After           Net                      │
│   ────────────────────────────────────────────────────────                  │
│   PUSH_I32 n      [....]          [....][n]       +1                        │
│   ADD_I32         [..][a][b]      [..][a+b]       -1                        │
│   SUB_I32         [..][a][b]      [..][a-b]       -1                        │
│   MUL_I32         [..][a][b]      [..][a*b]       -1                        │
│   DIV_I32         [..][a][b]      [..][a/b]       -1                        │
│   NEG_I32         [..][a]         [..][-a]         0                        │
│                                                                              │
│   Binary ops: pop 2, push 1 → net -1                                        │
│   Unary ops:  pop 1, push 1 → net  0                                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Verify Your Implementation

### Test 1: Addition
```
AIR:    %0 = const_i32(3)
        %1 = const_i32(5)
        %2 = add_i32(%0, %1)

Bytecode:
        PUSH_I32 3
        PUSH_I32 5
        ADD_I32

Result: 8
```

### Test 2: Subtraction
```
AIR:    %0 = const_i32(10)
        %1 = const_i32(3)
        %2 = sub_i32(%0, %1)

Bytecode:
        PUSH_I32 10
        PUSH_I32 3
        SUB_I32

Result: 7
```

### Test 3: Negation
```
AIR:    %0 = const_i32(5)
        %1 = neg_i32(%0)

Bytecode:
        PUSH_I32 5
        NEG_I32

Result: -5
```

### Test 4: Complex expression (2 + 3) * 4
```
AIR:    %0 = const_i32(2)
        %1 = const_i32(3)
        %2 = add_i32(%0, %1)
        %3 = const_i32(4)
        %4 = mul_i32(%2, %3)

Bytecode:
        PUSH_I32 2
        PUSH_I32 3
        ADD_I32
        PUSH_I32 4
        MUL_I32

Result: 20
```

---

## What's Next

Let's handle functions - parameters and local variables.

Next: [Lesson 5c.6: Generating Functions](../06-gen-functions/) →
