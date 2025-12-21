---
title: "2.2: Repetition"
weight: 2
---

# Lesson 2.2: Repetition and Loops

Our grammar only handles `1 + 2`. How do we handle `1 + 2 + 3`?

---

## Goal

Use the `*` operator in grammar rules and translate it to loops in code.

---

## The Problem

Our current rule:

```
expression → NUMBER "+" NUMBER
```

Only handles exactly TWO numbers:

```
✓  1 + 2         matches!
✗  1 + 2 + 3     three numbers - doesn't match!
✗  42            one number - doesn't match!
```

---

## The Solution: The `*` Operator

The `*` means "zero or more":

```
expression → NUMBER ("+" NUMBER)*
```

Read this as: "A number, followed by zero or more occurrences of (plus, number)."

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         THE * OPERATOR                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   expression → NUMBER ("+" NUMBER)*                                         │
│                       ─────────────                                          │
│                             │                                                │
│                             └─── This whole group can repeat 0+ times       │
│                                                                              │
│   Matches:                                                                   │
│                                                                              │
│     "42"           NUMBER, then 0 repeats           ✓                       │
│     "1 + 2"        NUMBER, then 1 repeat            ✓                       │
│     "1 + 2 + 3"    NUMBER, then 2 repeats           ✓                       │
│     "1 + 2 + 3 + 4" NUMBER, then 3 repeats          ✓                       │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Translating * to Code: Use a Loop

Grammar `*` becomes a `while` loop in code:

```
// Grammar: expression → NUMBER ("+" NUMBER)*

function parseExpression():
    left = parseNumber()           // First NUMBER

    while see(PLUS):               // ("+" NUMBER)*
        advance()                  // consume the "+"
        right = parseNumber()      // parse the NUMBER
        left = AddNode(left, right)

    return left
```

The pattern:
- `*` in grammar → `while` in code
- The loop continues as long as we see the starting token

---

## Step-by-Step Trace

Let's trace parsing `1 + 2 + 3`:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    PARSING "1 + 2 + 3" WITH REPETITION                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [1] [+] [2] [+] [3] [EOF]                                         │
│            ▲                                                                 │
│                                                                              │
│   Step 1: Parse first NUMBER                                                │
│           left = NumberNode(1)                                              │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [1] [+] [2] [+] [3] [EOF]                                         │
│               ▲                                                              │
│                                                                              │
│   Step 2: See "+"? YES → enter loop                                         │
│           advance() → consume "+"                                           │
│           right = parseNumber() → NumberNode(2)                             │
│           left = AddNode(1, 2)                                              │
│                                                                              │
│           Current tree:                                                      │
│                  Add                                                         │
│                 /   \                                                        │
│                1     2                                                       │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [1] [+] [2] [+] [3] [EOF]                                         │
│                       ▲                                                      │
│                                                                              │
│   Step 3: See "+"? YES → continue loop                                      │
│           advance() → consume "+"                                           │
│           right = parseNumber() → NumberNode(3)                             │
│           left = AddNode(AddNode(1, 2), 3)                                  │
│                                                                              │
│           Current tree:                                                      │
│                  Add                                                         │
│                 /   \                                                        │
│               Add    3                                                       │
│              /   \                                                           │
│             1     2                                                          │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [1] [+] [2] [+] [3] [EOF]                                         │
│                            ▲                                                 │
│                                                                              │
│   Step 4: See "+"? NO (see EOF) → exit loop                                 │
│           return left                                                        │
│                                                                              │
│           Final tree:                                                        │
│                  Add                                                         │
│                 /   \                                                        │
│               Add    3                                                       │
│              /   \                                                           │
│             1     2                                                          │
│                                                                              │
│           This represents: (1 + 2) + 3                                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Left-Associativity

Notice the tree shape: `(1 + 2) + 3`, not `1 + (2 + 3)`.

