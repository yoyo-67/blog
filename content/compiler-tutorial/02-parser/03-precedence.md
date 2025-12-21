---
title: "2.3: Precedence"
weight: 3
---

# Lesson 2.3: Operator Precedence

`1 + 2 * 3` should be `7`, not `9`. How do we make `*` happen before `+`?

---

## Goal

Use a two-level grammar to handle operator precedence correctly.

---

## The Problem

Our current grammar treats all operators the same:

```
expression → NUMBER (("+" | "-" | "*" | "/") NUMBER)*
```

Let's trace `1 + 2 * 3`:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    THE PROBLEM: WRONG PRECEDENCE                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Input: 1 + 2 * 3                                                          │
│                                                                              │
│   Our parser (left-to-right):                                               │
│     1. left = 1                                                             │
│     2. see "+", left = (1 + 2)                                              │
│     3. see "*", left = ((1 + 2) * 3)                                        │
│                                                                              │
│   Result: (1 + 2) * 3 = 9   ✗ WRONG!                                        │
│                                                                              │
│   Expected: 1 + (2 * 3) = 7  ✓                                              │
│                                                                              │
│   The parser builds the WRONG tree:                                         │
│                                                                              │
│        Wrong tree:               Correct tree:                              │
│                                                                              │
│            Mul                       Add                                    │
│           /   \                     /   \                                   │
│         Add    3                   1    Mul                                 │
│        /   \                           /   \                                │
│       1     2                         2     3                               │
│                                                                              │
│   In math, * has HIGHER PRECEDENCE than +.                                  │
│   Multiplication should happen FIRST.                                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Insight: Tree Depth = Evaluation Order

In a tree, **deeper nodes are evaluated first**:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      TREE DEPTH = EVALUATION ORDER                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   To evaluate a tree, work from LEAVES to ROOT:                             │
│                                                                              │
│              Add           Evaluation:                                      │
│             /   \                                                            │
│            1    Mul         1. Mul(2, 3) = 6   (deeper = first)             │
│                /   \        2. Add(1, 6) = 7   (root = last)                │
│               2     3                                                        │
│                                                                              │
│   The Mul is NESTED INSIDE Add, so it happens first.                        │
│                                                                              │
│   Rule: To make operator X happen before operator Y,                        │
│         X must be DEEPER in the tree (nested inside Y).                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

So to make `*` happen before `+`, we need `*` nodes **nested inside** `+` nodes.

---

## The Solution: Two-Level Grammar

Split into two rules, one for each precedence level:

```
expression → term (("+" | "-") term)*
term       → NUMBER (("*" | "/") NUMBER)*
```

Let's understand this step by step.

---

## Think of It Like Boxes

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          THE "BOXES" ANALOGY                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   expression deals with BOXES connected by + or -:                          │
│                                                                              │
│   ┌─────┐     ┌─────┐     ┌─────┐                                           │
│   │term │  +  │term │  +  │term │  ...                                      │
│   └─────┘     └─────┘     └─────┘                                           │
│                                                                              │
│   Each box (term) can contain multiplication INSIDE:                        │
│                                                                              │
│   ┌─────────────────┐                                                       │
│   │ 2 * 3 * 4       │  ← this whole thing is ONE term                       │
│   └─────────────────┘                                                       │
│                                                                              │
│   So "1 + 2 * 3 + 4" becomes:                                               │
│                                                                              │
│   ┌─────┐     ┌─────────┐     ┌─────┐                                       │
│   │  1  │  +  │  2 * 3  │  +  │  4  │                                       │
│   └─────┘     └─────────┘     └─────┘                                       │
│      │             │             │                                          │
│     term         term          term                                         │
│                                                                              │
│   expression only sees 3 terms connected by +                               │
│   The * is HIDDEN inside the middle term!                                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## How It Works

```
expression → term (("+" | "-") term)*
```

This says:
- First, get a `term` (whatever that is)
- Then, zero or more: get `+` or `-`, then another `term`

```
term → NUMBER (("*" | "/") NUMBER)*
```

This says:
- First, get a `NUMBER`
- Then, zero or more: get `*` or `/`, then another `NUMBER`

**Key insight: `expression` doesn't see numbers directly. It sees `term`s.**

---

## Step-by-Step Trace

