---
title: "3.2: Flatten Expressions"
weight: 2
---

# Lesson 3.2: Flattening Simple Expressions

Convert tree expressions into linear instructions.

---

## Goal

Generate ZIR for simple expressions like `3 + 5`.

---

## The Transformation

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         FLATTENING                                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   AST (tree):                     ZIR (linear):                             │
│                                                                              │
│        +                          %0 = constant(3)                          │
│       / \                         %1 = constant(5)                          │
│      3   5                        %2 = add(%0, %1)                          │
│                                                                              │
│   "Flattening" = turning nested structure into sequential instructions      │
│                                                                              │
│   Key insight: Process children BEFORE parent                               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## ZIR Generator State

```
ZIRGenerator {
    instructions: Instruction[]

    // Add instruction and return its index
    emit(instruction) → InstrRef:
        index = length(instructions)
        instructions.append(instruction)
        return index
}
```

---

## Generate Expression

```
function generateExpr(expr) → InstrRef:
    switch expr.type:
        NumberExpr:
            return emit(Constant { value: expr.value })

        IdentifierExpr:
            return emit(DeclRef { name: expr.name })

        UnaryExpr:
            operand = generateExpr(expr.operand)   // Generate child first
            return emit(Negate { operand: operand })

        BinaryExpr:
            lhs = generateExpr(expr.left)          // Generate left first
            rhs = generateExpr(expr.right)         // Then right
            return emit(binaryOp(expr.operator, lhs, rhs))
```

---

## Binary Operation Helper

```
function binaryOp(operator, lhs, rhs) → Instruction:
    switch operator.type:
        PLUS:  return Add { lhs, rhs }
        MINUS: return Sub { lhs, rhs }
        STAR:  return Mul { lhs, rhs }
        SLASH: return Div { lhs, rhs }
```

---

## Step-by-Step: `3 + 5`

```
AST:
    BinaryExpr {
        left: NumberExpr { value: 3 },
        operator: PLUS,
        right: NumberExpr { value: 5 }
    }

generateExpr(BinaryExpr):
    lhs = generateExpr(NumberExpr { value: 3 }):
        emit(Constant { value: 3 }) → returns 0
    lhs = 0

    rhs = generateExpr(NumberExpr { value: 5 }):
        emit(Constant { value: 5 }) → returns 1
    rhs = 1

    emit(Add { lhs: 0, rhs: 1 }) → returns 2

Result:
    [0] Constant { value: 3 }
    [1] Constant { value: 5 }
    [2] Add { lhs: 0, rhs: 1 }

Text:
    %0 = constant(3)
    %1 = constant(5)
    %2 = add(%0, %1)
```

---

## The Key: Recursion Order

Children are processed BEFORE parents:

```
      +
     / \
    3   5

Order of processing:
1. 3 (left child)   → %0 = constant(3)
2. 5 (right child)  → %1 = constant(5)
3. + (parent)       → %2 = add(%0, %1)

This is POST-ORDER traversal.
```

---

## Verify Your Implementation

### Test 1: Single number
```
Input:  NumberExpr { value: 42 }
ZIR:    %0 = constant(42)
```

### Test 2: Simple addition
```
Input:  BinaryExpr(3, +, 5)
ZIR:
    %0 = constant(3)
    %1 = constant(5)
    %2 = add(%0, %1)
```

### Test 3: Subtraction
```
Input:  BinaryExpr(10, -, 4)
ZIR:
    %0 = constant(10)
    %1 = constant(4)
    %2 = sub(%0, %1)
```

### Test 4: Multiplication
```
Input:  BinaryExpr(3, *, 7)
ZIR:
    %0 = constant(3)
    %1 = constant(7)
    %2 = mul(%0, %1)
```

### Test 5: Unary negation
```
Input:  UnaryExpr(-, NumberExpr(42))
ZIR:
    %0 = constant(42)
    %1 = negate(%0)
```

### Test 6: Identifier
```
Input:  IdentifierExpr { name: "x" }
ZIR:    %0 = decl_ref("x")
```

---

## What's Next

Let's handle nested expressions with correct ordering.

Next: [Lesson 3.3: Nested Expressions](../03-flatten-nested/) →
