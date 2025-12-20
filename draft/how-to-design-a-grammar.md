---
title: "How to Design a Grammar for Your Programming Language"
date: 2025-12-20
---

# How to Design a Grammar for Your Programming Language

*From tokens to trees: the missing guide*

---

## Introduction

You've built a lexer. It takes source code and spits out tokens:

```
Source: 1 + 2 * 3
Tokens: [NUMBER(1), PLUS, NUMBER(2), STAR, NUMBER(3)]
```

Now what?

If you try to process these tokens one by one, you'll quickly run into problems. How do you know that `*` should happen before `+`? How do you handle parentheses? How do you parse `x = 1 + 2` where the `=` needs to wrap the whole right side?

The answer is a **grammar** - a set of rules that describe what valid programs look like. This article will teach you how to design one from scratch.

---

## What is a Grammar?

A grammar is a recipe for building valid programs. Just like a cooking recipe says "add flour, then eggs, then mix", a grammar says "a function is: the word 'fn', then a name, then parameters, then a body".

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            WHAT IS A GRAMMAR?                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   A grammar is a set of RULES that describe:                                │
│                                                                              │
│   1. What pieces your language has (expressions, statements, functions)     │
│   2. How those pieces can be combined                                       │
│   3. What order things must appear in                                       │
│                                                                              │
│   Example rule:                                                             │
│                                                                              │
│       function → "fn" NAME "(" params ")" block                             │
│                                                                              │
│   This says: a function is the word "fn", followed by a name,               │
│   followed by params in parentheses, followed by a block.                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## The Problem: Why Tokens Aren't Enough

### Flat Tokens Don't Show Structure

When you look at tokens, they're just a flat list:

```
Source: const x = 1 + 2;

Tokens:
  [0] CONST
  [1] IDENTIFIER "x"
  [2] EQUAL
  [3] NUMBER 1
  [4] PLUS
  [5] NUMBER 2
  [6] SEMICOLON
```

But this list doesn't tell you:
- What belongs to what?
- Does `=` apply to just `1` or to `1 + 2`?
- Is `+` the "main" operation or is `=`?

### The Solution: Build a Tree

We need a **tree** that shows structure:

```
Token List (flat):               Tree (hierarchical):

[CONST][x][=][1][+][2][;]              VarDecl
                                      /   |   \
                                   "x"   =    Add
                                             /   \
                                            1     2
```

Now we can see:
- `x` is the variable name
- The value being assigned is `1 + 2` (the whole Add node)
- `1` and `2` are children of `Add`

### The Parser's Job

The parser reads tokens left-to-right and builds this tree. But it needs to know the rules - that's what the grammar provides.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           THE PARSER'S JOB                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Input:   Flat list of tokens                                              │
│   Output:  Hierarchical tree (AST)                                          │
│   Guide:   Grammar rules                                                    │
│                                                                              │
│   Tokens ──────────► Parser ──────────► Tree                                │
│                         ▲                                                    │
│                         │                                                    │
│                      Grammar                                                 │
│                      (rules)                                                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Your First Grammar Rule

Let's start with the simplest possible expression: `1 + 2`.

### The Rule in English

"An expression is a number, then a plus sign, then a number."

### The Rule in Grammar Notation

```
expression → NUMBER "+" NUMBER
```

Let's break this down:

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
│   The arrow → means "is defined as" or "is made of"                         │
│                                                                              │
│   NUMBER (all caps) = a token from the lexer                                │
│   "+"               = the literal plus character                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### How Parsing Works with This Rule

```
Input: 1 + 2
Tokens: [NUMBER(1), PLUS, NUMBER(2)]

Parser (following rule: expression → NUMBER "+" NUMBER):

Step 1: See NUMBER(1)? Yes! ✓ Consume it.
        Remaining: [PLUS, NUMBER(2)]

Step 2: See "+"? Yes! ✓ Consume it.
        Remaining: [NUMBER(2)]

Step 3: See NUMBER(2)? Yes! ✓ Consume it.
        Remaining: []

Step 4: Build the tree:
                Add
               /   \
              1     2

Done!
```

### Visual Trace

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    PARSING "1 + 2" STEP BY STEP                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens:  [NUMBER(1)] [PLUS] [NUMBER(2)]                                   │
│                 ▲                                                            │
│                 │                                                            │
│            ─────┴───── cursor starts here                                   │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│   Rule: expression → NUMBER "+" NUMBER                                      │
│                       ^^^^^                                                  │
│                       expect NUMBER                                          │
│                                                                              │
│   Current token: NUMBER(1) ✓ matches!                                       │
│   Action: consume, save value 1                                             │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens:  [NUMBER(1)] [PLUS] [NUMBER(2)]                                   │
│                           ▲                                                  │
│                           │                                                  │
│                ───────────┴───── cursor moved                               │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│   Rule: expression → NUMBER "+" NUMBER                                      │
│                              ^^^                                             │
│                              expect "+"                                      │
│                                                                              │
│   Current token: PLUS ✓ matches!                                            │
│   Action: consume                                                           │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens:  [NUMBER(1)] [PLUS] [NUMBER(2)]                                   │
│                                    ▲                                         │
│                                    │                                         │
│                       ─────────────┴───── cursor moved                      │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│   Rule: expression → NUMBER "+" NUMBER                                      │
│                                  ^^^^^^                                      │
│                                  expect NUMBER                               │
│                                                                              │
│   Current token: NUMBER(2) ✓ matches!                                       │
│   Action: consume, save value 2                                             │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│   All parts matched! Build node:                                            │
│                                                                              │
│               Add                                                            │
│              /   \                                                           │
│             1     2                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Problem: What About `1 + 2 + 3`?

Our current rule only handles exactly TWO numbers:

```
expression → NUMBER "+" NUMBER
```

It can parse:
- ✓ `1 + 2`
- ✗ `1 + 2 + 3`    (three numbers!)
- ✗ `1 + 2 + 3 + 4` (four numbers!)
- ✗ `42`           (one number!)

We need a way to say "one or more" or "zero or more".

---

## Adding Repetition

### The `*` Operator

In grammar notation, `*` means "zero or more":

```
expression → NUMBER ("+" NUMBER)*
```

This reads as: "A number, followed by zero or more occurrences of (plus, number)."

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

### How It Parses

```
expression → NUMBER ("+" NUMBER)*

Parsing "1 + 2 + 3":

Step 1: Parse NUMBER → 1
        left = 1

Step 2: See "+"? Yes! Enter the (*) loop.
        Parse NUMBER → 2
        left = Add(1, 2)

Step 3: See "+"? Yes! Still in loop.
        Parse NUMBER → 3
        left = Add(Add(1, 2), 3)

Step 4: See "+"? No. Exit loop.
        Return left

Result:
        Add
       /   \
     Add    3
    /   \
   1     2
```

### The Pattern: Use a Loop

In code, the `*` becomes a while loop:

```
fn parseExpression():
    left = parseNumber()           // First NUMBER

    while see(PLUS):               // ("+" NUMBER)*
        consume(PLUS)
        right = parseNumber()
        left = AddNode(left, right)

    return left
```

### Step-by-Step Trace of `1 + 2 + 3`

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    PARSING "1 + 2 + 3" WITH REPETITION                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [1] [+] [2] [+] [3]                                               │
│            ▲                                                                 │
│                                                                              │
│   Step 1: Parse first NUMBER                                                │
│           left = 1                                                          │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [1] [+] [2] [+] [3]                                               │
│               ▲                                                              │
│                                                                              │
│   Step 2: See "+"? YES → enter loop                                         │
│           consume "+"                                                        │
│           parse NUMBER → 2                                                  │
│           left = Add(1, 2)                                                  │
│                                                                              │
│           Current tree:                                                      │
│                  Add                                                         │
│                 /   \                                                        │
│                1     2                                                       │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [1] [+] [2] [+] [3]                                               │
│                       ▲                                                      │
│                                                                              │
│   Step 3: See "+"? YES → continue loop                                      │
│           consume "+"                                                        │
│           parse NUMBER → 3                                                  │
│           left = Add(Add(1, 2), 3)                                          │
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
│   Tokens: [1] [+] [2] [+] [3]                                               │
│                            ▲                                                 │
│                             (end of tokens)                                  │
│                                                                              │
│   Step 4: See "+"? NO → exit loop                                           │
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
│           Left-associative! ✓                                               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Why Left-Associative?

Notice the tree shape: `(1 + 2) + 3`, not `1 + (2 + 3)`.

This is called **left-associative** - we group from the left. This is what we want for subtraction:

```
8 - 5 - 2

Left-associative:  (8 - 5) - 2 = 3 - 2 = 1  ✓ Correct!
Right-associative: 8 - (5 - 2) = 8 - 3 = 5  ✗ Wrong!
```

The loop pattern naturally produces left-associativity because we keep updating `left`.

---

## The Precedence Problem

Let's add multiplication to our grammar:

```
expression → NUMBER (("+" | "*") NUMBER)*
```

The `|` means "or". So now we can have `+` or `*` between numbers.

### What Goes Wrong?

```
Input: 1 + 2 * 3

Our grammar parses left-to-right:
1. left = 1
2. See "+", parse 2 → left = Add(1, 2)
3. See "*", parse 3 → left = Mul(Add(1, 2), 3)

Result tree:
        Mul
       /   \
     Add    3
    /   \
   1     2

This means: (1 + 2) * 3 = 9
But math says: 1 + (2 * 3) = 7  ← Different answer!
```

### Visualizing the Problem

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         THE PRECEDENCE PROBLEM                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Input: 1 + 2 * 3                                                          │
│                                                                              │
│   WRONG (our current grammar):         CORRECT (what math expects):         │
│                                                                              │
│           Mul                                   Add                          │
│          /   \                                 /   \                         │
│        Add    3                               1    Mul                       │
│       /   \                                       /   \                      │
│      1     2                                     2     3                     │
│                                                                              │
│   Evaluation:                           Evaluation:                          │
│   (1 + 2) * 3                           1 + (2 * 3)                          │
│   = 3 * 3                               = 1 + 6                              │
│   = 9                                   = 7                                  │
│                                                                              │
│                                                                              │
│   The problem: * should bind TIGHTER than +                                 │
│   But our grammar treats them the same!                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### The Key Insight: Nesting = Precedence