Let's trace `1 + 2 * 3` with our two-level grammar:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    THE MAGIC OF TWO-LEVEL GRAMMAR                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   expression() starts:                                                       │
│       "I need a term first"                                                 │
│       │                                                                      │
│       ▼                                                                      │
│   term():                                                                    │
│       get NUMBER → 1                                                        │
│       see "*" or "/"? NO (I see "+")                                        │
│       return 1                                                              │
│       │                                                                      │
│       ▼                                                                      │
│   expression() continues:                                                    │
│       left = 1                                                              │
│       see "+" or "-"? YES, see "+"                                          │
│       consume "+"                                                           │
│       "I need another term"                                                 │
│       │                                                                      │
│       ▼                                                                      │
│   term():                     ◄─── HERE'S THE MAGIC                         │
│       get NUMBER → 2                                                        │
│       see "*" or "/"? YES! see "*"     ◄─── term handles the *             │
│       consume "*"                                                           │
│       get NUMBER → 3                                                        │
│       left = 2 * 3 = Mul(2, 3)                                             │
│       see "*" or "/"? NO                                                    │
│       return Mul(2, 3)        ◄─── returns the WHOLE multiplication        │
│       │                                                                      │
│       ▼                                                                      │
│   expression() continues:                                                    │
│       right = Mul(2, 3)       ◄─── expression gets (2*3) as one unit       │
│       left = Add(1, Mul(2, 3))                                             │
│       see "+" or "-"? NO                                                    │
│       return Add(1, Mul(2, 3))                                             │
│                                                                              │
│   Result: 1 + (2 * 3) = 7  ✓                                                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

**The key moment**: when `expression` asks for its second `term`, the `term` function sees the `*` and handles it internally. By the time `term` returns, the multiplication is already done!

---

## Detailed Token Trace

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    PARSING "1 + 2 * 3" WITH PRECEDENCE                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [1] [+] [2] [*] [3]                                               │
│            ▲                                                                 │
│                                                                              │
│   expression(): Call term() for left side                                   │
│                                                                              │
│       term():                                                                │
│           Parse NUMBER → 1                                                  │
│           See "*" or "/"? No (see "+")                                      │
│           Return 1                                                          │
│                                                                              │
│       left = 1                                                              │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [1] [+] [2] [*] [3]                                               │
│               ▲                                                              │
│                                                                              │
│   expression(): See "+"? Yes                                                │
│                 Consume "+"                                                  │
│                 Call term() for right side                                  │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [1] [+] [2] [*] [3]                                               │
│                   ▲                                                          │
│                                                                              │
│       term():                                                                │
│           Parse NUMBER → 2                                                  │
│           See "*" or "/"? YES! See "*"     ◄─── HANDLES IT!                │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [1] [+] [2] [*] [3]                                               │
│                       ▲                                                      │
│                                                                              │
│       term() (continuing):                                                   │
│           Consume "*"                                                        │
│           Parse NUMBER → 3                                                  │
│           left = Mul(2, 3)                                                  │
│           See "*" or "/"? No                                                │
│           Return Mul(2, 3)                                                  │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [1] [+] [2] [*] [3] [EOF]                                         │
│                               ▲                                              │
│                                                                              │
│   expression() (continuing):                                                 │
│       right = Mul(2, 3)                                                     │
│       left = Add(1, Mul(2, 3))                                              │
│       See "+"? No (EOF)                                                     │
│       Return Add(1, Mul(2, 3))                                              │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Final tree:                                                                │
│              Add                                                             │
│             /   \                                                            │
│            1    Mul                                                          │
│                /   \                                                         │
│               2     3                                                        │
│                                                                              │
│   Evaluation: 1 + (2 * 3) = 1 + 6 = 7  ✓ Correct!                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## The Golden Rule

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                     HOW NESTING CREATES PRECEDENCE                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Grammar:                                                                   │
│     expression → term (("+" | "-") term)*    ← LOW precedence (outer)       │
│     term       → NUMBER (("*" | "/") NUMBER)*  ← HIGH precedence (inner)    │
│                                                                              │
│   The Golden Rule:                                                           │
│                                                                              │
│   The function that gets called FIRST handles the operators                 │
│   that should happen FIRST (higher precedence).                             │
│                                                                              │
│   Call chain:                                                                │
│     expression calls term                                                    │
│     term handles * and /                                                    │
│     Therefore * and / happen before + and -                                 │
│                                                                              │
│   Rule of thumb:                                                             │
│     - Rules that call OTHER rules have LOWER precedence                     │
│     - Rules that are CALLED have HIGHER precedence                          │
│     - Called first = evaluated first = higher precedence                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## One Rule vs Two Rules

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      COMPARE: ONE RULE VS TWO RULES                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ONE RULE (wrong):                TWO RULES (correct):                     │
│   ─────────────────               ──────────────────────                    │
│                                                                              │
│   expression →                    expression →                              │
│     NUMBER ((+|*) NUMBER)*          term ((+|-) term)*                      │
│                                                                              │
│                                   term →                                    │
│                                     NUMBER ((*|/) NUMBER)*                  │
│                                                                              │
│                                                                              │
│   Parsing "1 + 2 * 3":            Parsing "1 + 2 * 3":                      │
│   ─────────────────               ──────────────────────                    │
│                                                                              │
│   1. left = 1                     1. expression calls term                  │
│   2. see +                           term returns 1                         │
│   3. left = 1 + 2                 2. expression sees +                      │
│   4. see *                        3. expression calls term                  │
│   5. left = (1+2) * 3                term gets 2                            │
│                                      term sees * ← HANDLES IT!              │
│      = 9  WRONG!                     term gets 3                            │
│                                      term returns (2*3)                     │
│                                   4. expression builds 1 + (2*3)            │
│                                                                              │
│                                      = 7  CORRECT!                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Translating to Code