This is called **left-associative** - we group from the left.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      WHY LEFT-ASSOCIATIVITY MATTERS                          │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   For addition: both give the same answer                                   │
│     (1 + 2) + 3 = 6                                                         │
│     1 + (2 + 3) = 6                                                         │
│                                                                              │
│   For subtraction: DIFFERENT answers!                                       │
│     (8 - 5) - 2 = 1       ← Left-associative (correct!)                    │
│     8 - (5 - 2) = 5       ← Right-associative (wrong!)                     │
│                                                                              │
│   The loop pattern naturally gives left-associativity                       │
│   because we keep updating `left`.                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Adding Multiple Operators

Let's handle `+` and `-`:

```
// Grammar: expression → NUMBER (("+" | "-") NUMBER)*

function parseExpression():
    left = parseNumber()

    while see(PLUS) or see(MINUS):
        op = advance()              // Get the operator
        right = parseNumber()

        if op.type == PLUS:
            left = AddNode(left, right)
        else:
            left = SubNode(left, right)

    return left
```

---

## The Primary Rule

We should also handle identifiers like `x + y`:

```
// Grammar: primary → NUMBER | IDENTIFIER

function parsePrimary():
    if see(NUMBER):
        token = advance()
        return NumberNode(parseInt(token.lexeme))

    if see(IDENTIFIER):
        token = advance()
        return IdentifierNode(token.lexeme)

    error("Expected expression")
```

Now our expression uses primary:

```
// Grammar: expression → primary (("+" | "-") primary)*

function parseExpression():
    left = parsePrimary()

    while see(PLUS) or see(MINUS):
        op = advance()
        right = parsePrimary()

        if op.type == PLUS:
            left = AddNode(left, right)
        else:
            left = SubNode(left, right)

    return left
```

---

## Verify Your Implementation

### Test 1: Single number
```
Input:  "42"
Tokens: [NUMBER("42"), EOF]
AST:    NumberNode { value: 42 }
```

### Test 2: Two numbers
```
Input:  "1 + 2"
AST:    AddNode {
            left: NumberNode(1),
            right: NumberNode(2)
        }
```

### Test 3: Three numbers
```
Input:  "1 + 2 + 3"
AST:    AddNode {
            left: AddNode {
                left: NumberNode(1),
                right: NumberNode(2)
            },
            right: NumberNode(3)
        }
Tree:       +
           / \
          +   3
         / \
        1   2
```

### Test 4: Left-associativity check
```
Input:  "8 - 5 - 2"
AST:    SubNode {
            left: SubNode {
                left: NumberNode(8),
                right: NumberNode(5)
            },
            right: NumberNode(2)
        }

Evaluation: (8 - 5) - 2 = 3 - 2 = 1  ✓
NOT:        8 - (5 - 2) = 8 - 3 = 5  ✗
```

### Test 5: Mixed operators
```
Input:  "1 + 2 - 3"
AST:    SubNode {
            left: AddNode {
                left: NumberNode(1),
                right: NumberNode(2)
            },
            right: NumberNode(3)
        }

Evaluation: (1 + 2) - 3 = 3 - 3 = 0
```

---

## The Problem We Haven't Solved

What about `1 + 2 * 3`?

```
Input:  "1 + 2 * 3"

Our parser (left-to-right):
  1. left = 1
  2. see +, left = (1 + 2)
  3. see *, left = ((1 + 2) * 3)

Result: (1 + 2) * 3 = 9

But math says: 1 + (2 * 3) = 7  ← Different!
```

We're ignoring **operator precedence**. That's next.

---

## Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              SUMMARY                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Grammar pattern:                                                           │
│     rule → item (operator item)*                                            │
│                                                                              │
│   Code pattern:                                                              │
│     function parseRule():                                                    │
│         left = parseItem()                                                  │
│         while see(OPERATOR):                                                │
│             advance()                                                       │
│             right = parseItem()                                             │
│             left = BinaryNode(left, op, right)                              │
│         return left                                                          │
│                                                                              │
│   This naturally gives LEFT-ASSOCIATIVITY.                                  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What's Next

We need `*` to happen before `+`. How? With a two-level grammar.

Next: [Lesson 2.3: Precedence](../03-precedence/) →
