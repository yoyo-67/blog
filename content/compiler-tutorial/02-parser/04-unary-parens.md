---
title: "2.4: Unary & Parentheses"
weight: 4
---

# Lesson 2.4: Unary Operators and Parentheses

Complete our expression grammar with `-5` and `(1 + 2)`.

---

## Goal

Add unary operators and parentheses to build a complete expression parser.

---

## Unary Operators

What about `-5` or `-x`? These are **unary operators** - they take one operand.

### The Problem

Our current grammar only handles binary operators (two operands):

```
expression → term (("+" | "-") term)*
term       → NUMBER (("*" | "/") NUMBER)*
```

The `-` in `-5` is different from the `-` in `3 - 5`. We need a new rule.

---

## The Unary Rule

Add a new level between `term` and `NUMBER`:

```
expression → term (("+" | "-") term)*
term       → unary (("*" | "/") unary)*
unary      → "-" unary | NUMBER
```

The new `unary` rule says:
- A unary is either: minus followed by another unary, OR just a number

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

---

## Why Unary is Between Term and Number

Precedence order (highest to lowest):
1. **Unary minus**: `-x` (happens first)
2. **Multiplication/Division**: `*` `/`
3. **Addition/Subtraction**: `+` `-`

So the call chain is: `expression → term → unary → number`

```
-2 * 3  parses as  (-2) * 3   ✓
```

If unary were at expression level:
```
-2 * 3  would parse as  -(2 * 3)  ✗ Wrong!
```

---

## Trace of `-1 + 2`

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
│            ▲                                                                 │
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

## Parentheses

Parentheses let users override precedence: `(1 + 2) * 3`.

### The Problem

Without parentheses:
```
1 + 2 * 3 = 1 + (2 * 3) = 7
```

With parentheses:
```
(1 + 2) * 3 = 3 * 3 = 9
```

We need a way to restart at `expression` from inside the tree.

---

## The Primary Rule

Rename `NUMBER` to `primary` and add the parenthesis option:

```
expression → term (("+" | "-") term)*
term       → unary (("*" | "/") unary)*
unary      → "-" unary | primary
primary    → NUMBER | "(" expression ")"
```

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

---

## Trace of `(1 + 2) * 3`

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                      PARSING "(1 + 2) * 3"                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Tokens: [LPAREN] [1] [PLUS] [2] [RPAREN] [STAR] [3]                       │
│            ▲                                                                 │
│                                                                              │
│   expression():                                                              │
│       call term():                                                           │
│           call unary():                                                      │
│               call primary():                                                │
│                   see "(" → consume it                                      │
│                                                                              │
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
│                                                                              │
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
├──────────────────────────────────────────────────────────────────────────────┤
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

---

## Visual Summary

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
│                                        └────────────────────────────────────┐│
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Precedence Levels

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

## Translating to Code

```
// Grammar:
//   expression → term (("+" | "-") term)*
//   term       → unary (("*" | "/") unary)*
//   unary      → "-" unary | primary
//   primary    → NUMBER | IDENTIFIER | "(" expression ")"

function parseExpression():
    left = parseTerm()
    while see(PLUS) or see(MINUS):
        op = advance()
        right = parseTerm()
        if op.type == PLUS:
            left = AddNode(left, right)
        else:
            left = SubNode(left, right)
    return left

function parseTerm():
    left = parseUnary()
    while see(STAR) or see(SLASH):
        op = advance()
        right = parseUnary()
        if op.type == STAR:
            left = MulNode(left, right)
        else:
            left = DivNode(left, right)
    return left

function parseUnary():
    if see(MINUS):
        advance()
        operand = parseUnary()    // Recursive!
        return NegateNode(operand)
    return parsePrimary()

function parsePrimary():
    if see(NUMBER):
        token = advance()
        return NumberNode(parseInt(token.lexeme))

    if see(IDENTIFIER):
        token = advance()
        return IdentifierNode(token.lexeme)

    if see(LPAREN):
        advance()                 // consume "("
        expr = parseExpression()  // Recursive!
        expect(RPAREN)            // consume ")"
        return expr

    error("Expected expression")
```

---

## Verify Your Implementation

### Test 1: Unary minus
```
Input:  "-5"
AST:    NegateNode {
            operand: NumberNode(5)
        }
```

### Test 2: Double negation
```
Input:  "--x"
AST:    NegateNode {
            operand: NegateNode {
                operand: IdentifierNode("x")
            }
        }
```

### Test 3: Unary with binary
```
Input:  "-2 * 3"
AST:    MulNode {
            left: NegateNode { operand: NumberNode(2) },
            right: NumberNode(3)
        }

Evaluation: (-2) * 3 = -6  ✓
```

### Test 4: Parentheses override
```
Input:  "(1 + 2) * 3"
AST:    MulNode {
            left: AddNode {
                left: NumberNode(1),
                right: NumberNode(2)
            },
            right: NumberNode(3)
        }

Evaluation: (1 + 2) * 3 = 9  ✓
```

### Test 5: Nested parentheses
```
Input:  "((1 + 2))"
AST:    AddNode {
            left: NumberNode(1),
            right: NumberNode(2)
        }

(Parentheses disappear from the tree!)
```

### Test 6: Complex expression
```
Input:  "-x * (y + z)"
AST:    MulNode {
            left: NegateNode { operand: IdentifierNode("x") },
            right: AddNode {
                left: IdentifierNode("y"),
                right: IdentifierNode("z")
            }
        }
```

---

## Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              SUMMARY                                         │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Unary operators:                                                           │
│     Rule:   unary → "-" unary | primary                                     │
│     Key:    Recursion allows multiple: --x                                  │
│     Code:   if see(MINUS): return Negate(parseUnary())                      │
│                                                                              │
│   Parentheses:                                                               │
│     Rule:   primary → NUMBER | "(" expression ")"                           │
│     Key:    Calls expression recursively                                    │
│     Code:   if see(LPAREN): parseExpression(); expect(RPAREN)               │
│                                                                              │
│   The complete expression grammar:                                           │
│     expression → term ((+ | -) term)*                                       │
│     term       → unary ((* | /) unary)*                                     │
│     unary      → - unary | primary                                          │
│     primary    → NUMBER | IDENTIFIER | ( expression )                       │
│                                                                              │
│   Expressions are now complete! They can parse:                             │
│     42, x, 1+2, 1+2*3, -5, --x, (1+2)*3, -x*(y+z)                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What's Next

We've finished expressions. Now let's parse **statements** - things that DO something like `const x = 5;` and `return x;`.

Next: [Lesson 2.5: Statements](../05-statements/) →
