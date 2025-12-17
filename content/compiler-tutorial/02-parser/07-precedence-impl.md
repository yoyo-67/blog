---
title: "2.7: Precedence Implementation"
weight: 7
---

# Lesson 2.7: Precedence Climbing

Implementing the precedence climbing algorithm.

---

## Goal

Modify `parseExpression` to respect operator precedence.

---

## The Algorithm

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                     PRECEDENCE CLIMBING                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   parseExpression(minPrecedence):                                           │
│       1. Parse left operand (atom/unary)                                    │
│       2. While next operator has precedence >= minPrecedence:               │
│          a. Get operator and its precedence                                 │
│          b. Parse right operand with higher minimum (precedence + 1)        │
│          c. Combine into BinaryExpr                                         │
│       3. Return result                                                       │
│                                                                              │
│   The key: recursively call with (precedence + 1) to let higher-precedence │
│   operators grab their operands first.                                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Implementation

```
function parseExpression(minPrecedence = 0):
    left = parseUnary()

    while true:
        operator = peek()
        precedence = getBindingPower(operator.type)

        // Stop if:
        // - Not an operator (precedence = 0)
        // - Operator precedence < minimum we're looking for
        if precedence < minPrecedence:
            break

        advance()  // consume operator

        // Recursive call with HIGHER minimum
        // This lets higher-precedence ops grab their operands
        right = parseExpression(precedence + 1)

        left = BinaryExpr {
            left: left,
            operator: operator,
            right: right
        }

    return left
```

---

## Binding Power Function

```
function getBindingPower(tokenType):
    switch tokenType:
        PLUS:   return 1
        MINUS:  return 1
        STAR:   return 2
        SLASH:  return 2
        default: return 0
```

---

## Trace: `1 + 2 * 3`

```
parseExpression(minPrecedence=0):
    left = parseUnary() → NumberExpr(1)

    Loop:
        operator = PLUS, precedence = 1
        1 >= 0? Yes, continue
        advance() → consume PLUS
        right = parseExpression(minPrecedence=2):     ← KEY: min=2
            left = parseUnary() → NumberExpr(2)

            Loop:
                operator = STAR, precedence = 2
                2 >= 2? Yes, continue
                advance() → consume STAR
                right = parseExpression(minPrecedence=3):
                    left = parseUnary() → NumberExpr(3)
                    Loop:
                        operator = EOF, precedence = 0
                        0 >= 3? No, break
                    return NumberExpr(3)
                left = BinaryExpr(2, *, 3)

            Loop:
                operator = EOF, precedence = 0
                0 >= 2? No, break
            return BinaryExpr(2, *, 3)

        left = BinaryExpr(1, +, BinaryExpr(2, *, 3))

    Loop:
        operator = EOF, precedence = 0
        0 >= 0? No, break

    return BinaryExpr(1, +, BinaryExpr(2, *, 3))

Tree:
      +
     / \
    1   *
       / \
      2   3

Result: 1 + (2 * 3) = 7 ✓
```

---

## Trace: `1 * 2 + 3`

```
parseExpression(minPrecedence=0):
    left = parseUnary() → NumberExpr(1)

    Loop 1:
        operator = STAR, precedence = 2
        2 >= 0? Yes
        advance() → consume STAR
        right = parseExpression(minPrecedence=3):
            left = parseUnary() → NumberExpr(2)
            Loop:
                operator = PLUS, precedence = 1
                1 >= 3? No, break           ← PLUS doesn't qualify!
            return NumberExpr(2)
        left = BinaryExpr(1, *, 2)

    Loop 2:
        operator = PLUS, precedence = 1
        1 >= 0? Yes
        advance() → consume PLUS
        right = parseExpression(minPrecedence=2):
            left = parseUnary() → NumberExpr(3)
            Loop:
                operator = EOF, precedence = 0
                0 >= 2? No, break
            return NumberExpr(3)
        left = BinaryExpr(BinaryExpr(1, *, 2), +, 3)

    return BinaryExpr(BinaryExpr(1, *, 2), +, 3)

Tree:
        +
       / \
      *   3
     / \
    1   2

Result: (1 * 2) + 3 = 5 ✓
```

---

## Why precedence + 1?

For left-associativity. With `1 + 2 + 3`:

```
parseExpression(0):
    left = 1

    PLUS (prec=1) >= 0? Yes
    right = parseExpression(2):      ← min=2, so PLUS (prec=1) won't match!
        left = 2
        PLUS (prec=1) >= 2? No       ← This is why +1
        return 2
    left = (1 + 2)

    PLUS (prec=1) >= 0? Yes
    right = parseExpression(2):
        return 3
    left = ((1 + 2) + 3)

Tree:
      +
     / \
    +   3
   / \
  1   2
```

If we used `precedence` instead of `precedence + 1`, same-precedence operators would associate right:

```
With precedence (not +1):
    1 + (2 + 3)    WRONG!

With precedence + 1:
    (1 + 2) + 3    CORRECT!
```

---

## Verify Your Implementation

### Test 1: Multiplication before addition
```
Input:  "1 + 2 * 3"
AST:    BinaryExpr(1, +, BinaryExpr(2, *, 3))
Eval:   1 + 6 = 7
```

### Test 2: Left associativity
```
Input:  "1 - 2 - 3"
AST:    BinaryExpr(BinaryExpr(1, -, 2), -, 3)
Eval:   (1 - 2) - 3 = -4
```

### Test 3: Complex expression
```
Input:  "1 + 2 * 3 + 4"
AST:    BinaryExpr(BinaryExpr(1, +, BinaryExpr(2, *, 3)), +, 4)
Eval:   (1 + 6) + 4 = 11
```

### Test 4: All multiplication
```
Input:  "2 * 3 * 4"
AST:    BinaryExpr(BinaryExpr(2, *, 3), *, 4)
Eval:   (2 * 3) * 4 = 24
```

### Test 5: Parentheses override
```
Input:  "(1 + 2) * 3"
AST:    BinaryExpr(BinaryExpr(1, +, 2), *, 3)
Eval:   3 * 3 = 9
```

### Test 6: Mixed everything
```
Input:  "-1 + 2 * (3 + 4)"
AST:    BinaryExpr(
            UnaryExpr(-, 1),
            +,
            BinaryExpr(2, *, BinaryExpr(3, +, 4))
        )
Eval:   -1 + 2 * 7 = -1 + 14 = 13
```

---

## Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                     PRECEDENCE CLIMBING SUMMARY                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   parseExpression(minPrecedence):                                           │
│       left = parseUnary()                                                   │
│       while getBindingPower(peek()) >= minPrecedence:                       │
│           op = advance()                                                    │
│           right = parseExpression(bindingPower(op) + 1)                     │
│           left = BinaryExpr(left, op, right)                                │
│       return left                                                            │
│                                                                              │
│   The +1 ensures left-associativity for same-precedence operators.          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What's Next

Expressions are done! Now let's parse statements.

Next: [Lesson 2.8: Statements](../08-statements/) →