Here's the crucial insight:

**In a tree, deeper nodes are evaluated first.**

```
        Add              ← evaluated LAST (outer)
       /   \
      1    Mul           ← evaluated FIRST (inner)
          /   \
         2     3

Evaluation order:
1. First: 2 * 3 = 6 (inner node)
2. Then:  1 + 6 = 7 (outer node)
```

So to make `*` happen before `+`, we need `*` nodes to be **nested inside** `+` nodes.

---

## Solving Precedence with Nesting

The solution: **split into multiple rules**, one for each precedence level.

### The Two-Level Grammar

```
expression → term (("+" | "-") term)*
term       → NUMBER (("*" | "/") NUMBER)*
```

Wait, what? Let's break this down carefully.

### How to Read These Rules

```
expression → term (("+" | "-") term)*
```

This says:
- First, get a `term` (whatever that is - we'll define it below)
- Then, zero or more times: get a `+` or `-`, then another `term`

```
term → NUMBER (("*" | "/") NUMBER)*
```

This says:
- First, get a `NUMBER`
- Then, zero or more times: get a `*` or `/`, then another `NUMBER`

**Key insight: `expression` doesn't see numbers directly. It sees `term`s.**

### Think of It Like Boxes

```
expression deals with BOXES connected by + or -:

┌─────┐     ┌─────┐     ┌─────┐
│term │  +  │term │  +  │term │  ...
└─────┘     └─────┘     └─────┘

Each box (term) can contain multiplication INSIDE:

┌─────────────────┐
│ 2 * 3 * 4       │  ← this whole thing is ONE term
└─────────────────┘

So "1 + 2 * 3 + 4" becomes:

┌─────┐     ┌─────────┐     ┌─────┐
│  1  │  +  │  2 * 3  │  +  │  4  │
└─────┘     └─────────┘     └─────┘
   │             │             │
  term         term          term

expression only sees 3 terms connected by +
The * is HIDDEN inside the middle term!
```

### Why This Gives Correct Precedence

Think of it like school math order of operations:

1. **First** do multiplication/division (that's what `term` does)
2. **Then** do addition/subtraction (that's what `expression` does)

The grammar enforces this by making `expression` call `term` first. By the time `expression` gets to do its work, all the `*` and `/` are already done.

### Simple Summary

- An **expression** is terms combined with `+` or `-`
- A **term** is numbers combined with `*` or `/`

### Why This Works: Step by Step

Let's trace `1 + 2 * 3` in detail:

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

### Compare: One Rule vs Two Rules

```
ONE RULE (wrong):                TWO RULES (correct):
─────────────────               ──────────────────────

expression →                    expression →
  NUMBER ((+|*) NUMBER)*          term ((+|-) term)*

                                term →
                                  NUMBER ((*|/) NUMBER)*


Parsing "1 + 2 * 3":            Parsing "1 + 2 * 3":
─────────────────               ──────────────────────

1. left = 1                     1. expression calls term
2. see +                           term returns 1
3. left = 1 + 2                 2. expression sees +
4. see *                        3. expression calls term
5. left = (1+2) * 3                term gets 2
                                   term sees * ← HANDLES IT!
   = 9  WRONG!                     term gets 3
                                   term returns (2*3)
                                4. expression builds 1 + (2*3)

                                   = 7  CORRECT!
```

### The Golden Rule

**The function that gets called FIRST handles the operators that should happen FIRST (higher precedence).**

```
expression calls term
term handles * and /
Therefore * and / happen before + and -
```

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                     HOW NESTING CREATES PRECEDENCE                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Grammar:                                                                   │
│     expression → term (("+" | "-") term)*    ← LOW precedence (outer)       │
│     term       → NUMBER (("*" | "/") NUMBER)*  ← HIGH precedence (inner)    │
│                                                                              │
│   Rule of thumb:                                                             │
│     - Rules that call OTHER rules have LOWER precedence                     │
│     - Rules that are CALLED have HIGHER precedence                          │
│     - Called first = evaluated first = higher precedence                    │
│                                                                              │
│   Call chain:                                                                │
│     expression calls term                                                    │
│     term calls (numbers directly)                                           │
│                                                                              │
│   So: term is "inside" expression                                           │
│   So: * is "inside" +                                                       │
│   So: * happens first!                                                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Detailed Trace of `1 + 2 * 3`

Let's trace through exactly how this works:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    PARSING "1 + 2 * 3" WITH PRECEDENCE                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Grammar:                                                                   │
│     expression → term (("+" | "-") term)*                                   │
│     term       → NUMBER (("*" | "/") NUMBER)*                               │
│                                                                              │
│   Tokens: [1] [+] [2] [*] [3]                                               │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│   expression() called:                                                       │
│                                                                              │
│   Step 1: Call term() for left side                                         │
│           │                                                                  │
│           ▼                                                                  │
│       term():                                                                │
│           Parse NUMBER → 1                                                  │
│           See "*" or "/"? No (see "+")                                      │
│           Return 1                                                          │
│           │                                                                  │
│           ▼                                                                  │
│       left = 1                                                              │
│                                                                              │
│   Tokens: [1] [+] [2] [*] [3]                                               │
│               ▲                                                              │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│   expression() continues:                                                    │
│                                                                              │
│   Step 2: See "+" or "-"? Yes, see "+"                                      │
│           Consume "+"                                                        │
│           Call term() for right side                                        │
│           │                                                                  │
│           ▼                                                                  │
│       term():                                                                │
│           Parse NUMBER → 2                                                  │
│           See "*" or "/"? YES! See "*"                                      │
│           Consume "*"                                                        │
│           Parse NUMBER → 3                                                  │
│           left = Mul(2, 3)                                                  │
│           See "*" or "/"? No                                                │
│           Return Mul(2, 3)          ← MULTIPLICATION HANDLED INSIDE TERM!  │
│           │                                                                  │
│           ▼                                                                  │
│       right = Mul(2, 3)                                                     │
│       left = Add(1, Mul(2, 3))                                              │
│                                                                              │
│   Tokens: [1] [+] [2] [*] [3]                                               │
│                            ▲                                                 │
│                             (end)                                            │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│   expression() continues:                                                    │
│                                                                              │
│   Step 3: See "+" or "-"? No (end of tokens)                                │
│           Return left                                                        │
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

### The Call Stack IS the Tree

Here's the beautiful insight: **the parser's call stack mirrors the tree structure**.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                     CALL STACK = TREE STRUCTURE                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   When parsing "1 + 2 * 3":                                                 │
│                                                                              │
│   Call Stack (grows down):          Tree (grows down):                      │
│   ────────────────────────          ────────────────────                    │
│                                                                              │
│   expression()                      Add (root)                              │
│       │                            /   \                                     │
│       ├── term() → 1              1     Mul                                 │
│       │                                /   \                                 │
│       └── term() ──────────────────►  2     3                               │
│               │                                                              │
│               ├── sees 2                                                     │
│               ├── sees *                                                     │
│               └── sees 3                                                     │
│                   builds Mul(2,3)                                           │
│                                                                              │
│   The nesting in the call stack                                             │
│   becomes nesting in the tree!                                              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Adding Unary Operators

What about `-5` or `-x`? These are **unary operators** - they take one operand.

### The Grammar Rule

```
expression → term (("+" | "-") term)*
term       → unary (("*" | "/") unary)*
unary      → "-" unary | NUMBER
```

The new `unary` rule says:
- A unary is either: minus followed by another unary, OR just a number
- The recursive `"-" unary` allows `--5` (double negative)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         UNARY OPERATOR RULE                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   unary → "-" unary | NUMBER                                                │
│                                                                              │
│   The "|" means OR. So a unary is either:                                   │
│     1. A minus sign followed by another unary, OR                           │
│     2. Just a number                                                        │
│                                                                              │
│   Examples:                                                                  │
│                                                                              │
│     "5"   →  NUMBER                                                         │
│                 └─ unary (the number case)                                  │
│                                                                              │
│     "-5"  →  "-" unary                                                      │
│                   └─ NUMBER                                                 │
│                        └─ unary (the number case)                           │
│                                                                              │
│     "--5" →  "-" unary                                                      │
│                   └─ "-" unary                                              │
│                          └─ NUMBER                                          │
│                               └─ unary (the number case)                    │
│                                                                              │
│   The recursion allows any number of minus signs!                           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Why Unary is Between Term and Number

Precedence order (highest to lowest):
1. Unary minus: `-x` (happens first)
2. Multiplication/Division: `*` `/`
3. Addition/Subtraction: `+` `-`

So the call chain is:
```
expression → term → unary → number

-2 * 3  parses as  (-2) * 3   ✓
```

If unary were at expression level:
```
-2 * 3  would parse as  -(2 * 3)  ✗ Wrong!
```

### Trace of `-1 + 2`

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        PARSING "-1 + 2"                                      │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Grammar:                                                                   │
│     expression → term (("+" | "-") term)*                                   │
│     term       → unary (("*" | "/") unary)*                                 │
│     unary      → "-" unary | NUMBER                                         │
│                                                                              │
│   Tokens: [MINUS] [1] [PLUS] [2]                                            │
│                                                                              │
│   expression():                                                              │
│       call term():                                                           │
│           call unary():                                                      │
│               see MINUS → consume it                                        │
│               call unary() recursively:                                      │
│                   see NUMBER(1) → return 1                                  │
│               return Negate(1)                                              │
│           see "*" or "/"? No                                                │
│           return Negate(1)                                                  │
│       left = Negate(1)                                                      │
│                                                                              │
│       see "+"? Yes → consume it                                             │
│       call term():                                                           │
│           call unary():                                                      │
│               see NUMBER(2) → return 2                                      │
│           return 2                                                          │
│       right = 2                                                             │
│       left = Add(Negate(1), 2)                                              │
│                                                                              │
│       see "+"? No                                                           │
│       return Add(Negate(1), 2)                                              │
│                                                                              │
│   Tree:                                                                      │
│              Add                                                             │
│             /   \                                                            │
│         Negate   2                                                           │
│            |                                                                 │
│            1                                                                 │
│                                                                              │
│   Evaluation: (-1) + 2 = 1  ✓                                               │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Adding Parentheses

Parentheses let users override precedence: `(1 + 2) * 3`.

### The Grammar Rule

```
expression → term (("+" | "-") term)*
term       → unary (("*" | "/") unary)*
unary      → "-" unary | primary
primary    → NUMBER | "(" expression ")"
```

We renamed "NUMBER" to "primary" and added the parenthesis option.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         PARENTHESES RULE                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   primary → NUMBER | "(" expression ")"                                     │
│                                                                              │
│   A primary is either:                                                       │
│     1. Just a number, OR                                                    │
│     2. An open paren, an EXPRESSION, and a close paren                      │
│                                                                              │
│   The magic: inside the parens, we RESTART at "expression"!                 │
│   This is RECURSION.                                                         │
│                                                                              │
│   Call chain for "(1 + 2)":                                                 │
│                                                                              │
│     primary() sees "("                                                       │
│         │                                                                    │
│         └──► calls expression()  ← RECURSION!                               │
│                  │                                                           │
│                  └──► parses "1 + 2"                                        │
│                       returns Add(1, 2)                                     │
│         │                                                                    │
│         └──► expects ")"                                                    │
│              returns Add(1, 2)                                              │
│                                                                              │
│   The parentheses DISAPPEAR from the AST.                                   │
│   Their job was to guide the parser - now structure is in the tree.        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Trace of `(1 + 2) * 3`

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      PARSING "(1 + 2) * 3"                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [LPAREN] [1] [PLUS] [2] [RPAREN] [STAR] [3]                       │
│                                                                              │
│   expression():                                                              │
│       call term():                                                           │
│           call unary():                                                      │
│               call primary():                                                │
│                   see "(" → consume it                                      │
│   ┌───────────────────────────────────────────────────────────────┐         │
│   │   call expression() RECURSIVELY:                               │         │
│   │       call term():                                             │         │
│   │           call unary():                                        │         │
│   │               call primary():                                  │         │
│   │                   see NUMBER(1) → return 1                    │         │
│   │               return 1                                        │         │
│   │           return 1                                            │         │
│   │       left = 1                                                │         │
│   │       see "+"? Yes → consume                                  │         │
│   │       call term():                                             │         │
│   │           call unary():                                        │         │
│   │               call primary():                                  │         │
│   │                   see NUMBER(2) → return 2                    │         │
│   │       right = 2                                               │         │
│   │       left = Add(1, 2)                                        │         │
│   │       see "+"? No (see ")")                                   │         │
│   │       return Add(1, 2)                                        │         │
│   └───────────────────────────────────────────────────────────────┘         │
│                   expect ")" → consume it                                   │
│                   return Add(1, 2)                                          │
│               return Add(1, 2)                                              │
│           return Add(1, 2)                                                  │
│       left = Add(1, 2)                                                      │
│                                                                              │
│       see "*"? Yes → consume                                                │
│       call unary():                                                          │
│           call primary():                                                    │
│               see NUMBER(3) → return 3                                      │
│       right = 3                                                             │
│       left = Mul(Add(1, 2), 3)                                              │
│                                                                              │
│       see "*"? No                                                           │
│       return Mul(Add(1, 2), 3)                                              │
│                                                                              │
│   see "+"? No                                                               │
│   return Mul(Add(1, 2), 3)                                                  │
│                                                                              │
│   Tree:                                                                      │
│              Mul                                                             │
│             /   \                                                            │
│           Add    3                                                           │
│          /   \                                                               │
│         1     2                                                              │
│                                                                              │
│   Evaluation: (1 + 2) * 3 = 3 * 3 = 9  ✓                                    │
│                                                                              │
│   Notice: The parentheses are GONE from the tree.                           │
│   Their effect is captured in the STRUCTURE of the tree.                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## The Complete Expression Grammar

Here's our full expression grammar with 4 rules:

```
expression → term (("+" | "-") term)*
term       → unary (("*" | "/") unary)*
unary      → "-" unary | primary
primary    → NUMBER | IDENTIFIER | "(" expression ")"
```

(We added IDENTIFIER so variables like `x` work too.)

### Visual Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    THE COMPLETE EXPRESSION GRAMMAR                           │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   expression → term (("+" | "-") term)*       Precedence: LOWEST (3)        │
│       │                                                                      │
│       │ calls                                                                │
│       ▼                                                                      │
│   term → unary (("*" | "/") unary)*           Precedence: MEDIUM (2)        │
│       │                                                                      │
│       │ calls                                                                │
│       ▼                                                                      │
│   unary → "-" unary | primary                 Precedence: HIGH (1)          │
│       │                                                                      │
│       │ calls                                                                │
│       ▼                                                                      │
│   primary → NUMBER | IDENTIFIER | "(" expression ")"   Precedence: HIGHEST │
│                                        │                                     │
│                                        │ calls (recursion!)                  │
│                                        └────────────────────────────────────┐
│                                                                              │
│                                                                              │
│   What can it parse?                                                         │
│   ──────────────────                                                         │
│     42                              ✓ number                                │
│     x                               ✓ identifier                            │
│     1 + 2                           ✓ addition                              │
│     1 + 2 * 3                       ✓ precedence: 1 + (2 * 3)              │
│     -5                              ✓ unary minus                           │
│     --x                             ✓ double negation                       │
│     (1 + 2) * 3                     ✓ parentheses override                  │
│     -x * (y + z)                    ✓ complex expression                    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### How Each Rule Maps to Precedence

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    PRECEDENCE LEVELS                                       │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│   Level   Rule          Operators    Evaluated                             │
│   ─────   ────          ─────────    ─────────                             │
│   3       expression    + -          LAST (outermost in tree)             │
│   2       term          * /          MIDDLE                                │
│   1       unary         - (prefix)   FIRST                                 │
│   0       primary       literals     FIRST (innermost in tree)            │
│                                                                            │
│   Lower level number = called first = evaluated first = higher precedence │
│                                                                            │
│   Example: -2 * 3 + 4                                                      │
│                                                                            │
│   Tree:           Add              (level 3, evaluated last)               │
│                  /   \                                                      │
│                Mul    4            (level 2)                               │
│               /   \                                                        │
│           Negate   3               (level 1, evaluated first)              │
│              |                                                             │
│              2                     (level 0)                               │
│                                                                            │
│   Evaluation order: 2 → -2 → (-2)*3=-6 → -6+4=-2                          │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## From Expressions to Statements

Expressions produce values. But programs also need **statements** - things that DO something.

### What's a Statement?

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    EXPRESSIONS VS STATEMENTS                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   EXPRESSIONS produce a value:                                              │
│     42              → produces 42                                           │
│     x + y           → produces the sum                                      │
│     foo()           → produces return value                                 │
│                                                                              │
│   STATEMENTS perform an action:                                             │
│     const x = 5;    → creates a variable (no value produced)               │
│     return 42;      → exits the function (no value produced)               │
│     { ... }         → groups statements (no value produced)                │
│                                                                              │
│   Key difference: statements usually end with semicolons.                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Statement Grammar Rules

```
statement   → var_decl | return_stmt
var_decl    → "const" IDENTIFIER "=" expression ";"
return_stmt → "return" expression ";"
```

### Trace of `const x = 1 + 2;`

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    PARSING "const x = 1 + 2;"                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [CONST] [x] [=] [1] [+] [2] [;]                                   │
│                                                                              │
│   statement():                                                               │
│       see "const"? Yes!                                                      │
│       call var_decl():                                                       │
│           expect "const" → consume                                          │
│           expect IDENTIFIER → consume, name = "x"                           │
│           expect "=" → consume                                              │
│           call expression():                                                 │
│               ... parses "1 + 2" ...                                        │
│               returns Add(1, 2)                                             │
│           value = Add(1, 2)                                                 │
│           expect ";" → consume                                              │
│           return VarDecl { name: "x", value: Add(1, 2) }                   │
│                                                                              │
│   Tree:                                                                      │
│           VarDecl                                                            │
│          /       \                                                           │
│        "x"       Add                                                         │
│                 /   \                                                        │
│                1     2                                                       │
│                                                                              │
│   The key: var_decl CALLS expression for the value!                        │
│   This is how the grammar COMPOSES.                                         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Trace of `return x + 1;`

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    PARSING "return x + 1;"                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [RETURN] [x] [+] [1] [;]                                          │
│                                                                              │
│   statement():                                                               │
│       see "const"? No                                                        │
│       see "return"? Yes!                                                     │
│       call return_stmt():                                                    │
│           expect "return" → consume                                         │
│           call expression():                                                 │
│               call term():                                                   │
│                   call unary():                                              │
│                       call primary():                                        │
│                           see IDENTIFIER "x" → return Ident("x")           │
│               left = Ident("x")                                             │
│               see "+"? Yes → consume                                        │
│               call term():                                                   │
│                   returns 1                                                 │
│               left = Add(Ident("x"), 1)                                     │
│               return Add(Ident("x"), 1)                                     │
│           value = Add(Ident("x"), 1)                                        │
│           expect ";" → consume                                              │
│           return ReturnStmt { value: Add(Ident("x"), 1) }                  │
│                                                                              │
│   Tree:                                                                      │
│           ReturnStmt                                                         │
│               |                                                              │
│              Add                                                             │
│             /   \                                                            │
│         Ident   1                                                           │
│           |                                                                  │
│          "x"                                                                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Adding Blocks

A **block** is a sequence of statements wrapped in braces.

### The Grammar Rule

```
block → "{" statement* "}"
```

This says: an open brace, zero or more statements, and a close brace.

### Trace of `{ const x = 5; return x; }`

```
┌──────────────────────────────────────────────────────────────────────────────┐
│              PARSING "{ const x = 5; return x; }"                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [{] [CONST] [x] [=] [5] [;] [RETURN] [x] [;] [}]                  │
│                                                                              │
│   block():                                                                   │
│       expect "{" → consume                                                  │
│       statements = []                                                        │
│                                                                              │
│       while not see "}":                                                    │
│           call statement():                                                  │
│               ... parses "const x = 5;" ...                                 │
│               returns VarDecl { name: "x", value: 5 }                       │
│           append to statements                                              │
│                                                                              │
│           call statement():                                                  │
│               ... parses "return x;" ...                                    │
│               returns ReturnStmt { value: Ident("x") }                      │
│           append to statements                                              │
│                                                                              │
│       expect "}" → consume                                                  │
│       return Block { statements: [VarDecl, ReturnStmt] }                    │
│                                                                              │
│   Tree:                                                                      │
│           Block                                                              │
│          /     \                                                             │
│     VarDecl   ReturnStmt                                                    │
│     /    \         |                                                         │
│   "x"     5    Ident("x")                                                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Adding Functions

Now let's add function declarations.

### The Grammar Rules

```
function → "fn" IDENTIFIER "(" parameters? ")" block
parameters → parameter ("," parameter)*
parameter → IDENTIFIER ":" type
type → "i32" | "bool" | "void"
```

Let's break these down:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                       FUNCTION GRAMMAR RULES                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   function → "fn" IDENTIFIER "(" parameters? ")" block                      │
│                                                                              │
│   This says: a function is:                                                 │
│     1. The keyword "fn"                                                     │
│     2. An identifier (the function name)                                    │
│     3. Open paren                                                           │
│     4. OPTIONAL parameters (that's what ? means)                            │
│     5. Close paren                                                          │
│     6. A block                                                              │
│                                                                              │
│   ────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   parameters → parameter ("," parameter)*                                   │
│                                                                              │
│   This says: parameters are:                                                │
│     1. One parameter                                                        │
│     2. Followed by zero or more (comma, parameter) pairs                   │
│                                                                              │
│   Examples:                                                                  │
│     "a: i32"           → one parameter                                      │
│     "a: i32, b: i32"   → two parameters                                    │
│     ""                 → no parameters (handled by the ? in function)       │
│                                                                              │
│   ────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   parameter → IDENTIFIER ":" type                                           │
│                                                                              │
│   This says: a parameter is an identifier, a colon, and a type.            │
│                                                                              │
│   Example: "a: i32"                                                         │
│     IDENTIFIER = "a"                                                        │
│     ":"                                                                      │
│     type = "i32"                                                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### The `?` Operator

The `?` means "optional" - zero or one occurrence:

```
parameters?

Matches:
  ""           (nothing - zero occurrences)   ✓
  "a: i32"     (one occurrence)               ✓
```

### Trace of `fn add(a: i32, b: i32) { return a + b; }`

```
┌──────────────────────────────────────────────────────────────────────────────┐
│        PARSING "fn add(a: i32, b: i32) { return a + b; }"                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [FN] [add] [(] [a] [:] [i32] [,] [b] [:] [i32] [)]                │
│           [{] [RETURN] [a] [+] [b] [;] [}]                                  │
│                                                                              │
│   function():                                                                │
│       expect "fn" → consume                                                 │
│       expect IDENTIFIER → consume, name = "add"                             │
│       expect "(" → consume                                                  │
│                                                                              │
│       see ")"? No, so parse parameters                                      │
│       call parameters():                                                     │
│           call parameter():                                                  │
│               expect IDENTIFIER → consume, name = "a"                       │
│               expect ":" → consume                                          │
│               expect type → consume, type = "i32"                           │
│               return Parameter { name: "a", type: "i32" }                   │
│                                                                              │
│           see ","? Yes → consume                                            │
│                                                                              │
│           call parameter():                                                  │
│               expect IDENTIFIER → consume, name = "b"                       │
│               expect ":" → consume                                          │
│               expect type → consume, type = "i32"                           │
│               return Parameter { name: "b", type: "i32" }                   │
│                                                                              │
│           see ","? No                                                       │
│           return [Param("a"), Param("b")]                                   │
│                                                                              │
│       params = [Param("a"), Param("b")]                                     │
│       expect ")" → consume                                                  │
│                                                                              │
│       call block():                                                          │
│           expect "{" → consume                                              │
│           call statement():                                                  │
│               call return_stmt():                                            │
│                   expect "return" → consume                                 │
│                   call expression():                                         │
│                       ... parses "a + b" ...                                │
│                       returns Add(Ident("a"), Ident("b"))                   │
│                   expect ";" → consume                                      │
│                   return ReturnStmt { value: Add(...) }                     │
│           expect "}" → consume                                              │
│           return Block { statements: [ReturnStmt] }                         │
│                                                                              │
│       return FnDecl {                                                        │
│           name: "add",                                                       │
│           params: [Param("a", i32), Param("b", i32)],                       │
│           body: Block { ... }                                               │
│       }                                                                      │
│                                                                              │
│   Tree:                                                                      │
│                    FnDecl("add")                                             │
│                   /      |       \                                           │
│           Param("a")  Param("b")  Block                                     │
│              |           |           |                                       │
│            i32         i32      ReturnStmt                                  │
│                                      |                                       │
│                                     Add                                      │
│                                    /   \                                     │
│                               Ident   Ident                                  │
│                                 |       |                                    │
│                                "a"     "b"                                   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## The Complete Grammar

Here's our full grammar with 11 rules:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         THE COMPLETE GRAMMAR                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   PROGRAM                                                                    │
│   ───────                                                                    │
│   program     → function*                                                   │
│                                                                              │
│   FUNCTIONS                                                                  │
│   ─────────                                                                  │
│   function    → "fn" IDENTIFIER "(" parameters? ")" block                   │
│   parameters  → parameter ("," parameter)*                                  │
│   parameter   → IDENTIFIER ":" type                                         │
│   type        → "i32" | "bool" | "void"                                     │
│                                                                              │
│   STATEMENTS                                                                 │
│   ──────────                                                                 │
│   block       → "{" statement* "}"                                          │
│   statement   → var_decl | return_stmt                                      │
│   var_decl    → "const" IDENTIFIER "=" expression ";"                       │
│   return_stmt → "return" expression ";"                                     │
│                                                                              │
│   EXPRESSIONS                                                                │
│   ───────────                                                                │
│   expression  → term (("+" | "-") term)*                                    │
│   term        → unary (("*" | "/") unary)*                                  │
│   unary       → "-" unary | primary                                         │
│   primary     → NUMBER | IDENTIFIER | "(" expression ")"                    │
│                                                                              │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Total: 11 rules                                                            │
│                                                                              │
│   This grammar can parse programs like:                                     │
│                                                                              │
│       fn main() {                                                           │
│           const x = 1 + 2;                                                  │
│           return x;                                                         │
│       }                                                                      │
│                                                                              │
│       fn add(a: i32, b: i32) {                                              │
│           return a + b;                                                     │
│       }                                                                      │
│                                                                              │
│       fn complex() {                                                        │
│           const result = (1 + 2) * -3;                                      │
│           return result;                                                    │
│       }                                                                      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Structure Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        GRAMMAR STRUCTURE                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   program                                                                    │
│       │                                                                      │
│       └──► function*                                                        │
│               │                                                              │
│               ├──► parameters                                               │
│               │       │                                                      │
│               │       └──► parameter*                                       │
│               │               │                                              │
│               │               └──► type                                     │
│               │                                                              │
│               └──► block                                                    │
│                       │                                                      │
│                       └──► statement*                                       │
│                               │                                              │
│                               ├──► var_decl ──► expression                  │
│                               │                                              │
│                               └──► return_stmt ──► expression               │
│                                                       │                      │
│                                                       └──► term*            │
│                                                              │              │
│                                                              └──► unary*    │
│                                                                     │       │
│                                                                     └──► primary
│                                                                            │
│                                                              ┌─────────────┘
│                                                              │              │
│                                                              └──► expression│
│                                                              (recursion!)   │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Grammar Notation Reference

Here's a quick reference for all the symbols we've used:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      GRAMMAR NOTATION REFERENCE                              │
├────────────┬─────────────────────────────────────────────────────────────────┤
│  Symbol    │  Meaning                                                        │
├────────────┼─────────────────────────────────────────────────────────────────┤
│  →         │  "is defined as" / "is made of"                                │
│            │  Example: expression → term                                    │
│            │  (an expression is made of a term)                             │
├────────────┼─────────────────────────────────────────────────────────────────┤
│  |         │  "or" (alternatives)                                           │
│            │  Example: primary → NUMBER | IDENTIFIER                        │
│            │  (a primary is either a number or an identifier)               │
├────────────┼─────────────────────────────────────────────────────────────────┤
│  *         │  "zero or more" (repetition)                                   │
│            │  Example: statement*                                           │
│            │  (zero or more statements)                                     │
├────────────┼─────────────────────────────────────────────────────────────────┤
│  +         │  "one or more" (at least one)                                  │
│            │  Example: digit+                                               │
│            │  (one or more digits)                                          │
├────────────┼─────────────────────────────────────────────────────────────────┤
│  ?         │  "optional" (zero or one)                                      │
│            │  Example: parameters?                                          │
│            │  (parameters are optional)                                     │
├────────────┼─────────────────────────────────────────────────────────────────┤
│  ( )       │  Grouping                                                      │
│            │  Example: ("+" term)*                                          │
│            │  (the whole "+" term pattern repeats)                          │
├────────────┼─────────────────────────────────────────────────────────────────┤
│  " "       │  Literal text (exact match)                                    │
│            │  Example: "fn"                                                 │
│            │  (the literal characters f and n)                              │
├────────────┼─────────────────────────────────────────────────────────────────┤
│  CAPS      │  Token from lexer                                              │
│            │  Example: NUMBER, IDENTIFIER                                   │
│            │  (tokens produced by the lexer)                                │
├────────────┼─────────────────────────────────────────────────────────────────┤
│  lowercase │  Another grammar rule                                          │
│            │  Example: expression, term, primary                            │
│            │  (references to other rules - calls another parse function)   │
└────────────┴─────────────────────────────────────────────────────────────────┘
```

### Examples of Each

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           NOTATION EXAMPLES                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   statement*                                                                 │
│   ──────────                                                                 │
│   Matches: ""                  (zero statements)                            │
│            "return 1;"         (one statement)                              │
│            "const x = 1; return x;"  (two statements)                       │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   parameters?                                                                │
│   ───────────                                                                │
│   Matches: ""                  (no parameters)                              │
│            "a: i32"            (has parameters)                             │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   NUMBER | IDENTIFIER                                                        │
│   ───────────────────                                                        │
│   Matches: "42"                (NUMBER)                                     │
│            "foo"               (IDENTIFIER)                                 │
│   NOT:     "+"                 (neither)                                    │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   ("," parameter)*                                                          │
│   ────────────────                                                           │
│   Matches: ""                  (zero extra params)                          │
│            ", b: i32"          (one extra param)                            │
│            ", b: i32, c: i32"  (two extra params)                           │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   term (("+" | "-") term)*                                                  │
│   ────────────────────────                                                   │
│   Matches: "1"                 (just a term)                                │
│            "1 + 2"             (term, plus, term)                           │
│            "1 - 2 + 3"         (term, minus, term, plus, term)              │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## From Grammar to Code

Each grammar rule becomes one parse function. Here's the pattern:

### The Template

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                     GRAMMAR RULE → PARSE FUNCTION                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Grammar notation          Code pattern                                    │
│   ────────────────          ────────────                                    │
│                                                                              │
│   "keyword"                 expect(KEYWORD) or consume(KEYWORD)             │
│                                                                              │
│   TOKEN                     consume(TOKEN) and use its value                │
│                                                                              │
│   rule                      call parseRule()                                │
│                                                                              │
│   A | B                     if see(A): parseA() else: parseB()              │
│                                                                              │
│   A*                        while see(A): parseA()                          │
│                                                                              │
│   A?                        if see(A): parseA()                             │
│                                                                              │
│   (A B)*                    while see(A): parseA(); parseB()                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Example: expression → term (("+" | "-") term)*

```
fn parseExpression():
    left = parseTerm()                    // term

    while see(PLUS) or see(MINUS):        // (("+" | "-") term)*
        op = consume()                    // consume "+" or "-"
        right = parseTerm()               // term
        left = BinaryNode(left, op, right)

    return left
```

### Example: unary → "-" unary | primary

```
fn parseUnary():
    if see(MINUS):                        // "-" unary
        consume(MINUS)
        operand = parseUnary()            // recursive call
        return UnaryNode(MINUS, operand)
    else:                                 // | primary
        return parsePrimary()
```

### Example: block → "{" statement* "}"

```
fn parseBlock():
    expect(LBRACE)                        // "{"

    statements = []
    while not see(RBRACE):                // statement*
        stmt = parseStatement()
        statements.append(stmt)

    expect(RBRACE)                        // "}"
    return BlockNode(statements)
```

### Example: function → "fn" IDENTIFIER "(" parameters? ")" block

```
fn parseFunction():
    expect(FN)                            // "fn"
    name = consume(IDENTIFIER)            // IDENTIFIER
    expect(LPAREN)                        // "("

    if not see(RPAREN):                   // parameters?
        params = parseParameters()
    else:
        params = []

    expect(RPAREN)                        // ")"
    body = parseBlock()                   // block

    return FunctionNode(name, params, body)
```

### The Complete Mapping

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                  GRAMMAR RULES → PARSE FUNCTIONS                             │
├────────────────────────────────┬─────────────────────────────────────────────┤
│  Grammar Rule                  │  Parse Function                             │
├────────────────────────────────┼─────────────────────────────────────────────┤
│  program → function*           │  parseProgram()                             │
│  function → "fn" NAME ...      │  parseFunction()                            │
│  parameters → param (, param)* │  parseParameters()                          │
│  parameter → NAME ":" type     │  parseParameter()                           │
│  type → "i32" | "bool" | ...   │  parseType()                                │
│  block → "{" statement* "}"    │  parseBlock()                               │
│  statement → var | return      │  parseStatement()                           │
│  var_decl → "const" NAME ...   │  parseVarDecl()                             │
│  return_stmt → "return" ...    │  parseReturnStmt()                          │
│  expression → term ((+|-) ..)* │  parseExpression()                          │
│  term → unary ((*|/) unary)*   │  parseTerm()                                │
│  unary → "-" unary | primary   │  parseUnary()                               │
│  primary → NUM | ID | (expr)   │  parsePrimary()                             │
└────────────────────────────────┴─────────────────────────────────────────────┘
```

---

## The Key Insight

Let's summarize the most important things we've learned:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          THE KEY INSIGHTS                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. GRAMMAR STRUCTURE = AST STRUCTURE                                      │
│   ─────────────────────────────────────                                      │
│   The nesting in your grammar rules becomes the nesting in your tree.       │
│   If rule A calls rule B, then A nodes contain B nodes as children.         │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   2. NESTING DEPTH = PRECEDENCE                                             │
│   ─────────────────────────────                                              │
│   Rules that are called first (deepest in the call chain) have the          │
│   highest precedence. They're evaluated first because they're innermost.    │
│                                                                              │
│   expression → term → unary → primary                                       │
│   LOW prec    ───────────────►    HIGH prec                                 │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   3. CALL STACK = TREE STRUCTURE                                            │
│   ──────────────────────────────                                             │
│   As parse functions call each other, the call stack naturally forms        │
│   the tree structure. When functions return, they return tree nodes         │
│   to their parent callers.                                                   │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   4. EACH RULE = ONE FUNCTION                                               │
│   ───────────────────────────                                                │
│   There's a direct 1:1 mapping from grammar rules to parse functions.       │
│   Write the grammar first, then translating to code is mechanical.          │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   5. LOOPS FOR *, CONDITIONALS FOR |                                        │
│   ────────────────────────────────────                                       │
│   The * becomes a while loop. The | becomes an if-else chain.               │
│   The ? becomes a simple if check.                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Extending the Grammar

Once you understand the pattern, adding new features is straightforward.

### Adding If Statements

```
statement → var_decl
          | return_stmt
          | if_stmt            ← NEW

if_stmt → "if" expression block ("else" block)?
```

Parse function:

```
fn parseIfStmt():
    expect(IF)
    condition = parseExpression()
    then_block = parseBlock()

    if see(ELSE):
        consume(ELSE)
        else_block = parseBlock()
    else:
        else_block = null

    return IfNode(condition, then_block, else_block)
```

### Adding While Loops

```
statement → var_decl
          | return_stmt
          | if_stmt
          | while_stmt         ← NEW

while_stmt → "while" expression block
```

Parse function:

```
fn parseWhileStmt():
    expect(WHILE)
    condition = parseExpression()
    body = parseBlock()
    return WhileNode(condition, body)
```

### Adding More Operators

To add comparison operators (`<`, `>`, `==`):

```
expression → comparison                                    ← CHANGE
comparison → term (("<" | ">" | "==" | "!=") term)*       ← NEW
term       → unary (("*" | "/") unary)*
unary      → "-" unary | primary
primary    → NUMBER | IDENTIFIER | "(" expression ")"
```

Now comparison has LOWER precedence than `+` and `-`.

Wait, that's wrong! Let's fix the precedence:

```
expression  → comparison                                    ← LOWEST
comparison  → additive (("<" | ">" | "==") additive)*      ← LOW
additive    → term (("+" | "-") term)*                     ← MEDIUM
term        → unary (("*" | "/") unary)*                   ← HIGH
unary       → "-" unary | primary                          ← HIGHER
primary     → NUMBER | IDENTIFIER | "(" expression ")"     ← HIGHEST
```

The pattern: **insert new rules between existing ones** based on where you want the precedence.

### Adding Function Calls

```
primary → NUMBER
        | IDENTIFIER
        | IDENTIFIER "(" arguments? ")"    ← NEW: function call
        | "(" expression ")"

arguments → expression ("," expression)*
```

But wait - both "IDENTIFIER" and "IDENTIFIER (" start with IDENTIFIER! We need to look ahead:

```
fn parsePrimary():
    if see(NUMBER):
        return parseNumber()

    if see(IDENTIFIER):
        if peekNext() == LPAREN:           // Look ahead!
            return parseCall()
        else:
            return parseIdentifier()

    if see(LPAREN):
        return parseGrouped()

    error("Expected primary expression")
```

---

## The Grammar Design Process

Here's how to design a grammar for any language:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    THE GRAMMAR DESIGN PROCESS                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   STEP 1: Write example programs                                            │
│   ──────────────────────────────                                             │
│   What should your language look like? Write examples:                      │
│                                                                              │
│       1 + 2                                                                 │
│       const x = 5;                                                          │
│       fn add(a, b) { return a + b; }                                        │
│                                                                              │
│   STEP 2: Identify categories                                               │
│   ──────────────────────────                                                 │
│   What kinds of things exist?                                               │
│                                                                              │
│       - Expressions (produce values)                                        │
│       - Statements (do things)                                              │
│       - Declarations (define things)                                        │
│                                                                              │
│   STEP 3: List operators by precedence                                      │
│   ────────────────────────────────────                                       │
│   From lowest to highest:                                                   │
│                                                                              │
│       1. || (or)                                                            │
│       2. && (and)                                                           │
│       3. == != < > (comparison)                                             │
│       4. + - (additive)                                                     │
│       5. * / (multiplicative)                                               │
│       6. - ! (unary prefix)                                                 │
│       7. () . [] (postfix)                                                  │
│                                                                              │
│   STEP 4: Write rules from bottom up                                        │
│   ──────────────────────────────────                                         │
│   Start with the HIGHEST precedence (primary),                              │
│   then work your way up to the LOWEST (expression).                         │
│                                                                              │
│   STEP 5: Add statements and declarations                                   │
│   ────────────────────────────────────────                                   │
│   Statements contain expressions.                                           │
│   Declarations contain statements (in blocks).                              │
│   Program contains declarations.                                            │
│                                                                              │
│   STEP 6: Translate to parse functions                                      │
│   ────────────────────────────────────                                       │
│   One rule = one function.                                                  │
│   Follow the mechanical translation.                                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Common Patterns

Here are patterns you'll use over and over:

### Binary Operators (Left-Associative)

```
rule → next_level ((OP1 | OP2) next_level)*
```

```
fn parseRule():
    left = parseNextLevel()
    while see(OP1) or see(OP2):
        op = consume()
        right = parseNextLevel()
        left = BinaryNode(left, op, right)
    return left
```

### Unary Operators (Prefix)

```
rule → OP rule | next_level
```

```
fn parseRule():
    if see(OP):
        consume()
        operand = parseRule()    // recursive
        return UnaryNode(OP, operand)
    return parseNextLevel()
```

### Optional Parts

```
rule → A B?
```

```
fn parseRule():
    a = parseA()
    b = null
    if see(B_START):
        b = parseB()
    return Node(a, b)
```

### Lists with Separators

```
list → item ("," item)*
```

```
fn parseList():
    items = [parseItem()]
    while see(COMMA):
        consume(COMMA)
        items.append(parseItem())
    return items
```

### Blocks of Things

```
block → "{" item* "}"
```

```
fn parseBlock():
    expect(LBRACE)
    items = []
    while not see(RBRACE):
        items.append(parseItem())
    expect(RBRACE)
    return items
```

---

## Complex Example: Parsing a Complete Program

Let's trace through parsing a complete, non-trivial program:

```
fn factorial(n: i32) {
    const result = n * (n - 1);
    return result;
}

fn main() {
    const x = factorial(5);
    return x;
}
```

### The Token Stream

First, the lexer produces this token stream:

```
[FN] [factorial] [LPAREN] [n] [COLON] [i32] [RPAREN] [LBRACE]
[CONST] [result] [EQUAL] [n] [STAR] [LPAREN] [n] [MINUS] [1] [RPAREN] [SEMICOLON]
[RETURN] [result] [SEMICOLON]
[RBRACE]
[FN] [main] [LPAREN] [RPAREN] [LBRACE]
[CONST] [x] [EQUAL] [factorial] [LPAREN] [5] [RPAREN] [SEMICOLON]
[RETURN] [x] [SEMICOLON]
[RBRACE]
[EOF]
```

### Full Parse Trace

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    PARSING COMPLETE PROGRAM                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   program():                                                                 │
│       functions = []                                                         │
│                                                                              │
│       ┌─ FIRST FUNCTION ─────────────────────────────────────────────────┐  │
│       │                                                                   │  │
│       │   function():                                                     │  │
│       │       expect FN → ✓                                              │  │
│       │       name = "factorial"                                         │  │
│       │       expect LPAREN → ✓                                          │  │
│       │                                                                   │  │
│       │       parameters():                                               │  │
│       │           parameter():                                            │  │
│       │               name = "n"                                         │  │
│       │               expect COLON → ✓                                   │  │
│       │               type = "i32"                                       │  │
│       │               return Parameter("n", i32)                         │  │
│       │           see COMMA? No                                          │  │
│       │           return [Parameter("n", i32)]                           │  │
│       │                                                                   │  │
│       │       expect RPAREN → ✓                                          │  │
│       │                                                                   │  │
│       │       block():                                                    │  │
│       │           expect LBRACE → ✓                                      │  │
│       │           statements = []                                        │  │
│       │                                                                   │  │
│       │           ┌─ FIRST STATEMENT ─────────────────────────────────┐  │  │
│       │           │                                                    │  │  │
│       │           │   statement():                                     │  │  │
│       │           │       see CONST? Yes                               │  │  │
│       │           │       var_decl():                                  │  │  │
│       │           │           expect CONST → ✓                        │  │  │
│       │           │           name = "result"                         │  │  │
│       │           │           expect EQUAL → ✓                        │  │  │
│       │           │                                                    │  │  │
│       │           │           expression():                            │  │  │
│       │           │               term():                              │  │  │
│       │           │                   unary():                         │  │  │
│       │           │                       primary():                   │  │  │
│       │           │                           see IDENT "n"           │  │  │
│       │           │                           return Ident("n")       │  │  │
│       │           │                   left = Ident("n")               │  │  │
│       │           │                   see STAR? Yes!                  │  │  │
│       │           │                   consume STAR                    │  │  │
│       │           │                   unary():                         │  │  │
│       │           │                       primary():                   │  │  │
│       │           │                           see LPAREN              │  │  │
│       │           │                           consume LPAREN          │  │  │
│       │           │                           ┌────────────────────┐  │  │  │
│       │           │                           │ NESTED expression: │  │  │  │
│       │           │                           │   term():          │  │  │  │
│       │           │                           │     Ident("n")     │  │  │  │
│       │           │                           │   see MINUS? Yes   │  │  │  │
│       │           │                           │   term():          │  │  │  │
│       │           │                           │     Number(1)      │  │  │  │
│       │           │                           │   return Sub(n, 1) │  │  │  │
│       │           │                           └────────────────────┘  │  │  │
│       │           │                           expect RPAREN → ✓       │  │  │
│       │           │                           return Sub(n, 1)       │  │  │
│       │           │                   right = Sub(n, 1)              │  │  │
│       │           │                   left = Mul(Ident("n"), Sub(n,1))│ │  │
│       │           │                   see STAR? No                   │  │  │
│       │           │                   return Mul(...)                │  │  │
│       │           │               see PLUS/MINUS? No                  │  │  │
│       │           │               return Mul(Ident("n"), Sub(n, 1))   │  │  │
│       │           │                                                    │  │  │
│       │           │           expect SEMICOLON → ✓                    │  │  │
│       │           │           return VarDecl("result", Mul(...))      │  │  │
│       │           │                                                    │  │  │
│       │           └────────────────────────────────────────────────────┘  │  │
│       │                                                                   │  │
│       │           ┌─ SECOND STATEMENT ────────────────────────────────┐  │  │
│       │           │                                                    │  │  │
│       │           │   statement():                                     │  │  │
│       │           │       see RETURN? Yes                              │  │  │
│       │           │       return_stmt():                               │  │  │
│       │           │           expect RETURN → ✓                       │  │  │
│       │           │           expression():                            │  │  │
│       │           │               ... returns Ident("result")         │  │  │
│       │           │           expect SEMICOLON → ✓                    │  │  │
│       │           │           return ReturnStmt(Ident("result"))      │  │  │
│       │           │                                                    │  │  │
│       │           └────────────────────────────────────────────────────┘  │  │
│       │                                                                   │  │
│       │           see RBRACE? Yes                                        │  │
│       │           expect RBRACE → ✓                                      │  │
│       │           return Block([VarDecl, ReturnStmt])                    │  │
│       │                                                                   │  │
│       │       return FnDecl("factorial", [Param], Block)                 │  │
│       │                                                                   │  │
│       └───────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│       append FnDecl("factorial", ...) to functions                          │
│                                                                              │
│       ┌─ SECOND FUNCTION (main) ─────────────────────────────────────────┐  │
│       │                                                                   │  │
│       │   function():                                                     │  │
│       │       expect FN → ✓                                              │  │
│       │       name = "main"                                              │  │
│       │       expect LPAREN → ✓                                          │  │
│       │       see RPAREN? Yes (no parameters)                            │  │
│       │       expect RPAREN → ✓                                          │  │
│       │                                                                   │  │
│       │       block():                                                    │  │
│       │           expect LBRACE → ✓                                      │  │
│       │                                                                   │  │
│       │           statement(): var_decl                                   │  │
│       │               name = "x"                                         │  │
│       │               expression():                                       │  │
│       │                   primary():                                      │  │
│       │                       see IDENT "factorial"                      │  │
│       │                       peekNext() == LPAREN? Yes!                 │  │
│       │                       parseCall():                                │  │
│       │                           name = "factorial"                     │  │
│       │                           expect LPAREN → ✓                      │  │
│       │                           arguments():                           │  │
│       │                               expression() → Number(5)           │  │
│       │                           expect RPAREN → ✓                      │  │
│       │                           return Call("factorial", [5])          │  │
│       │               return VarDecl("x", Call("factorial", [5]))        │  │
│       │                                                                   │  │
│       │           statement(): return_stmt                                │  │
│       │               return ReturnStmt(Ident("x"))                      │  │
│       │                                                                   │  │
│       │           return Block([VarDecl, ReturnStmt])                    │  │
│       │                                                                   │  │
│       │       return FnDecl("main", [], Block)                           │  │
│       │                                                                   │  │
│       └───────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│       append FnDecl("main", ...) to functions                               │
│                                                                              │
│       see EOF? Yes                                                           │
│       return Program([FnDecl("factorial"), FnDecl("main")])                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### The Final AST

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         FINAL AST STRUCTURE                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Program                                                                    │
│   ├── FnDecl("factorial")                                                   │
│   │   ├── params: [Parameter("n", i32)]                                     │
│   │   └── body: Block                                                       │
│   │       ├── VarDecl("result")                                             │
│   │       │   └── value: Mul                                                │
│   │       │       ├── left: Ident("n")                                      │
│   │       │       └── right: Sub                                            │
│   │       │           ├── left: Ident("n")                                  │
│   │       │           └── right: Number(1)                                  │
│   │       └── ReturnStmt                                                    │
│   │           └── value: Ident("result")                                    │
│   │                                                                         │
│   └── FnDecl("main")                                                        │
│       ├── params: []                                                        │
│       └── body: Block                                                       │
│           ├── VarDecl("x")                                                  │
│           │   └── value: Call                                               │
│           │       ├── callee: "factorial"                                   │
│           │       └── args: [Number(5)]                                     │
│           └── ReturnStmt                                                    │
│               └── value: Ident("x")                                         │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Right-Associativity: Assignment and Exponentiation

So far, all our operators have been **left-associative**:

```
1 - 2 - 3 = (1 - 2) - 3    Left-associative
```

But some operators are **right-associative**:

```
x = y = z    means    x = (y = z)    Right-associative (if = is expression)
2 ^ 3 ^ 4    means    2 ^ (3 ^ 4)    Right-associative (exponentiation)
```

### How to Achieve Right-Associativity

The trick: **don't add 1** to the precedence in recursive calls, OR use recursion instead of a loop.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│               LEFT VS RIGHT ASSOCIATIVITY                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   LEFT-ASSOCIATIVE (use loop OR precedence + 1):                            │
│   ──────────────────────────────────────────────                             │
│                                                                              │
│   fn parseAdditive():                                                        │
│       left = parseTerm()                                                    │
│       while see(PLUS) or see(MINUS):                                        │
│           op = consume()                                                    │
│           right = parseTerm()         ← calls SAME level                    │
│           left = BinaryNode(left, op, right)                                │
│       return left                                                            │
│                                                                              │
│   1 + 2 + 3 → ((1 + 2) + 3)                                                 │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   RIGHT-ASSOCIATIVE (use recursion):                                        │
│   ────────────────────────────────────                                       │
│                                                                              │
│   fn parseAssignment():                                                      │
│       left = parseEquality()                                                │
│       if see(EQUAL):                                                        │
│           consume()                                                         │
│           right = parseAssignment()   ← RECURSE to same function!           │
│           return AssignNode(left, right)                                    │
│       return left                                                            │
│                                                                              │
│   x = y = z → (x = (y = z))                                                 │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Why Does Recursion Give Right-Associativity?

```
Parsing: x = y = 5

parseAssignment():
    left = parseEquality() → Ident("x")
    see "="? Yes
    right = parseAssignment()           ← recursive call
        left = parseEquality() → Ident("y")
        see "="? Yes
        right = parseAssignment()       ← recursive call
            left = parseEquality() → Number(5)
            see "="? No
            return Number(5)
        return Assign(Ident("y"), Number(5))
    return Assign(Ident("x"), Assign(Ident("y"), Number(5)))

Tree:
         Assign
        /      \
   Ident("x")  Assign
              /      \
         Ident("y")  Number(5)

This is: x = (y = 5)  ✓ Right-associative!
```

### Exponentiation Example

```
Grammar:
    power → unary ("^" power)?      ← recursive, not loop!

Parsing: 2 ^ 3 ^ 4

parsePower():
    left = parseUnary() → Number(2)
    see "^"? Yes
    consume "^"
    right = parsePower()              ← recurse!
        left = parseUnary() → Number(3)
        see "^"? Yes
        consume "^"
        right = parsePower()          ← recurse!
            left = parseUnary() → Number(4)
            see "^"? No
            return Number(4)
        return Power(3, 4)
    return Power(2, Power(3, 4))

Tree:
         Power
        /     \
       2      Power
             /     \
            3       4

Evaluation: 2 ^ (3 ^ 4) = 2 ^ 81 = huge number
(Not (2 ^ 3) ^ 4 = 8 ^ 4 = 4096)
```

---

## Handling Errors Gracefully

Real parsers need to handle errors. What happens when input is invalid?

### Types of Parse Errors

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         COMMON PARSE ERRORS                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. UNEXPECTED TOKEN                                                        │
│   ───────────────────                                                        │
│   const x = ;                                                               │
│              ^                                                               │
│   Expected expression, got semicolon                                        │
│                                                                              │
│   2. MISSING TOKEN                                                          │
│   ────────────────                                                           │
│   const x = 5                                                               │
│               ^                                                              │
│   Expected semicolon, got EOF                                               │
│                                                                              │
│   3. UNCLOSED DELIMITER                                                     │
│   ─────────────────────                                                      │
│   fn foo() {                                                                │
│       return 5;                                                             │
│                 ^                                                            │
│   Expected }, got EOF                                                       │
│                                                                              │
│   4. INVALID EXPRESSION                                                     │
│   ─────────────────────                                                      │
│   const x = 1 + + 2;                                                        │
│                 ^                                                            │
│   Unexpected + in expression                                                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### The `expect` Pattern

Use an `expect` function that reports errors:

```
fn expect(tokenType):
    if peek().type == tokenType:
        return consume()
    else:
        error("Expected " + tokenType + ", got " + peek().type)
```

### Error Recovery: Synchronization

After an error, the parser needs to "recover" to continue finding more errors. The common technique is **synchronization** - skip tokens until you find a safe point.

```
fn parseStatement():
    try:
        if see(CONST): return parseVarDecl()
        if see(RETURN): return parseReturnStmt()
        error("Expected statement")
    catch ParseError:
        synchronize()    // Skip to next statement
        return ErrorNode()

fn synchronize():
    // Skip tokens until we find a statement boundary
    while not isAtEnd():
        if previous().type == SEMICOLON:
            return    // Just passed a semicolon, good place to resume

        switch peek().type:
            CONST, RETURN, FN, IF, WHILE:
                return    // Found a keyword that starts a statement
            default:
                advance()    // Skip this token
```

### Example: Multiple Errors

```
Input:
    const x = ;
    const y = 5;
    return

Parser output:
    Error at line 1: Expected expression, got semicolon
    Error at line 3: Expected expression after 'return'
    Error at line 3: Expected semicolon, got EOF

Even though line 1 had an error, we recovered and parsed line 2
successfully, then found more errors on line 3.
```

---

## Lookahead: When One Token Isn't Enough

Sometimes you need to look at more than just the current token.

### The Problem

```
primary → IDENTIFIER
        | IDENTIFIER "(" arguments ")"    // function call
```

Both start with IDENTIFIER! How do we know which one?

### Solution: Peek Ahead

```
fn parsePrimary():
    if see(IDENTIFIER):
        if peekNext() == LPAREN:
            return parseCall()
        else:
            return parseIdentifier()
    // ...
```

### When Lookahead Gets Complicated

Some grammars need more than one token of lookahead:

```
// Is this a type annotation or a comparison?
x: i32           // type annotation (x has type i32)
x < y            // comparison (is x less than y?)

// Both start with: IDENTIFIER followed by something
```

Solution: Restructure the grammar or use context:

```
// In a declaration context, expect type
var_decl → IDENTIFIER ":" type "=" expression ";"

// In an expression context, expect comparison
expression → ... (("<" | ">") ...)*
```

---

## Putting It All Together: A Complete Parser

Here's the complete pseudocode for our parser:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        COMPLETE PARSER PSEUDOCODE                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   // ═══════════════════════════════════════════════════════════════════    │
│   // HELPER FUNCTIONS                                                        │
│   // ═══════════════════════════════════════════════════════════════════    │
│                                                                              │
│   fn peek():                                                                 │
│       return tokens[current]                                                │
│                                                                              │
│   fn previous():                                                             │
│       return tokens[current - 1]                                            │
│                                                                              │
│   fn isAtEnd():                                                              │
│       return peek().type == EOF                                             │
│                                                                              │
│   fn advance():                                                              │
│       if not isAtEnd(): current++                                           │
│       return previous()                                                     │
│                                                                              │
│   fn see(type):                                                              │
│       return peek().type == type                                            │
│                                                                              │
│   fn consume(type):                                                          │
│       if see(type): return advance()                                        │
│       error("Unexpected token")                                             │
│                                                                              │
│   fn expect(type):                                                           │
│       if see(type): return advance()                                        │
│       error("Expected " + type)                                             │
│                                                                              │
│   // ═══════════════════════════════════════════════════════════════════    │
│   // PROGRAM & FUNCTIONS                                                     │
│   // ═══════════════════════════════════════════════════════════════════    │
│                                                                              │
│   fn parseProgram():                                                         │
│       functions = []                                                        │
│       while not isAtEnd():                                                  │
│           functions.append(parseFunction())                                 │
│       return ProgramNode(functions)                                         │
│                                                                              │
│   fn parseFunction():                                                        │
│       expect(FN)                                                            │
│       name = expect(IDENTIFIER).lexeme                                      │
│       expect(LPAREN)                                                        │
│       params = []                                                           │
│       if not see(RPAREN):                                                   │
│           params = parseParameters()                                        │
│       expect(RPAREN)                                                        │
│       body = parseBlock()                                                   │
│       return FnDeclNode(name, params, body)                                 │
│                                                                              │
│   fn parseParameters():                                                      │
│       params = [parseParameter()]                                           │
│       while see(COMMA):                                                     │
│           advance()                                                         │
│           params.append(parseParameter())                                   │
│       return params                                                         │
│                                                                              │
│   fn parseParameter():                                                       │
│       name = expect(IDENTIFIER).lexeme                                      │
│       expect(COLON)                                                         │
│       type = parseType()                                                    │
│       return ParameterNode(name, type)                                      │
│                                                                              │
│   fn parseType():                                                            │
│       if see(I32): advance(); return TypeNode("i32")                        │
│       if see(BOOL): advance(); return TypeNode("bool")                      │
│       if see(VOID): advance(); return TypeNode("void")                      │
│       error("Expected type")                                                │
│                                                                              │
│   // ═══════════════════════════════════════════════════════════════════    │
│   // STATEMENTS                                                              │
│   // ═══════════════════════════════════════════════════════════════════    │
│                                                                              │
│   fn parseBlock():                                                           │
│       expect(LBRACE)                                                        │
│       statements = []                                                       │
│       while not see(RBRACE) and not isAtEnd():                              │
│           statements.append(parseStatement())                               │
│       expect(RBRACE)                                                        │
│       return BlockNode(statements)                                          │
│                                                                              │
│   fn parseStatement():                                                       │
│       if see(CONST) or see(VAR):                                            │
│           return parseVarDecl()                                             │
│       if see(RETURN):                                                       │
│           return parseReturnStmt()                                          │
│       if see(IF):                                                           │
│           return parseIfStmt()                                              │
│       if see(WHILE):                                                        │
│           return parseWhileStmt()                                           │
│       error("Expected statement")                                           │
│                                                                              │
│   fn parseVarDecl():                                                         │
│       isConst = see(CONST)                                                  │
│       advance()  // consume CONST or VAR                                    │
│       name = expect(IDENTIFIER).lexeme                                      │
│       expect(EQUAL)                                                         │
│       value = parseExpression()                                             │
│       expect(SEMICOLON)                                                     │
│       return VarDeclNode(name, value, isConst)                              │
│                                                                              │
│   fn parseReturnStmt():                                                      │
│       expect(RETURN)                                                        │
│       value = null                                                          │
│       if not see(SEMICOLON):                                                │
│           value = parseExpression()                                         │
│       expect(SEMICOLON)                                                     │
│       return ReturnNode(value)                                              │
│                                                                              │
│   fn parseIfStmt():                                                          │
│       expect(IF)                                                            │
│       condition = parseExpression()                                         │
│       thenBranch = parseBlock()                                             │
│       elseBranch = null                                                     │
│       if see(ELSE):                                                         │
│           advance()                                                         │
│           elseBranch = parseBlock()                                         │
│       return IfNode(condition, thenBranch, elseBranch)                      │
│                                                                              │
│   fn parseWhileStmt():                                                       │
│       expect(WHILE)                                                         │
│       condition = parseExpression()                                         │
│       body = parseBlock()                                                   │
│       return WhileNode(condition, body)                                     │
│                                                                              │
│   // ═══════════════════════════════════════════════════════════════════    │
│   // EXPRESSIONS                                                             │
│   // ═══════════════════════════════════════════════════════════════════    │
│                                                                              │
│   fn parseExpression():                                                      │
│       return parseEquality()                                                │
│                                                                              │
│   fn parseEquality():                                                        │
│       left = parseComparison()                                              │
│       while see(EQUAL_EQUAL) or see(BANG_EQUAL):                            │
│           op = advance()                                                    │
│           right = parseComparison()                                         │
│           left = BinaryNode(left, op, right)                                │
│       return left                                                            │
│                                                                              │
│   fn parseComparison():                                                      │
│       left = parseAdditive()                                                │
│       while see(LESS) or see(GREATER) or see(LESS_EQ) or see(GREATER_EQ):  │
│           op = advance()                                                    │
│           right = parseAdditive()                                           │
│           left = BinaryNode(left, op, right)                                │
│       return left                                                            │
│                                                                              │
│   fn parseAdditive():                                                        │
│       left = parseTerm()                                                    │
│       while see(PLUS) or see(MINUS):                                        │
│           op = advance()                                                    │
│           right = parseTerm()                                               │
│           left = BinaryNode(left, op, right)                                │
│       return left                                                            │
│                                                                              │
│   fn parseTerm():                                                            │
│       left = parseUnary()                                                   │
│       while see(STAR) or see(SLASH):                                        │
│           op = advance()                                                    │
│           right = parseUnary()                                              │
│           left = BinaryNode(left, op, right)                                │
│       return left                                                            │
│                                                                              │
│   fn parseUnary():                                                           │
│       if see(MINUS) or see(BANG):                                           │
│           op = advance()                                                    │
│           operand = parseUnary()                                            │
│           return UnaryNode(op, operand)                                     │
│       return parseCall()                                                    │
│                                                                              │
│   fn parseCall():                                                            │
│       expr = parsePrimary()                                                 │
│       if see(LPAREN):                                                       │
│           advance()                                                         │
│           args = []                                                         │
│           if not see(RPAREN):                                               │
│               args = parseArguments()                                       │
│           expect(RPAREN)                                                    │
│           return CallNode(expr, args)                                       │
│       return expr                                                            │
│                                                                              │
│   fn parseArguments():                                                       │
│       args = [parseExpression()]                                            │
│       while see(COMMA):                                                     │
│           advance()                                                         │
│           args.append(parseExpression())                                    │
│       return args                                                            │
│                                                                              │
│   fn parsePrimary():                                                         │
│       if see(NUMBER):                                                       │
│           return NumberNode(advance().value)                                │
│       if see(IDENTIFIER):                                                   │
│           return IdentNode(advance().lexeme)                                │
│       if see(TRUE):                                                         │
│           advance()                                                         │
│           return BoolNode(true)                                             │
│       if see(FALSE):                                                        │
│           advance()                                                         │
│           return BoolNode(false)                                            │
│       if see(LPAREN):                                                       │
│           advance()                                                         │
│           expr = parseExpression()                                          │
│           expect(RPAREN)                                                    │
│           return expr                                                        │
│       error("Expected expression")                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Common Mistakes to Avoid

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        COMMON MISTAKES                                       │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   1. WRONG ASSOCIATIVITY                                                    │
│   ──────────────────────                                                     │
│   Using recursion when you want left-associativity:                         │
│                                                                              │
│   // WRONG - gives right-associativity                                      │
│   fn parseAdditive():                                                        │
│       left = parseTerm()                                                    │
│       if see(PLUS):                                                         │
│           advance()                                                         │
│           right = parseAdditive()  // recursive!                            │
│           return BinaryNode(left, PLUS, right)                              │
│       return left                                                            │
│                                                                              │
│   // CORRECT - use a loop for left-associativity                            │
│   fn parseAdditive():                                                        │
│       left = parseTerm()                                                    │
│       while see(PLUS):                                                      │
│           advance()                                                         │
│           right = parseTerm()                                               │
│           left = BinaryNode(left, PLUS, right)                              │
│       return left                                                            │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   2. INFINITE LOOP                                                          │
│   ────────────────                                                           │
│   Forgetting to consume tokens in a loop:                                   │
│                                                                              │
│   // WRONG - infinite loop!                                                 │
│   while see(PLUS):                                                          │
│       right = parseTerm()  // never consumes PLUS!                          │
│                                                                              │
│   // CORRECT                                                                │
│   while see(PLUS):                                                          │
│       advance()            // consume the PLUS                              │
│       right = parseTerm()                                                   │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   3. WRONG PRECEDENCE ORDER                                                 │
│   ─────────────────────────                                                  │
│   Remember: rules called FIRST have HIGHER precedence                       │
│                                                                              │
│   // WRONG - * has lower precedence than +                                  │
│   expression → unary (("*" | "/") unary)*                                   │
│   term → primary (("+" | "-") primary)*                                     │
│                                                                              │
│   // CORRECT - * has higher precedence than +                               │
│   expression → term (("+" | "-") term)*                                     │
│   term → unary (("*" | "/") unary)*                                         │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   4. NOT HANDLING END OF INPUT                                              │
│   ────────────────────────────                                               │
│   Always check for EOF to avoid reading past the end:                       │
│                                                                              │
│   // WRONG - might read past EOF                                            │
│   while not see(RBRACE):                                                    │
│       statements.append(parseStatement())                                   │
│                                                                              │
│   // CORRECT - also check for end of input                                  │
│   while not see(RBRACE) and not isAtEnd():                                  │
│       statements.append(parseStatement())                                   │
│                                                                              │
│   ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│   5. FORGETTING TO RETURN                                                   │
│   ───────────────────────                                                    │
│   Make sure all paths return a value:                                       │
│                                                                              │
│   // WRONG - might not return anything                                      │
│   fn parsePrimary():                                                         │
│       if see(NUMBER): return parseNumber()                                  │
│       if see(IDENTIFIER): return parseIdentifier()                          │
│       // what if neither? falls through without return!                     │
│                                                                              │
│   // CORRECT - handle the error case                                        │
│   fn parsePrimary():                                                         │
│       if see(NUMBER): return parseNumber()                                  │
│       if see(IDENTIFIER): return parseIdentifier()                          │
│       error("Expected expression")  // or throw/return error node          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              SUMMARY                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   A grammar is a set of rules describing valid programs.                    │
│                                                                              │
│   Each rule has:                                                             │
│     - A name (left side)                                                    │
│     - A definition (right side)                                             │
│                                                                              │
│   Rules can use:                                                             │
│     - Literals: "fn", "return"                                              │
│     - Tokens: NUMBER, IDENTIFIER                                            │
│     - Other rules: expression, statement                                    │
│     - Operators: | (or), * (repeat), ? (optional)                           │
│                                                                              │
│   Precedence is handled by nesting rules:                                   │
│     - Outer rules = lower precedence                                        │
│     - Inner rules = higher precedence                                       │
│                                                                              │
│   Each rule becomes one parse function.                                     │
│                                                                              │
│   The call stack forms the tree structure.                                  │
│                                                                              │
│   Start with examples, identify patterns, write rules, translate to code.  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What's Next

Now you understand how to design a grammar. The next step is implementing it in code - creating the actual parse functions and AST nodes.

See the [Parser Tutorial](../compiler-tutorial/02-parser/) for a complete implementation.

---

## Quick Reference

### Our Complete Grammar

```
program     → function*
function    → "fn" IDENTIFIER "(" parameters? ")" block
parameters  → parameter ("," parameter)*
parameter   → IDENTIFIER ":" type
type        → "i32" | "bool" | "void"
block       → "{" statement* "}"
statement   → var_decl | return_stmt
var_decl    → "const" IDENTIFIER "=" expression ";"
return_stmt → "return" expression ";"
expression  → term (("+" | "-") term)*
term        → unary (("*" | "/") unary)*
unary       → "-" unary | primary
primary     → NUMBER | IDENTIFIER | "(" expression ")"
```

### Notation Reference

```
→     "is defined as"
|     "or"
*     "zero or more"
+     "one or more"
?     "optional"
( )   grouping
" "   literal
CAPS  token
lower other rule
```
