---
title: "2.1: Grammar Basics"
weight: 1
---

# Lesson 2.1: What is a Grammar?

Before we write any parser code, we need to understand **grammar** - the rules that describe valid programs.

---

## Goal

Understand why we need grammar rules, and learn the notation for writing them.

---

## The Problem: Flat Tokens Don't Show Structure

The lexer gives us a flat list of tokens:

```
Source: 1 + 2 * 3
Tokens: [NUMBER(1), PLUS, NUMBER(2), STAR, NUMBER(3)]
```

But this list doesn't tell us:
- Should `+` or `*` happen first?
- What belongs to what?
- How do we build a tree from this?

---

## The Solution: A Tree

We need to build a **tree** that shows structure:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      FLAT TOKENS VS TREE                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens (flat):           Tree (hierarchical):                             │
│                                                                              │
│   [1] [+] [2] [*] [3]              Add                                      │
│                                   /   \                                      │
│   No structure!                  1    Mul                                   │
│                                      /   \                                   │
│                                     2     3                                  │
│                                                                              │
│   The tree shows:                                                           │
│   - Mul is INSIDE Add (so * happens first)                                 │
│   - 2 and 3 belong to Mul                                                  │
│   - 1 and Mul belong to Add                                                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Key insight**: In a tree, deeper nodes are evaluated first.

---

## What is a Grammar?

A **grammar** is a set of rules that describe valid programs.

Think of it like a recipe:
- A recipe says "add flour, then eggs, then mix"
- A grammar says "an expression is a number, then a plus, then a number"

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           WHAT IS A GRAMMAR?                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   A grammar is a set of RULES that describe:                                │
│                                                                              │
│   1. What pieces your language has                                          │
│   2. How those pieces can be combined                                       │
│   3. What order things must appear in                                       │
│                                                                              │
│   Example rule in English:                                                  │
│   "An expression is a number, then a plus, then a number"                   │
│                                                                              │
│   Same rule in grammar notation:                                            │
│   expression → NUMBER "+" NUMBER                                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Your First Grammar Rule

Let's write a rule for `1 + 2`:

```
expression → NUMBER "+" NUMBER
```

Breaking this down:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        ANATOMY OF A GRAMMAR RULE                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   expression → NUMBER "+" NUMBER                                            │
│   ──────────   ────────────────────                                          │
│       │                │                                                     │
│       │                └─── Right side: what it's made of                   │
│       │                                                                      │
│       └─── Left side: the thing we're defining                              │
│                                                                              │
│                                                                              │
│   The arrow → means "is made of"                                            │
│                                                                              │
│   NUMBER (all caps) = a token from the lexer                                │
│   "+"               = the literal plus character                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Grammar Notation

Here are the symbols we'll use:

```
┌────────────┬─────────────────────────────────────────────────────────────────┐
│  Symbol    │  Meaning                                                        │
├────────────┼─────────────────────────────────────────────────────────────────┤
│  →         │  "is made of"                                                   │
│            │  expression → NUMBER means "an expression is made of a number" │
├────────────┼─────────────────────────────────────────────────────────────────┤
│  |         │  "or" (alternatives)                                           │
│            │  primary → NUMBER | IDENTIFIER                                 │
│            │  means "a primary is either a number OR an identifier"         │
├────────────┼─────────────────────────────────────────────────────────────────┤
│  *         │  "zero or more"                                                │
│            │  statement* means "zero or more statements"                    │
├────────────┼─────────────────────────────────────────────────────────────────┤
│  ?         │  "optional" (zero or one)                                      │
│            │  parameters? means "parameters are optional"                   │
├────────────┼─────────────────────────────────────────────────────────────────┤
│  ( )       │  Grouping                                                      │
│            │  ("+" NUMBER)* means "the whole group repeats"                 │
├────────────┼─────────────────────────────────────────────────────────────────┤
│  "..."     │  Literal text                                                  │
│            │  "fn" means the literal characters f and n                     │
├────────────┼─────────────────────────────────────────────────────────────────┤
│  CAPS      │  Token from lexer                                              │
│            │  NUMBER, IDENTIFIER, PLUS                                      │
├────────────┼─────────────────────────────────────────────────────────────────┤
│  lowercase │  Another grammar rule                                          │
│            │  expression, term, primary                                     │
└────────────┴─────────────────────────────────────────────────────────────────┘
```

