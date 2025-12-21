---
title: "Section 2: The Parser"
weight: 2
---

# Section 2: The Parser

The parser transforms a flat stream of tokens into a tree structure.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           WHAT THE PARSER DOES                               │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Input:  Flat token stream                                                 │
│           [1] [+] [2] [*] [3]                                               │
│                                                                              │
│   Output: Tree structure                                                    │
│                  Add                                                         │
│                 /   \                                                        │
│                1    Mul                                                      │
│                    /   \                                                     │
│                   2     3                                                    │
│                                                                              │
│   The tree captures STRUCTURE and PRECEDENCE.                               │
│   * is nested inside +, so it happens first!                                │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## The Core Approach

We'll design a **grammar** first - rules that describe valid programs. Then we'll translate those rules directly into parser code.

```
Grammar Rule                    →    Parser Function
────────────────────────────         ─────────────────
expression → term ((+|-) term)*  →   parseExpression()
term → unary ((*|/) unary)*      →   parseTerm()
unary → - unary | primary        →   parseUnary()
primary → NUMBER | ( expr )      →   parsePrimary()
```

Each rule becomes one function. **The grammar IS the parser.**

---

## Lessons in This Section

| Lesson | Topic | What You'll Learn |
|--------|-------|-------------------|
| [1. Grammar Basics](01-grammar-basics/) | What is a grammar? | Why we need rules, notation |
| [2. Repetition](02-repetition/) | Handling chains | `1 + 2 + 3` with loops |
| [3. Precedence](03-precedence/) | Operator priority | Why `*` beats `+` |
| [4. Unary & Parens](04-unary-parens/) | Complete expressions | `-x` and `(1 + 2)` |
| [5. Statements](05-statements/) | Doing things | `const x = 5;` and `return` |
| [6. Functions](06-functions/) | Declarations | `fn name() { ... }` |
| [7. Complete Parser](07-complete/) | Everything together | Full working parser |

---

## The Grammar We'll Build

By the end, you'll understand this complete grammar:

```
program     → function*
function    → "fn" IDENTIFIER "(" parameters? ")" block
parameters  → parameter ("," parameter)*
parameter   → IDENTIFIER ":" type
block       → "{" statement* "}"
statement   → var_decl | return_stmt
var_decl    → "const" IDENTIFIER "=" expression ";"
return_stmt → "return" expression ";"
expression  → term (("+" | "-") term)*
term        → unary (("*" | "/") unary)*
unary       → "-" unary | primary
primary     → NUMBER | IDENTIFIER | "(" expression ")"
```

And you'll be able to parse programs like:

```
fn add(a: i32, b: i32) {
    const result = a + b;
    return result;
}
```

---

## Start Here

Begin with [Lesson 1: Grammar Basics](01-grammar-basics/) →
