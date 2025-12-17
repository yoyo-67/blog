---
title: "2.6: Precedence"
weight: 6
---

# Lesson 2.6: Understanding Precedence

Why `*` beats `+`, and how to represent it.

---

## Goal

Understand operator precedence and binding power before implementing it.

---

## The Problem

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        PRECEDENCE PROBLEM                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Input: 1 + 2 * 3                                                          │
│                                                                              │
│   Without precedence:              With precedence:                         │
│                                                                              │
│         *                                +                                   │
│        / \                              / \                                  │
│       +   3                            1   *                                 │
│      / \                                  / \                                │
│     1   2                                2   3                               │
│                                                                              │
│   = (1 + 2) * 3 = 9                 = 1 + (2 * 3) = 7                       │
│                                                                              │
│   Math convention: * and / before + and -                                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Binding Power

Think of operators as having "binding power" - how tightly they hold their operands.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          BINDING POWER                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Higher number = binds tighter = happens first                             │
│                                                                              │
│   Operator    Precedence (binding power)                                    │
│   ─────────   ──────────────────────────                                    │
│   + -         1 (low - happens last)                                        │
│   * /         2 (high - happens first)                                      │
│                                                                              │
│   In "1 + 2 * 3":                                                           │
│                                                                              │
│   1   +   2   *   3                                                         │
│       ↑       ↑                                                              │
│      bp=1   bp=2                                                            │
│                                                                              │
│   * has higher binding power, so it grabs 2 and 3 first.                    │
│   Then + gets what's left: 1 and (2*3).                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Define Precedence Table

```
function getBindingPower(tokenType):
    switch tokenType:
        PLUS, MINUS:   return 1
        STAR, SLASH:   return 2
        default:       return 0    // Not an operator
```

---

## The Intuition

When parsing `1 + 2 * 3`:

```
1. Parse 1
2. See +, binding power 1
3. Start building: 1 + ???
4. Parse 2
5. See *, binding power 2
   * has HIGHER power than +
   So 2 belongs to * MORE than to +
6. Build: 2 * 3
7. Now + gets: 1 + (2 * 3)
```

The key insight: **when we see a higher-precedence operator, it "steals" the operand from the lower-precedence one**.

---

## Another Example

```
1 * 2 + 3

1. Parse 1
2. See *, binding power 2
3. Start building: 1 * ???
4. Parse 2
5. See +, binding power 1
   + has LOWER power than *
   So 2 belongs to * (doesn't get stolen)
6. Build: 1 * 2
7. Now + gets: (1 * 2) + 3
```

---

## Complex Example

```
1 + 2 * 3 + 4

Step by step:
1. Parse 1
2. See + (bp=1), start: 1 + ???
3. Parse 2
4. See * (bp=2), higher! Steal 2.
   Build: 2 * ???
5. Parse 3
6. See + (bp=1), lower than *
   So 3 stays with *
   Build: 2 * 3
7. Back to first +: 1 + (2*3)
8. See + (bp=1), same precedence
   Left-associative: (1 + (2*3)) + ???
9. Parse 4
10. EOF
11. Final: (1 + (2*3)) + 4 = (1 + 6) + 4 = 7 + 4 = 11

Tree:
        +
       / \
      +   4
     / \
    1   *
       / \
      2   3
```

---

## Precedence Rules Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        PRECEDENCE RULES                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. Higher precedence operators bind tighter                               │
│      * binds 2*3 before + can claim 2                                       │
│                                                                              │
│   2. Equal precedence: left-to-right (left-associative)                     │
│      1 - 2 - 3 = (1 - 2) - 3                                                │
│                                                                              │
│   3. Parentheses override everything                                        │
│      (1 + 2) * 3 = 3 * 3 = 9                                                │
│                                                                              │
│   4. Unary operators have highest precedence                                │
│      -2 * 3 = (-2) * 3 = -6                                                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Full Precedence Table

For a complete language, you might have:

```
Precedence   Operators        Description
─────────────────────────────────────────────
   1         || or            Logical OR
   2         && and           Logical AND
   3         == !=            Equality
   4         < > <= >=        Comparison
   5         + -              Addition, Subtraction
   6         * / %            Multiplication, Division, Modulo
   7         - !              Unary (prefix)
```

For our mini compiler, we only need:
```
   1         + -
   2         * /
```

---

## What's Next

Now let's implement this with the "precedence climbing" algorithm.

Next: [Lesson 2.7: Precedence Implementation](../07-precedence-impl/) →
