---
title: "Section 2: The Parser"
weight: 2
---

# Section 2: The Parser

The parser transforms a flat stream of tokens into a tree structure that represents the program's meaning.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           WHAT THE PARSER DOES                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Input:  [CONST] [IDENT:x] [EQUAL] [NUMBER:3] [PLUS] [NUMBER:5] [SEMI]     │
│                                                                              │
│   Output:                                                                    │
│                        ConstDecl                                             │
│                       /        \                                             │
│                   name:"x"     Add                                           │
│                               /   \                                          │
│                           Num:3   Num:5                                      │
│                                                                              │
│   The tree shows STRUCTURE:                                                  │
│   ✓ "x" is being assigned                                                   │
│   ✓ The value is an addition                                                │
│   ✓ Addition has two operands (3 and 5)                                     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Why Trees?

Tokens are flat. But code has structure:

```
3 + 5 * 2

Tokens: [3] [+] [5] [*] [2]   ← Flat, no structure

Tree:        +                 ← Shows * happens first!
            / \
           3   *
              / \
             5   2
```

The tree captures operator precedence: multiply first, then add.

---

## Lessons in This Section

| Lesson | Topic | What You'll Add |
|--------|-------|-----------------|
| [1. AST Nodes](01-ast-nodes/) | Node types | Define what AST nodes look like |
| [2. Atoms](02-atoms/) | Simple expressions | Numbers, identifiers |
| [3. Grouping](03-grouping/) | Parentheses | `(expression)` |
| [4. Unary](04-unary/) | Unary operators | `-x` |
| [5. Binary Simple](05-binary-simple/) | Binary operators | `a + b` (no precedence) |
| [6. Precedence](06-precedence/) | Binding power | Why `*` beats `+` |
| [7. Precedence Impl](07-precedence-impl/) | Climbing algorithm | The actual implementation |
| [8. Statements](08-statements/) | Statements | `return`, `const`, `var` |
| [9. Blocks](09-blocks/) | Code blocks | `{ stmt; stmt; }` |
| [10. Functions](10-functions/) | Function declarations | `fn name(...) { ... }` |
| [11. Complete Parser](11-putting-together/) | Integration | Full parser with tests |

---

## What You'll Build

By the end of this section, you can parse:

```
fn add(a: i32, b: i32) i32 {
    const result: i32 = a + b;
    return result;
}
```

Into an AST like:

```
Root
└── FnDecl("add")
    ├── params: [("a", i32), ("b", i32)]
    ├── return_type: i32
    └── body: Block
        ├── ConstDecl("result", i32)
        │   └── value: Binary(+)
        │       ├── left: Identifier("a")
        │       └── right: Identifier("b")
        └── Return
            └── value: Identifier("result")
```

---

## Parsing Technique: Recursive Descent

We'll use **recursive descent parsing** - the most intuitive approach:

```
To parse a function:
    1. Expect "fn" keyword
    2. Parse the name (identifier)
    3. Parse the parameters (call parseParams)
    4. Parse the return type
    5. Parse the body (call parseBlock)

Each "call parseX" recursively parses that construct.
```

This mirrors how you'd describe the grammar in English.

---

## Start Here

Begin with [Lesson 1: AST Nodes](01-ast-nodes/) →