---

## How Parsing Works

The parser reads tokens left-to-right, following the grammar rules:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    PARSING "1 + 2" STEP BY STEP                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Rule: expression → NUMBER "+" NUMBER                                      │
│   Tokens: [NUMBER(1)] [PLUS] [NUMBER(2)]                                    │
│                 ▲                                                            │
│                 cursor                                                       │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│   Step 1: Expect NUMBER                                                     │
│           Current token: NUMBER(1) ✓                                        │
│           Consume it, save value 1                                          │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│   Tokens: [NUMBER(1)] [PLUS] [NUMBER(2)]                                    │
│                         ▲                                                    │
│                         cursor moved                                         │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│   Step 2: Expect "+"                                                        │
│           Current token: PLUS ✓                                             │
│           Consume it                                                        │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│   Tokens: [NUMBER(1)] [PLUS] [NUMBER(2)]                                    │
│                                   ▲                                          │
│                                   cursor moved                               │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│   Step 3: Expect NUMBER                                                     │
│           Current token: NUMBER(2) ✓                                        │
│           Consume it, save value 2                                          │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│   All parts matched! Build the tree:                                        │
│                                                                              │
│               Add                                                            │
│              /   \                                                           │
│             1     2                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Parser State

The parser keeps track of:

```
Parser {
    tokens: Token[]        // All tokens from lexer
    pos: integer           // Current position (starts at 0)
}
```

And uses these helper functions:

```
function peek():
    return tokens[pos]     // Look at current token

function advance():
    token = tokens[pos]
    pos = pos + 1
    return token           // Return current, move to next

function see(type):
    return peek().type == type    // Check token type

function expect(type):
    if peek().type != type:
        error("Expected " + type)
    return advance()
```

---

## From Grammar to Code

Each grammar rule becomes a function:

```
// Grammar: expression → NUMBER "+" NUMBER

function parseExpression():
    left = expect(NUMBER)            // First NUMBER
    expect(PLUS)                     // "+"
    right = expect(NUMBER)           // Second NUMBER
    return AddNode(left, right)
```

This is the key insight: **grammar rules map directly to parse functions**.

---

## Parsing Just a Number

Before we parse `1 + 2`, let's handle just `42`:

```
// Grammar: primary → NUMBER

function parsePrimary():
    if see(NUMBER):
        token = advance()
        value = parseInt(token.lexeme)
        return NumberNode(value)

    error("Expected expression")
```

---

## Verify Your Implementation

### Test 1: Single number
```
Input:  "42"
Tokens: [NUMBER("42"), EOF]
AST:    NumberNode { value: 42 }
```

### Test 2: Simple addition
```
Input:  "1 + 2"
Tokens: [NUMBER(1), PLUS, NUMBER(2), EOF]
AST:    AddNode {
            left: NumberNode(1),
            right: NumberNode(2)
        }
```

### Test 3: Error case
```
Input:  "+"
Tokens: [PLUS, EOF]
Result: Error - Expected NUMBER, got PLUS
```

---

## What We Can't Parse Yet

Our simple rule `expression → NUMBER "+" NUMBER` only handles exactly two numbers:

```
✓  1 + 2       Two numbers - works!
✗  1 + 2 + 3   Three numbers - fails!
✗  42          Just one number - fails!
✗  1 * 2       Different operator - fails!
```

We need more powerful rules. That's next.

---

## Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              SUMMARY                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. Tokens are flat, but code has tree structure                           │
│                                                                              │
│   2. A grammar is rules describing valid programs                           │
│                                                                              │
│   3. Grammar notation:                                                       │
│      →    "is made of"                                                      │
│      |    "or"                                                              │
│      *    "zero or more"                                                    │
│      ?    "optional"                                                        │
│                                                                              │
│   4. Each grammar rule becomes one parse function                           │
│                                                                              │
│   5. Parser state: tokens[], pos, peek(), advance()                         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What's Next

Our rule only handles `1 + 2`. How do we handle `1 + 2 + 3`? We need repetition.

Next: [Lesson 2.2: Repetition](../02-repetition/) →
