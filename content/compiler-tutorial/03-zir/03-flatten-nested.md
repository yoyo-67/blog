---
title: "3.3: Nested Expressions"
weight: 3
---

# Lesson 3.3: Flattening Nested Expressions

Handle expressions like `a + b * c` with correct evaluation order.

---

## Goal

Generate correct ZIR for complex nested expressions.

---

## The Challenge

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    NESTED EXPRESSION                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Expression: 1 + 2 * 3                                                     │
│                                                                              │
│   AST (parser already handled precedence):                                  │
│                                                                              │
│        +                                                                     │
│       / \                                                                    │
│      1   *                                                                   │
│         / \                                                                  │
│        2   3                                                                 │
│                                                                              │
│   Must compute 2 * 3 BEFORE the addition!                                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Same Algorithm Works!

The recursive algorithm from Lesson 3.2 handles this automatically:

```
generateExpr(BinaryExpr(1, +, BinaryExpr(2, *, 3))):

    lhs = generateExpr(NumberExpr(1)):
        emit(Constant { value: 1 }) → 0
    lhs = 0

    rhs = generateExpr(BinaryExpr(2, *, 3)):
        inner_lhs = generateExpr(NumberExpr(2)):
            emit(Constant { value: 2 }) → 1
        inner_rhs = generateExpr(NumberExpr(3)):
            emit(Constant { value: 3 }) → 2
        emit(Mul { lhs: 1, rhs: 2 }) → 3
    rhs = 3

    emit(Add { lhs: 0, rhs: 3 }) → 4

Result:
    %0 = constant(1)
    %1 = constant(2)
    %2 = constant(3)
    %3 = mul(%1, %2)      // 2 * 3 = 6
    %4 = add(%0, %3)       // 1 + 6 = 7
```

---

## Why It Works

```
Recursion naturally processes deeper nodes first:

        +  (last)
       / \
      1   *  (second-to-last)
   (first) / \
          2   3
       (2nd) (3rd)

Post-order traversal:
1. Visit left: 1 → %0
2. Visit right: recurse into *
   2a. Visit left: 2 → %1
   2b. Visit right: 3 → %2
   2c. Process *: %3 = mul(%1, %2)
3. Process +: %4 = add(%0, %3)
```

---

## More Complex Example

```
Expression: (1 + 2) * (3 + 4)

AST:
        *
       / \
      +   +
     / \ / \
    1  2 3  4

Post-order:
1. Left subtree: 1, 2, +
2. Right subtree: 3, 4, +
3. Root: *

ZIR:
    %0 = constant(1)
    %1 = constant(2)
    %2 = add(%0, %1)      // 1 + 2 = 3
    %3 = constant(3)
    %4 = constant(4)
    %5 = add(%3, %4)      // 3 + 4 = 7
    %6 = mul(%2, %5)      // 3 * 7 = 21
```

---

## With Unary Operations

```
Expression: -x + y

AST:
      +
     / \
    -   y
    |
    x

ZIR:
    %0 = decl_ref("x")
    %1 = negate(%0)
    %2 = decl_ref("y")
    %3 = add(%1, %2)
```

---

## Verify Your Implementation

### Test 1: Multiplication before addition
```
Input:  1 + 2 * 3
AST:    BinaryExpr(1, +, BinaryExpr(2, *, 3))
ZIR:
    %0 = constant(1)
    %1 = constant(2)
    %2 = constant(3)
    %3 = mul(%1, %2)
    %4 = add(%0, %3)
```

### Test 2: Chain of same operator
```
Input:  1 + 2 + 3
AST:    BinaryExpr(BinaryExpr(1, +, 2), +, 3)
ZIR:
    %0 = constant(1)
    %1 = constant(2)
    %2 = add(%0, %1)
    %3 = constant(3)
    %4 = add(%2, %3)
```

### Test 3: Parentheses change order
```
Input:  (1 + 2) * 3
AST:    BinaryExpr(BinaryExpr(1, +, 2), *, 3)
ZIR:
    %0 = constant(1)
    %1 = constant(2)
    %2 = add(%0, %1)
    %3 = constant(3)
    %4 = mul(%2, %3)
```

### Test 4: Deep nesting
```
Input:  1 + 2 * 3 + 4 * 5
AST:    ((1) + (2 * 3)) + (4 * 5)
ZIR:
    %0 = constant(1)
    %1 = constant(2)
    %2 = constant(3)
    %3 = mul(%1, %2)      // 6
    %4 = add(%0, %3)       // 7
    %5 = constant(4)
    %6 = constant(5)
    %7 = mul(%5, %6)      // 20
    %8 = add(%4, %7)       // 27
```

### Test 5: With negation
```
Input:  -1 + 2
AST:    BinaryExpr(UnaryExpr(-, 1), +, 2)
ZIR:
    %0 = constant(1)
    %1 = negate(%0)
    %2 = constant(2)
    %3 = add(%1, %2)
```

### Test 6: Mixed with identifiers
```
Input:  x * 2 + y
ZIR:
    %0 = decl_ref("x")
    %1 = constant(2)
    %2 = mul(%0, %1)
    %3 = decl_ref("y")
    %4 = add(%2, %3)
```

---

## Key Insight

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          KEY INSIGHT                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   The parser already encoded precedence in the tree structure!              │
│                                                                              │
│   1 + 2 * 3 → parsed as: BinaryExpr(1, +, BinaryExpr(2, *, 3))             │
│                                                                              │
│   The ZIR generator doesn't need to know about precedence.                  │
│   It just flattens the tree top-down, processing children first.            │
│                                                                              │
│   This is the beauty of well-designed compiler stages:                      │
│   Each stage has a simple job because earlier stages did their part.        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What's Next

Let's handle variable declarations and references properly.

Next: [Lesson 3.4: Name References](../04-name-references/) →
