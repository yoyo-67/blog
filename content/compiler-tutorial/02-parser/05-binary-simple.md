---
title: "2.5: Binary Operators (Simple)"
weight: 5
---

# Lesson 2.5: Binary Operators (Simple)

Binary operators combine two expressions: `a + b`, `3 * 5`.

---

## Goal

Parse binary expressions, ignoring precedence for now. (We'll fix precedence next.)

---

## The Challenge

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    BINARY OPERATOR CHALLENGE                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Input: 1 + 2 + 3                                                          │
│                                                                              │
│   Two possible trees:                                                        │
│                                                                              │
│   Left-associative:          Right-associative:                             │
│         +                           +                                        │
│        / \                         / \                                       │
│       +   3                       1   +                                      │
│      / \                             / \                                     │
│     1   2                           2   3                                    │
│                                                                              │
│   (1 + 2) + 3 = 6               1 + (2 + 3) = 6                             │
│                                                                              │
│   For +, both give same answer. But for - or /:                             │
│   (8 - 5) - 2 = 1               8 - (5 - 2) = 5     ← Different!           │
│                                                                              │
│   We want LEFT-ASSOCIATIVE (standard math).                                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## First Attempt (Wrong!)

```
// WRONG - don't do this!
function parseExpression():
    left = parseUnary()

    if isBinaryOperator(peek()):
        operator = advance()
        right = parseExpression()    // ← Problem: right-recursive!
        return BinaryExpr { left, operator, right }

    return left
```

This gives right-associativity:
```
1 + 2 + 3 → 1 + (2 + 3)     WRONG!
```

---

## Correct Approach: Loop

```
function parseExpression():
    left = parseUnary()

    while isBinaryOperator(peek()):
        operator = advance()
        right = parseUnary()          // ← parseUnary, not parseExpression!
        left = BinaryExpr { left, operator, right }

    return left
```

This gives left-associativity:
```
1 + 2 + 3 → (1 + 2) + 3     CORRECT!
```

---

## Helper Function

```
function isBinaryOperator(token):
    return token.type in [PLUS, MINUS, STAR, SLASH]
```

---

## Step-by-Step Trace

```
Input: "1 + 2 + 3"
Tokens: [NUMBER(1), PLUS, NUMBER(2), PLUS, NUMBER(3), EOF]

parseExpression():
    left = parseUnary() → NumberExpr(1)

    Loop iteration 1:
        peek() → PLUS (is binary op? yes)
        operator = advance() → PLUS
        right = parseUnary() → NumberExpr(2)
        left = BinaryExpr(1, +, 2)

    Loop iteration 2:
        peek() → PLUS (is binary op? yes)
        operator = advance() → PLUS
        right = parseUnary() → NumberExpr(3)
        left = BinaryExpr(BinaryExpr(1, +, 2), +, 3)

    Loop iteration 3:
        peek() → EOF (is binary op? no)
        exit loop

    return BinaryExpr(BinaryExpr(1, +, 2), +, 3)

Tree:
      +
     / \
    +   3
   / \
  1   2
```

---

## Verify Your Implementation

### Test 1: Simple addition
```
Input:  "1 + 2"
AST:    BinaryExpr {
            left: NumberExpr(1),
            operator: PLUS,
            right: NumberExpr(2)
        }
```

### Test 2: Chain of additions
```
Input:  "1 + 2 + 3"
AST:    BinaryExpr {
            left: BinaryExpr {
                left: NumberExpr(1),
                operator: PLUS,
                right: NumberExpr(2)
            },
            operator: PLUS,
            right: NumberExpr(3)
        }
```

### Test 3: Mixed operators
```
Input:  "1 + 2 * 3"
AST:    BinaryExpr {
            left: BinaryExpr {
                left: NumberExpr(1),
                operator: PLUS,
                right: NumberExpr(2)
            },
            operator: STAR,
            right: NumberExpr(3)
        }
```

### Test 4: Subtraction (check associativity)
```
Input:  "8 - 5 - 2"

With LEFT associativity (correct):
    (8 - 5) - 2 = 1

With RIGHT associativity (wrong):
    8 - (5 - 2) = 5

AST:    BinaryExpr {
            left: BinaryExpr {
                left: NumberExpr(8),
                operator: MINUS,
                right: NumberExpr(5)
            },
            operator: MINUS,
            right: NumberExpr(2)
        }
```

### Test 5: With unary
```
Input:  "-1 + 2"
AST:    BinaryExpr {
            left: UnaryExpr { operator: MINUS, operand: NumberExpr(1) },
            operator: PLUS,
            right: NumberExpr(2)
        }
```

---

## The Problem

Look at Test 3 again:

```
Input:  "1 + 2 * 3"

Our AST:  (1 + 2) * 3 = 9

Math says: 1 + (2 * 3) = 7    ← Different!
```

We're ignoring operator precedence! Multiplication should happen before addition.

That's the next lesson.

---

## What's Next

Let's understand operator precedence and how to handle it.

Next: [Lesson 2.6: Precedence](../06-precedence/) →