```
// Grammar:
//   expression → term (("+" | "-") term)*
//   term       → NUMBER (("*" | "/") NUMBER)*

function parseExpression():
    left = parseTerm()              // Get first term

    while see(PLUS) or see(MINUS):  // (("+" | "-") term)*
        op = advance()
        right = parseTerm()
        if op.type == PLUS:
            left = AddNode(left, right)
        else:
            left = SubNode(left, right)

    return left

function parseTerm():
    left = parseNumber()            // Get first NUMBER

    while see(STAR) or see(SLASH):  // (("*" | "/") NUMBER)*
        op = advance()
        right = parseNumber()
        if op.type == STAR:
            left = MulNode(left, right)
        else:
            left = DivNode(left, right)

    return left
```

---

## Verify Your Implementation

### Test 1: Multiplication before addition
```
Input:  "1 + 2 * 3"
AST:    AddNode {
            left: NumberNode(1),
            right: MulNode {
                left: NumberNode(2),
                right: NumberNode(3)
            }
        }

Evaluation: 1 + (2 * 3) = 7  ✓
```

### Test 2: Addition before multiplication
```
Input:  "1 * 2 + 3"
AST:    AddNode {
            left: MulNode {
                left: NumberNode(1),
                right: NumberNode(2)
            },
            right: NumberNode(3)
        }

Evaluation: (1 * 2) + 3 = 5  ✓
```

### Test 3: Chain of multiplications
```
Input:  "2 * 3 * 4"
AST:    MulNode {
            left: MulNode {
                left: NumberNode(2),
                right: NumberNode(3)
            },
            right: NumberNode(4)
        }

Evaluation: (2 * 3) * 4 = 24  ✓
```

### Test 4: Mixed expression
```
Input:  "1 + 2 * 3 + 4"
AST:    AddNode {
            left: AddNode {
                left: NumberNode(1),
                right: MulNode {
                    left: NumberNode(2),
                    right: NumberNode(3)
                }
            },
            right: NumberNode(4)
        }

Evaluation: (1 + (2 * 3)) + 4 = 11  ✓
```

---

## Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              SUMMARY                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Problem: All operators at the same level = wrong precedence               │
│                                                                              │
│   Solution: Split grammar into multiple levels                              │
│                                                                              │
│     expression → term ((+ | -) term)*     ← handles + -                     │
│     term       → NUMBER ((* | /) NUMBER)* ← handles * /                     │
│                                                                              │
│   How it works:                                                              │
│     1. expression calls term first                                          │
│     2. term handles all * and / before returning                           │
│     3. expression only sees the results (terms)                            │
│     4. Deeper in call stack = higher precedence                            │
│                                                                              │
│   Think of it as:                                                            │
│     - expression deals with BOXES connected by + -                          │
│     - Each box (term) can have * / INSIDE                                  │
│     - The * / is hidden from expression's view                             │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What's Next

What about `-5` or `(1 + 2) * 3`? We need unary operators and parentheses.

Next: [Lesson 2.4: Unary & Parentheses](../04-unary-parens/) →
