---
title: "Build Your Own Compiler"
description: "A step-by-step guide to building a working compiler from scratch"
---

# Build Your Own Compiler

A hands-on, language-agnostic guide to building a compiler in under 1,000 lines of code.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         THE COMPILER PIPELINE                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   "fn add(a, b) { return a + b; }"                                          │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────┐                                   │
│   │  SECTION 1: LEXER                   │                                   │
│   │  Break text into tokens             │                                   │
│   └─────────────────────────────────────┘                                   │
│                    │                                                         │
│                    ▼                                                         │
│   [fn] [add] [(] [a] [,] [b] [)] [{] [return] [a] [+] [b] [;] [}]          │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────┐                                   │
│   │  SECTION 2: PARSER                  │                                   │
│   │  Build Abstract Syntax Tree         │                                   │
│   └─────────────────────────────────────┘                                   │
│                    │                                                         │
│                    ▼                                                         │
│   FnDecl("add", [a, b], Block(Return(Add(a, b))))                          │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────┐                                   │
│   │  SECTION 3: ZIR                     │                                   │
│   │  Flatten to linear instructions     │                                   │
│   └─────────────────────────────────────┘                                   │
│                    │                                                         │
│                    ▼                                                         │
│   %0 = param_ref(0)    // "a" - name not resolved yet                       │
│   %1 = param_ref(1)    // "b"                                               │
│   %2 = add(%0, %1)     // no type yet                                       │
│   %3 = ret(%2)                                                              │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────┐                                   │
│   │  SECTION 4: SEMA                    │                                   │
│   │  Type check, resolve names          │                                   │
│   └─────────────────────────────────────┘                                   │
│                    │                                                         │
│                    ▼                                                         │
│   %0 = param(0): i32   // typed!                                            │
│   %1 = param(1): i32   // typed!                                            │
│   %2 = add(%0, %1): i32                                                     │
│   %3 = ret(%2): i32                                                         │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────┐                                   │
│   │  SECTION 5: CODEGEN                 │                                   │
│   │  Generate output code               │                                   │
│   └─────────────────────────────────────┘                                   │
│                    │                                                         │
│                    ▼                                                         │
│   int32_t add(int32_t p0, int32_t p1) {                                     │
│       return p0 + p1;                                                        │
│   }                                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## What You'll Build

A compiler that transforms this:
```
fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn main() i32 {
    const x: i32 = 5;
    const y: i32 = 3;
    return add(x, y);
}
```

Into runnable C code (or bytecode, or LLVM IR).

---

## What You'll Learn

| Section | What You Build | Key Concept |
|---------|---------------|-------------|
| [1. Lexer](01-lexer/) | Tokenizer | State machine, character classification |
| [2. Parser](02-parser/) | AST builder | Recursive descent, precedence climbing |
| [3. ZIR](03-zir/) | IR generator | Flattening trees, instruction references |
| [4. Sema](04-sema/) | Type checker | Symbol tables, type inference |
| [5. Codegen](05-codegen/) | Code generator | Target-specific output |
| [6. Complete](06-complete/) | Full compiler | Integration, testing |

---

## Design Principles

This tutorial follows these principles:

**1. Language-Agnostic**
- Instructions describe WHAT to build, not HOW in a specific language
- Implement in Zig, TypeScript, Go, Rust, Python - your choice
- Pseudo-code shows the logic; you write the real code

**2. Baby Steps**
- Each lesson adds ONE small thing
- Complete and test before moving on
- Build confidence through small wins

**3. Testable**
- Every lesson ends with test cases
- Verify your implementation works before proceeding
- Tests catch bugs early

**4. Real-World Architecture**
- Same stages as production compilers (GCC, LLVM, Zig)
- Understand why each stage exists
- Transferable knowledge

---

## Prerequisites

- Basic programming ability in any language
- Understanding of functions, loops, conditionals
- No prior compiler experience needed!

---

## Getting Started

Start with [Section 1: The Lexer](01-lexer/) →
