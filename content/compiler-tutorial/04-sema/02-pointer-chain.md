---
title: "4.2: The Pointer Chain"
weight: 2
---

# Lesson 4.2: The Pointer Chain

How errors point back to source code.

---

## The Goal

When sema finds an error, we want to show:

```
1:19: error: undefined variable "x"
fn foo() { return x; }
                  ^
```

This requires knowing:
- Line 1, column 19
- The source code of that line
- Where to put the caret

---

## The Problem

By the time sema runs, we have ZIR instructions:

```
%2 = decl_ref("x")
```

But where did this instruction come from in the source? We need to trace back.

---

## The Pointer Chain

Instead of copying location data at each stage, we use pointers:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           POINTER CHAIN                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Error                                                                     │
│     │                                                                       │
│     └──► Instruction (ZIR)                                                  │
│            │                                                                │
│            └──► Node (AST)                                                  │
│                  │                                                          │
│                  └──► Token                                                 │
│                        │                                                    │
│                        └──► line: 1, col: 19                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Following the Chain

To get location from an error:

```
error                           // undefined_variable error
  .inst                         // → ZIR instruction (decl_ref)
    .node                       // → AST node (identifier_ref)
      .token                    // → Token
        .line, .col             // → 1, 19
```

Each level points to its source. Nothing is copied.

---

## Token: The Source of Truth

The Token is where location lives:

```
Token {
    type: TokenType,
    lexeme: []const u8,     // The actual text ("x")
    line: usize,            // Line number (1-based)
    col: usize,             // Column number (1-based)
}
```

Created by the lexer when scanning source code.

---

## AST Node: Points to Token

AST nodes that can cause errors store a pointer to their token:

```
Node = union {
    identifier_ref: struct {
        name: []const u8,
        token: *const Token,   // ← Points to the token
    },

    identifier: struct {
        name: []const u8,
        value: *const Node,
        token: *const Token,   // ← Points to the token
    },

    // ... other nodes
}
```

---

## ZIR Instruction: Points to AST Node

Instructions that can cause errors store a pointer to their AST node:

```
Instruction = union {
    decl_ref: struct {
        name: []const u8,
        node: *const Node,     // ← Points to AST node
    },

    decl: struct {
        name: []const u8,
        value: u32,
        node: *const Node,     // ← Points to AST node
    },

    // ... other instructions
}
```

---

## Error: Points to Instruction

Errors store a pointer to the instruction that caused them:

```
Error = union {
    undefined_variable: struct {
        name: []const u8,
        inst: *const Instruction,   // ← Points to instruction
    },

    duplicate_declaration: struct {
        name: []const u8,
        inst: *const Instruction,   // ← Points to instruction
    },
}
```

---

## Why Pointers?

Three benefits:

**1. Single Source of Truth**
```
Location lives only in Token.
Change it once, everywhere sees the update.
```

**2. Rich Context**
```
From an error, you can access:
  - The instruction details
  - The AST node structure
  - The original token
  - The source location
```

**3. Extensibility**
```
Add file path to Token later?
All errors get it for free.
No changes needed elsewhere.
```

---

## Getting Location from Error

```
function getToken(error) → Token:
    switch error:
        undefined_variable:
            return error.inst.decl_ref.node.identifier_ref.token

        duplicate_declaration:
            return error.inst.decl.node.identifier.token
```

The path varies by error type, but the principle is the same: follow the pointers.

---

## Memory Lifetime

For pointers to work, the data must stay alive:

```
Arena allocator ensures:
  - Tokens live for entire compilation
  - AST nodes live for entire compilation
  - Instructions live for entire compilation
  - Errors can safely point to any of them

No dangling pointers!
```

---

## Alternative: Copy Everything (Don't Do This)

```
// BAD: Copying location at each level
Instruction {
    name: "x",
    line: 1,        // Copied from Node
    col: 19,        // Copied from Node
}

Error {
    name: "x",
    line: 1,        // Copied from Instruction
    col: 19,        // Copied from Instruction
}

// Problems:
// - Duplicated data everywhere
// - Changes don't propagate
// - More memory used
```

---

## The Complete Picture

```
Source: "fn foo() { return x; }"
              col: 19 ────────┘

Lexer creates:
    Token { lexeme: "x", line: 1, col: 19 }

Parser creates:
    Node.identifier_ref { name: "x", token: ──► Token }

ZIR creates:
    Instruction.decl_ref { name: "x", node: ──► Node }

Sema creates:
    Error.undefined_variable { name: "x", inst: ──► Instruction }

Error formatting follows chain:
    Error → Instruction → Node → Token → (line: 1, col: 19)

Output:
    1:19: error: undefined variable "x"
    fn foo() { return x; }
                      ^
```

---

## Verify Your Understanding

### Question 1
If we add `filename: []const u8` to Token, what changes are needed elsewhere?

**Answer:** Nothing. Error formatting can access `error.inst...token.filename` automatically.

### Question 2
Why does `identifier_ref` need a token pointer but `constant` doesn't?

**Answer:** Constants can't cause name-related errors. Only nodes that might trigger errors need location info.

### Question 3
What happens if we use a stack variable instead of arena-allocated data?

**Answer:** Dangling pointer! The pointer would point to freed memory after the function returns.

---

## What's Next

Now that we understand how errors point to source, let's build the name tracking system.

Next: [Lesson 4.3: Tracking Names](../03-tracking-names/) →
