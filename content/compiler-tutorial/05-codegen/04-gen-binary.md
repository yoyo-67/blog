---
title: "5.4: Binary Operations"
weight: 4
---

# Lesson 5.4: Generating Binary Operations

Emit code for arithmetic operations.

---

## Goal

Generate C code for operations like `add_i32`, `sub_i32`, `mul_i32`, `div_i32`.

---

## The Pattern

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    BINARY OPERATION GENERATION                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   AIR:                          C Code:                                     │
│                                                                              │
│   %2 = add_i32(%0, %1)         int32_t t2 = t0 + t1;                       │
│   %4 = sub_i64(%2, %3)         int64_t t4 = t2 - t3;                       │
│   %6 = mul_i32(%4, %5)         int32_t t6 = t4 * t5;                       │
│   %8 = div_i32(%6, %7)         int32_t t8 = t6 / t7;                       │
│                                                                              │
│   Pattern: [type] t[index] = t[lhs] [op] t[rhs];                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Operator Mapping

```
function airTagToOperator(tag) → string:
    switch tag:
        ADD_I32, ADD_I64:  return "+"
        SUB_I32, SUB_I64:  return "-"
        MUL_I32, MUL_I64:  return "*"
        DIV_I32, DIV_I64:  return "/"
```

---

## Generate Binary Operation

```
function generateBinaryOp(instr, index):
    type_str = typeToCType(instr.type)
    op_str = airTagToOperator(instr.tag)
    lhs = instr.data.lhs
    rhs = instr.data.rhs

    emitIndent()
    emit(type_str)
    emit(" t")
    emit(index)
    emit(" = t")
    emit(lhs)
    emit(" ")
    emit(op_str)
    emit(" t")
    emit(rhs)
    emitLine(";")
```

---

## Example: Addition

```
Context:
    %0 = const_i32(3)     → int32_t t0 = 3;
    %1 = const_i32(5)     → int32_t t1 = 5;
    %2 = add_i32(%0, %1)  → ???

generateBinaryOp(add_i32(%0, %1), 2):
    type_str = "int32_t"
    op_str = "+"
    lhs = 0
    rhs = 1

    Output: "    int32_t t2 = t0 + t1;"

Full output:
    int32_t t0 = 3;
    int32_t t1 = 5;
    int32_t t2 = t0 + t1;
```

---

## Unary Operations

Negation follows a similar pattern:

```
AIR:                          C Code:
%1 = neg_i32(%0)              int32_t t1 = -t0;
```

```
function generateUnaryOp(instr, index):
    type_str = typeToCType(instr.type)
    operand = instr.data.operand

    emitIndent()
    emit(type_str)
    emit(" t")
    emit(index)
    emit(" = -t")
    emit(operand)
    emitLine(";")
```

---

## Complete Example

```
Source: 1 + 2 * 3

AIR:
    %0 = const_i32(1)
    %1 = const_i32(2)
    %2 = const_i32(3)
    %3 = mul_i32(%1, %2)
    %4 = add_i32(%0, %3)

Generated C:
    int32_t t0 = 1;
    int32_t t1 = 2;
    int32_t t2 = 3;
    int32_t t3 = t1 * t2;
    int32_t t4 = t0 + t3;

// t4 = 1 + (2 * 3) = 7
```

---

## Operator Precedence?

You might worry: does `t0 + t3` have the right precedence?

No problem! Each operation uses its own temporary:
- We don't generate `t0 + t1 * t2`
- We generate `t3 = t1 * t2; t4 = t0 + t3;`

The AIR already encodes evaluation order correctly.

---

## Verify Your Implementation

### Test 1: Addition
```
AIR:    add_i32(%0, %1) at index 2
Output: "int32_t t2 = t0 + t1;"
```

### Test 2: Subtraction
```
AIR:    sub_i32(%3, %4) at index 5
Output: "int32_t t5 = t3 - t4;"
```

### Test 3: Multiplication
```
AIR:    mul_i64(%0, %1) at index 2
Output: "int64_t t2 = t0 * t1;"
```

### Test 4: Division
```
AIR:    div_i32(%2, %3) at index 4
Output: "int32_t t4 = t2 / t3;"
```

### Test 5: Negation
```
AIR:    neg_i32(%0) at index 1
Output: "int32_t t1 = -t0;"
```

### Test 6: Chain of operations
```
AIR:
    %0 = const_i32(10)
    %1 = const_i32(3)
    %2 = sub_i32(%0, %1)
    %3 = const_i32(2)
    %4 = mul_i32(%2, %3)

Output:
    int32_t t0 = 10;
    int32_t t1 = 3;
    int32_t t2 = t0 - t1;
    int32_t t3 = 2;
    int32_t t4 = t2 * t3;
```

---

## What's Next

Let's handle variables (parameters and locals).

Next: [Lesson 5.5: Variables](../05-gen-variables/) →
